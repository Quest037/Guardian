import Combine
import Foundation

// MARK: - User overrides + catalog resolution (MCR / export)

/// Optional per-`templateKey` `{{param}}` patterns for Mission Control room display.
/// User entries apply only to ``GuardianStructuredLogLinePresentation/missionControlRoom``;
/// copy/export uses catalog defaults via ``MissionRunEvent/plainTextLine``.
@MainActor
final class MissionRunLogTemplateRegistry: ObservableObject {
    static let shared = MissionRunLogTemplateRegistry()

    @Published private(set) var templates: [String: String] = [:]

    private init() {}

    func setTemplates(_ entries: [String: String]) {
        var copy = templates
        copy.merge(entries) { _, new in new }
        templates = copy
    }

    func setTemplate(_ key: String, pattern: String) {
        var copy = templates
        copy[key] = pattern
        templates = copy
    }

    func removeTemplate(forKey key: String) {
        var copy = templates
        copy.removeValue(forKey: key)
        templates = copy
    }

    func clearTemplates() {
        templates = [:]
    }

    /// Mission Control room live log body (user `templates` override, then catalog MCR line, then default, then `event.message`).
    func resolveDisplayBody(for event: MissionRunEvent) -> String {
        resolveBody(for: event, presentation: .missionControlRoom)
    }

    /// `plainExport` ignores user `templates` entries so copy/export stays on catalog defaults.
    func resolveBody(for event: MissionRunEvent, presentation: GuardianStructuredLogLinePresentation) -> String {
        guard let key = event.templateKey else { return event.message }
        switch presentation {
        case .missionControlRoom:
            if let pattern = templates[key], !pattern.isEmpty {
                return StructuredLogTemplateCatalog.interpolate(pattern, params: event.templateParams)
            }
            if let pattern = StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom) {
                return StructuredLogTemplateCatalog.interpolate(pattern, params: event.templateParams)
            }
            return event.message
        case .plainExport:
            if let pattern = StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport) {
                return StructuredLogTemplateCatalog.interpolate(pattern, params: event.templateParams)
            }
            return event.message
        }
    }
}

extension MissionRunEvent {
    /// Plain line for copy / print (no colours). Uses ``StructuredLogTemplateCatalog`` defaults
    /// (``GuardianStructuredLogLinePresentation/plainExport``); ignores user MCR overrides in the registry.
    /// Format: `[Wrapper][Speaker] @target body`.
    @MainActor
    func plainTextLine(
        templateRegistry: MissionRunLogTemplateRegistry = .shared,
        mission: Mission? = nil,
        assignments: [MissionRunAssignment] = []
    ) -> String {
        let rawBody = templateRegistry.resolveBody(for: self, presentation: .plainExport)
        let body = Self.resolvePlainMentions(in: rawBody, mission: mission, assignments: assignments)
        let taskNameForPrefix = resolvedTaskLogPrefix(mission: mission, assignments: assignments)
        let pathPart = taskNameForPrefix.map { "[\($0)]" } ?? ""
        let speakerPart: String
        switch speaker {
        case .missionControl: speakerPart = "[MissionControl]"
        case .assistant(let key):
            speakerPart = "[\(MissionRunAssistantRegistry.shared.displayName(forKey: key))]"
        case .vehicleSlot(let slot): speakerPart = "[\(slot)]"
        case .operator(let displayName):
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            speakerPart = trimmed.isEmpty ? "[Operator]" : "[Operator][\(trimmed)]"
        }
        let prefix = pathPart.isEmpty ? speakerPart : "\(pathPart)\(speakerPart)"
        let targetPart = "@" + plainTargetName(effectiveTarget, assignments: assignments)
        let sevSuffix: String
        switch level {
        case .info: sevSuffix = ""
        case .warning: sevSuffix = " · warn"
        case .error: sevSuffix = " · error"
        }
        return "\(prefix) \(targetPart) \(body)\(sevSuffix)"
    }

    /// Plain-text `@<uuid>` mention resolver. Walks the body, finds `@<UUID>` substrings, and
    /// replaces them with `@<displayName>` (task name from `mission` or slot callsign from
    /// `assignments`). Unknown UUIDs become `@deleted` so exports surface stale references rather
    /// than dumping raw ids. Mirrors the renderer-side ``buildAttributedBody`` matcher so plain
    /// export and MCR rendering stay aligned on what an `@`-handle resolves to.
    static func resolvePlainMentions(
        in body: String,
        mission: Mission?,
        assignments: [MissionRunAssignment]
    ) -> String {
        guard body.contains("@") else { return body }
        var result = ""
        result.reserveCapacity(body.count)
        var i = body.startIndex
        while i < body.endIndex {
            if body[i] == "@" {
                let after = body.index(after: i)
                if let uuidEnd = body.index(after, offsetBy: 36, limitedBy: body.endIndex) {
                    let candidate = String(body[after..<uuidEnd])
                    if let uuid = UUID(uuidString: candidate) {
                        if let assignment = assignments.first(where: { $0.id == uuid }) {
                            result.append("@")
                            result.append(assignment.slotName.isEmpty
                                ? "slot:\(uuid.uuidString.prefix(8))"
                                : assignment.slotName)
                            i = uuidEnd
                            continue
                        }
                        if let task = mission?.routeMacro.tasks.first(where: { $0.id == uuid }) {
                            result.append("@")
                            result.append(task.name.isEmpty
                                ? "task:\(uuid.uuidString.prefix(8))"
                                : task.name)
                            i = uuidEnd
                            continue
                        }
                        result.append("@deleted")
                        i = uuidEnd
                        continue
                    }
                }
            }
            result.append(body[i])
            i = body.index(after: i)
        }
        return result
    }

    /// `@MainActor`-isolated because it reads ``MissionRunAssistantRegistry/shared`` (a MainActor
    /// singleton); only called from ``plainTextLine`` which is already `@MainActor`. Slot targets
    /// resolve their callsign from `assignments` (id-keyed); deletion / unknown slot falls back to
    /// `slot:<short uuid>` so the export is always self-describing.
    @MainActor
    private func plainTargetName(
        _ target: MissionRunEventTarget,
        assignments: [MissionRunAssignment]
    ) -> String {
        switch target {
        case .missionControl: return "missionControl"
        case .assistant(let key):
            let name = MissionRunAssistantRegistry.shared.displayName(forKey: key)
            return name.isEmpty ? key : name.lowercased()
        case .task(_, let name): return name
        case .slot(let id):
            if let name = assignments.first(where: { $0.id == id })?.slotName, !name.isEmpty {
                return name
            }
            return "slot:\(id.uuidString.prefix(8))"
        case .operator(let displayName):
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "operator" : trimmed
        }
    }
}
