// MissionControlCompletedView.swift — MC-C: completed-run report cards and mission log export (`MissionRunDetailView`).
import AppKit
import Foundation
import SwiftUI

extension MissionRunDetailView {
    var missionCompletedReportCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mission report")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                MissionRunStatusBadge(status: .completed)
            }

            completedOutcomeCard
            completedScheduleCyclesCard
            completedTimelineCard
            completedRosterCard
            completedMissionLogHealthCard
        }
    }

    var completedOutcomeCard: some View {
        let accent = completedOutcomeAccent
        return completedReportCardChrome(title: "Outcome", accent: accent) {
            Text(completedOutcomeTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(completedOutcomeDetail)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var completedOutcomeAccent: Color {
        switch run.completionKind {
        case .oneOffAutopilotFinished:
            return Color.green.opacity(0.75)
        case .operatorStoppedAfterCycle:
            return Color.blue.opacity(0.8)
        case .operatorStoppedImmediate:
            return Color.orange.opacity(0.85)
        case .operatorCompletedImmediate, .operatorCompletedAfterCycle:
            return Color.green.opacity(0.72)
        case .none:
            return Color.gray.opacity(0.55)
        }
    }

    var completedOutcomeTitle: String {
        switch run.completionKind {
        case .operatorStoppedImmediate:
            return "Stopped by operator"
        case .operatorStoppedAfterCycle:
            return "Stopped after current cycle"
        case .operatorCompletedImmediate:
            return "Completed by operator (recovery)"
        case .operatorCompletedAfterCycle:
            return "Completed after current cycle (recovery)"
        case .oneOffAutopilotFinished:
            return "Mission finished"
        case .none:
            return "Run completed"
        }
    }

    var completedOutcomeDetail: String {
        switch run.completionKind {
        case .operatorStoppedImmediate:
            return "The run was ended immediately (vehicles were commanded home / RTL where applicable)."
        case .operatorStoppedAfterCycle:
            return "The active mission cycle was allowed to finish, then the run ended."
        case .operatorCompletedImmediate:
            return "The run moved to recovery immediately using your complete policy (not the abort policy)."
        case .operatorCompletedAfterCycle:
            return "The active mission cycle was allowed to finish, then the run moved to recovery using your complete policy."
        case .oneOffAutopilotFinished:
            return "The mission cycle completed and the run ended."
        case .none:
            return "This run is marked complete. Older runs may not store a detailed outcome."
        }
    }

    var completedScheduleCyclesCard: some View {
        completedReportCardChrome(title: "Timing & cycles", accent: Color.white.opacity(0.2)) {
            if let t = run.oneOffStartAt {
                labeledReportRow("Planned start", t.formatted(date: .abbreviated, time: .shortened))
            } else {
                labeledReportRow("Planned start", "When started (no deferred start)")
            }
            let cycles = run.reportCyclesCompleted ?? 0
            labeledReportRow(
                "Mission cycles completed",
                "\(cycles)"
            )
        }
    }

    var completedTimelineCard: some View {
        completedReportCardChrome(title: "Timeline", accent: Color.white.opacity(0.2)) {
            labeledReportRow("Created", run.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let s = run.startedAt {
                labeledReportRow("Started", s.formatted(date: .abbreviated, time: .shortened))
            } else {
                labeledReportRow("Started", "—")
            }
            if let e = run.completedAt {
                labeledReportRow("Completed", e.formatted(date: .abbreviated, time: .shortened))
            }
            if let dur = completedRunDurationFormatted {
                labeledReportRow("Elapsed (start → complete)", dur)
            }
        }
    }

    var completedRunDurationFormatted: String? {
        guard let s = run.startedAt, let e = run.completedAt else { return nil }
        let sec = max(0, e.timeIntervalSince(s))
        if sec < 60 { return String(format: "%.0f s", sec) }
        let m = Int(sec / 60)
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let rm = m % 60
        return "\(h) h \(rm) min"
    }

    var completedRosterCard: some View {
        completedReportCardChrome(title: "Roster", accent: Color.white.opacity(0.2)) {
            if run.assignments.isEmpty {
                Text("No roster slots.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(run.assignments) { a in
                        let bound = a.attachedFleetVehicleToken != nil || !a.attachedDevice.isEmpty
                        Text("• \(a.slotName)\(bound ? "" : " — unassigned")")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    var completedMissionLogHealthCard: some View {
        let errs = completedMissionLogErrorCount
        let warns = completedMissionLogWarningCount
        let accent: Color = errs > 0 ? Color.red.opacity(0.8) : (warns > 0 ? Color.orange.opacity(0.8) : Color.green.opacity(0.65))
        return completedReportCardChrome(title: "Mission log health", accent: accent) {
            if run.events.isEmpty {
                Text("No mission log entries are stored for this run.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            } else {
                let events = run.events.count
                labeledReportRow("Events recorded", "\(events)")
                labeledReportRow("Warnings", "\(warns)")
                labeledReportRow("Errors", "\(errs)")
                if errs == 0, warns == 0 {
                    Text("No warnings or errors in the mission log.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.top, 4)
                }
            }
        }
    }

    var completedMissionLogErrorCount: Int {
        run.events.filter { $0.level == .error }.count
    }

    var completedMissionLogWarningCount: Int {
        run.events.filter { $0.level == .warning }.count
    }

    var completedMissionLogExportSection: some View {
        let text = liveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Mission log")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                GuardianThemedButton(
                    title: "Copy",
                    accent: .primary,
                    surface: .solid,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !text.isEmpty,
                    action: { copyCompletedLog() }
                )

                GuardianThemedButton(
                    title: "Save…",
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !text.isEmpty,
                    action: { saveCompletedLog() }
                )

                GuardianThemedButton(
                    title: "Print…",
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !text.isEmpty,
                    action: { printCompletedLog() }
                )
            }

            if text.isEmpty {
                Text("No mission log entries for this run.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 220, idealHeight: 320, maxHeight: 480)
                .padding(10)
                .background(theme.backgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func completedReportCardChrome<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                content()
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func labeledReportRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    func copyCompletedLog() {
        guard !run.events.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(
            liveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan),
            forType: .string
        )
    }

    func saveCompletedLog() {
        guard !run.events.isEmpty else { return }
        let text = liveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "Save mission log"
        let safeName = run.missionName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName)-mission-log.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                // Best-effort export; avoid crashing the UI.
            }
        }
    }

    func printCompletedLog() {
        guard !run.events.isEmpty else { return }
        let text = liveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 2000))
        tv.string = text
        tv.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.isEditable = false
        tv.drawsBackground = false
        let op = NSPrintOperation(view: tv, printInfo: NSPrintInfo.shared)
        op.jobTitle = "\(run.missionName) — Mission log"
        op.run()
    }
}
