// MCRLiveMissionLogStripStore.swift — Phase 7: MC-R live mission log strip uses a narrow tail snapshot so unrelated ``MissionRunEnvironment`` publishes do not rebuild ``ForEach`` from ``run.events`` on every tick.
import Foundation
import SwiftUI

/// Holds the **tail window** of task-filtered log lines for the MC-R live strip. Ingest is driven from
/// ``MissionControlLiveRunRoot`` on log-count / focus / roster / mission fingerprint changes — not from the shell’s
/// per-frame body evaluation.
@MainActor
final class MCRLiveMissionLogStripStore: ObservableObject {
    /// Matches the prior ``suffix(80)`` strip cap in ``MissionRunDetailView``.
    static let visibleTailCount = 80

    @Published private(set) var visibleTail: [MissionRunEvent] = []
    @Published private(set) var tailAnchorID: UUID?

    var isEmpty: Bool { visibleTail.isEmpty }

    /// Recomputes the filtered tail from the run; publishes **only** when ``visibleTail`` (Equatable) differs.
    func ingestFromRun(
        _ run: MissionRunEnvironment,
        mission: Mission?,
        focusedTaskID: UUID?
    ) {
        let filtered = MissionRunEnvironment.filterEventsForLiveTaskLogFocus(
            events: run.events,
            assignments: run.assignments,
            mission: mission,
            focusedTaskID: focusedTaskID
        )
        let tail = Array(filtered.suffix(Self.visibleTailCount))
        let newAnchor = tail.last?.id
        guard tail != visibleTail else { return }
        visibleTail = tail
        tailAnchorID = newAnchor
    }
}
