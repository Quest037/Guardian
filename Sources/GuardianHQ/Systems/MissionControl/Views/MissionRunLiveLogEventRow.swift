import SwiftUI

/// One MC‑R / Live Drive mission log line: severity rail + wrapper + speaker + attributed `@target` + body (matches ``MissionControlSetupView`` live log strip).
@MainActor
struct MissionRunLiveLogEventRow: View {
    let event: MissionRunEvent
    @ObservedObject var run: MissionRunEnvironment
    let mission: Mission?
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject private var logTemplateRegistry = MissionRunLogTemplateRegistry.shared

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        let routeTint: Color? = {
            guard let pid = event.taskID, let mission else { return nil }
            if let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == pid }) {
                return MissionTaskMapColor.swiftUIColor(forTaskIndex: idx)
            }
            return nil
        }()
        let routeTextColor = routeTint ?? Color.gray.opacity(0.85)
        let speakerColor: Color = {
            switch event.speaker {
            case .missionControl, .assistant, .operator:
                return theme.textPrimary
            case .vehicleSlot(let slot):
                return slotSpeakerColor(slotName: slot)
            }
        }()
        let bodyColor: Color = {
            switch event.level {
            case .info: return Color.gray.opacity(0.92)
            case .warning: return Color.orange.opacity(0.88)
            case .error: return Color.red.opacity(0.9)
            }
        }()

        var line = Text(verbatim: "")
        if let pl = event.resolvedTaskLogPrefix(mission: mission, assignments: run.assignments) {
            line = line + Text(verbatim: "[\(pl)]").foregroundColor(routeTextColor)
        }
        line = line + speakerLogText(event.speaker, color: speakerColor)
        line = line + Text(attributedTargetAndBody(event: event, defaultColor: bodyColor))

        return HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(logSeverityBorderColor(event.level))
                .frame(width: 3)
            line
                .font(GuardianTypography.font(.telemetryMono11Regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, GuardianSpacing.xsTight)
                .padding(.vertical, GuardianSpacing.micro)
        }
        .textSelection(.enabled)
    }

    private func logSeverityBorderColor(_ level: MissionRunEventLevel) -> Color {
        switch level {
        case .info: return Color.white.opacity(0.22)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }

    private func speakerLogText(_ speaker: MissionRunEventSpeaker, color: Color) -> Text {
        switch speaker {
        case .missionControl:
            return Text(verbatim: "[MissionControl]").foregroundColor(color)
        case .assistant(let key):
            let name = MissionRunAssistantRegistry.shared.displayName(forKey: key)
            return Text(verbatim: "[\(name)]").foregroundColor(color)
        case .vehicleSlot(let s):
            return Text(verbatim: "[\(s)]").foregroundColor(color)
        case .operator(let displayName):
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Text(verbatim: trimmed.isEmpty ? "[Operator]" : "[Operator][\(trimmed)]")
                .foregroundColor(color)
        }
    }

    private func attributedTargetAndBody(event: MissionRunEvent, defaultColor: Color) -> AttributedString {
        var result = AttributedString("")
        var leadingSpace = AttributedString(" ")
        leadingSpace.foregroundColor = defaultColor
        result.append(leadingSpace)

        let target = event.effectiveTarget
        var mention = AttributedString("@\(mcrTargetDisplayName(target))")
        mention.foregroundColor = mcrTargetColor(target)
        if let url = mcrTargetLinkURL(target) {
            mention.link = url
        }
        result.append(mention)

        let body = " " + logTemplateRegistry.resolveDisplayBody(for: event)
        result.append(buildAttributedBody(body, defaultColor: defaultColor))
        return result
    }

    private func buildAttributedBody(_ body: String, defaultColor: Color) -> AttributedString {
        struct NameCandidate {
            let name: String
            let color: Color
            let url: URL?
        }
        var nameCandidates: [NameCandidate] = []
        if let mission {
            let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
            let enabledTaskCount = enabledTasks.count
            for (idx, task) in mission.routeMacro.tasks.enumerated() where !task.name.isEmpty {
                nameCandidates.append(
                    NameCandidate(
                        name: task.name,
                        color: MissionTaskMapColor.swiftUIColor(forTaskIndex: idx),
                        url: URL(string: "guardian://mcr/task/\(task.id.uuidString)")
                    )
                )
                let primaries = MissionControlSquadUtilities.orderedPrimarySquads(
                    task: task,
                    assignments: run.assignments,
                    rosterDevices: mission.rosterDevices,
                    enabledTaskCount: enabledTaskCount
                )
                if primaries.count > 1 {
                    for i in 0..<primaries.count {
                        let label = MissionControlSquadUtilities.squadDisplayName(taskName: task.name, squadIndex: i)
                        nameCandidates.append(
                            NameCandidate(
                                name: label,
                                color: MissionTaskMapColor.swiftUIColor(forTaskIndex: idx),
                                url: URL(string: "guardian://mcr/task/\(task.id.uuidString)")
                            )
                        )
                    }
                }
            }
        }
        for assignment in run.assignments where !assignment.slotName.isEmpty {
            nameCandidates.append(
                NameCandidate(
                    name: assignment.slotName,
                    color: slotSpeakerColor(slotName: assignment.slotName),
                    url: URL(string: "guardian://mcr/slot/\(assignment.id.uuidString)")
                )
            )
        }
        nameCandidates.sort { $0.name.count > $1.name.count }

        let mutedColor = Color.gray.opacity(0.6)
        let deletedDisplay = "deleted"

        var result = AttributedString("")
        var i = body.startIndex
        var pending = ""

        func flushPending() {
            if !pending.isEmpty {
                var p = AttributedString(pending)
                p.foregroundColor = defaultColor
                result.append(p)
                pending = ""
            }
        }

        func appendMention(display: String, color: Color, url: URL?) {
            flushPending()
            var mention = AttributedString("@\(display)")
            mention.foregroundColor = color
            if let url { mention.link = url }
            result.append(mention)
        }

        while i < body.endIndex {
            if body[i] == "@" {
                let after = body.index(after: i)

                if let uuidEnd = body.index(after, offsetBy: 36, limitedBy: body.endIndex) {
                    let candidate = String(body[after..<uuidEnd])
                    if let uuid = UUID(uuidString: candidate) {
                        if let assignment = run.assignments.first(where: { $0.id == uuid }) {
                            appendMention(
                                display: assignment.slotName.isEmpty
                                    ? "slot:\(uuid.uuidString.prefix(8))"
                                    : assignment.slotName,
                                color: slotSpeakerColor(slotName: assignment.slotName),
                                url: URL(string: "guardian://mcr/slot/\(uuid.uuidString)")
                            )
                            i = uuidEnd
                            continue
                        }
                        if let mission,
                           let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == uuid }) {
                            let task = mission.routeMacro.tasks[idx]
                            appendMention(
                                display: task.name.isEmpty ? "task:\(uuid.uuidString.prefix(8))" : task.name,
                                color: MissionTaskMapColor.swiftUIColor(forTaskIndex: idx),
                                url: URL(string: "guardian://mcr/task/\(uuid.uuidString)")
                            )
                            i = uuidEnd
                            continue
                        }
                        appendMention(display: deletedDisplay, color: mutedColor, url: nil)
                        i = uuidEnd
                        continue
                    }
                }

                let suffix = body[after...]
                if let match = nameCandidates.first(where: { suffix.hasPrefix($0.name) }) {
                    appendMention(display: match.name, color: match.color, url: match.url)
                    i = body.index(i, offsetBy: match.name.count + 1)
                    continue
                }
            }
            pending.append(body[i])
            i = body.index(after: i)
        }
        flushPending()
        return result
    }

    private func mcrTargetDisplayName(_ target: MissionRunEventTarget) -> String {
        switch target {
        case .missionControl: return "missionControl"
        case .assistant(let key):
            let name = MissionRunAssistantRegistry.shared.displayName(forKey: key)
            return name.isEmpty ? key : name.lowercased()
        case .task(_, let name): return name
        case .slot(let id):
            if let name = run.assignments.first(where: { $0.id == id })?.slotName, !name.isEmpty {
                return name
            }
            return "slot:\(id.uuidString.prefix(8))"
        case .operator(let displayName):
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "operator" : trimmed
        }
    }

    private func mcrTargetColor(_ target: MissionRunEventTarget) -> Color {
        switch target {
        case .missionControl, .assistant, .operator:
            return theme.textPrimary
        case .task(let id, _):
            if let mission, let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == id }) {
                return MissionTaskMapColor.swiftUIColor(forTaskIndex: idx)
            }
            return Color.gray.opacity(0.85)
        case .slot(let id):
            if let name = run.assignments.first(where: { $0.id == id })?.slotName, !name.isEmpty {
                return slotSpeakerColor(slotName: name)
            }
            return Color.gray.opacity(0.6)
        }
    }

    private func mcrTargetLinkURL(_ target: MissionRunEventTarget) -> URL? {
        switch target {
        case .missionControl, .assistant, .operator:
            return nil
        case .task(let id, _):
            return URL(string: "guardian://mcr/task/\(id.uuidString)")
        case .slot(let id):
            return URL(string: "guardian://mcr/slot/\(id.uuidString)")
        }
    }

    private func slotSpeakerColor(slotName: String) -> Color {
        guard let a = run.assignments.first(where: { $0.slotName == slotName }),
              let vid = resolvedFleetStreamVehicleID(assignment: a, fleetLink: fleetLink, sitl: sitl)
        else { return Color.gray.opacity(0.9) }
        return colorFromMapHex(fleetLink.mapColorHex(forVehicleID: vid))
    }

    private func colorFromMapHex(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else {
            return Color(red: 0.55, green: 0.55, blue: 0.58)
        }
        let r = Double((n >> 16) & 0xFF) / 255
        let g = Double((n >> 8) & 0xFF) / 255
        let b = Double(n & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}
