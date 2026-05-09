// MissionControlCompletedView.swift — MC-C: completed-run report cards and Paladin log export (`MissionRunDetailView`).
import AppKit
import Foundation
import SwiftUI

extension MissionRunDetailView {
    var missionCompletedReportCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mission report")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                Spacer()
                MissionRunStatusBadge(status: .completed)
            }

            completedOutcomeCard
            completedScheduleCyclesCard
            completedTimelineCard
            completedRosterCard
            completedPaladinHealthCard
        }
    }

    var completedOutcomeCard: some View {
        let accent = completedOutcomeAccent
        return completedReportCardChrome(title: "Outcome", accent: accent) {
            Text(completedOutcomeTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
            Text(completedOutcomeDetail)
                .font(.system(size: 13))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
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
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(run.assignments) { a in
                        let bound = a.attachedFleetVehicleToken != nil || !a.attachedDevice.isEmpty
                        Text("• \(a.slotName)\(bound ? "" : " — unassigned")")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                    }
                }
            }
        }
    }

    var completedPaladinHealthCard: some View {
        let errs = completedPaladinErrorCount
        let warns = completedPaladinWarningCount
        let accent: Color = errs > 0 ? Color.red.opacity(0.8) : (warns > 0 ? Color.orange.opacity(0.8) : Color.green.opacity(0.65))
        return completedReportCardChrome(title: "Paladin log health", accent: accent) {
            if run.events.isEmpty {
                Text("No mission log entries are stored for this run.")
                    .font(.system(size: 13))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                let events = run.events.count
                labeledReportRow("Events recorded", "\(events)")
                labeledReportRow("Warnings", "\(warns)")
                labeledReportRow("Errors", "\(errs)")
                if errs == 0, warns == 0 {
                    Text("No warnings or errors in the Paladin log.")
                        .font(.system(size: 12))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
                        .padding(.top, 4)
                }
            }
        }
    }

    var completedPaladinErrorCount: Int {
        run.events.filter { $0.level == .error }.count
    }

    var completedPaladinWarningCount: Int {
        run.events.filter { $0.level == .warning }.count
    }

    var completedPaladinLogExportSection: some View {
        let text = paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Paladin log")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                Spacer()
                Button("Copy") {
                    copyCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)

                Button("Save…") {
                    saveCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)

                Button("Print…") {
                    printCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)
            }

            if text.isEmpty {
                Text("No mission log entries for this run.")
                    .font(.system(size: 13))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 220, idealHeight: 320, maxHeight: 480)
                .padding(10)
                .background(GuardianDynamicColors.backgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(GuardianDynamicColors.borderSubtle, lineWidth: 1)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
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
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                content()
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func labeledReportRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    func copyCompletedPaladinLog() {
        guard !run.events.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(
            paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan),
            forType: .string
        )
    }

    func saveCompletedPaladinLog() {
        guard !run.events.isEmpty else { return }
        let text = paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "Save Paladin log"
        let safeName = run.missionName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName)-paladin-log.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                // Best-effort export; avoid crashing the UI.
            }
        }
    }

    func printCompletedPaladinLog() {
        guard !run.events.isEmpty else { return }
        let text = paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 2000))
        tv.string = text
        tv.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.isEditable = false
        tv.drawsBackground = false
        let op = NSPrintOperation(view: tv, printInfo: NSPrintInfo.shared)
        op.jobTitle = "\(run.missionName) — Paladin log"
        op.run()
    }
}
