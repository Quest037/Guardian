// MissionControlCompletedView.swift — MC-C: completed-run report cards and mission log export (`MissionRunDetailView`).
import AppKit
import Foundation
import SwiftUI

extension MissionRunDetailView {
    var missionCompletedReportCards: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mission report")
                    .font(GuardianTypography.relativeFixed(size: 18, weight: .bold, relativeTo: .title3))
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
        completedReportGuardianCard(title: "Outcome", border: completedOutcomeBorder) {
            Text(completedOutcomeTitle)
                .font(GuardianTypography.font(.windowHeading16Semibold))
                .foregroundStyle(theme.textPrimary)
            Text(completedOutcomeDetail)
                .font(GuardianTypography.font(.denseSubsection13Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Semantic ``GuardianCardBorder`` for how the run ended (same vocabulary as the rest of the app — no in-body tint bars).
    private var completedOutcomeBorder: GuardianCardBorder {
        switch run.completionKind {
        case .operatorStoppedImmediate:
            return .warning
        case .operatorStoppedAfterCycle:
            return .primary
        case .operatorCompletedImmediate, .operatorCompletedAfterCycle:
            return .subtle
        case .oneOffAutopilotFinished:
            return .subtle
        case .none:
            return .subtle
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
        completedReportGuardianCard(title: "Timing & cycles", border: .subtle) {
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
        completedReportGuardianCard(title: "Timeline", border: .subtle) {
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
        completedReportGuardianCard(title: "Roster", border: .subtle) {
            if run.assignments.isEmpty {
                Text("No roster slots.")
                    .font(GuardianTypography.font(.denseSubsection13Regular))
                    .foregroundStyle(theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    ForEach(run.assignments) { a in
                        let bound = a.attachedFleetVehicleToken != nil || !a.attachedDevice.isEmpty
                        Text("• \(a.slotName)\(bound ? "" : " — unassigned")")
                            .font(GuardianTypography.font(.telemetryMono13Regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    var completedMissionLogHealthCard: some View {
        let errs = completedMissionLogErrorCount
        let warns = completedMissionLogWarningCount
        let border: GuardianCardBorder = errs > 0 ? .danger : (warns > 0 ? .warning : .subtle)
        return completedReportGuardianCard(title: "Mission log health", border: border) {
            if run.events.isEmpty {
                Text("No mission log entries are stored for this run.")
                    .font(GuardianTypography.font(.denseSubsection13Regular))
                    .foregroundStyle(theme.textSecondary)
            } else {
                let events = run.events.count
                labeledReportRow("Events recorded", "\(events)")
                labeledReportRow("Warnings", "\(warns)")
                labeledReportRow("Errors", "\(errs)")
                if errs == 0, warns == 0 {
                    Text("No warnings or errors in the mission log.")
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.top, GuardianSpacing.xxs)
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
        return GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            header: {
                HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                    Text("Mission log")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: GuardianSpacing.xs)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                Group {
                    if text.isEmpty {
                        Text("No mission log entries for this run.")
                            .font(GuardianTypography.font(.denseSubsection13Regular))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        ScrollView {
                            Text(text)
                                .font(GuardianTypography.font(.telemetryMono11Regular))
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 220, idealHeight: 320, maxHeight: 480)
                        .padding(GuardianSpacing.denseGutter)
                        .background(theme.backgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.borderSubtle, lineWidth: 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completedReportGuardianCard<Content: View>(
        title: String,
        border: GuardianCardBorder,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: border,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            header: {
                Text(title)
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    func labeledReportRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: GuardianSpacing.sm)
            Text(value)
                .font(GuardianTypography.font(.denseCaption12Medium))
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
