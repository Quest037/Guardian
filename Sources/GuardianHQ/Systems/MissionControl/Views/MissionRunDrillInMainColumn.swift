// MissionRunDrillInMainColumn.swift — Mission Control run drill-in: main column switches setup vs completed vs live (preflight stays a sibling overlay on the parent).
import SwiftUI

/// Branches the **primary** run body by ``MissionRunStatus`` so **setup**, **completed**, and **MC‑R live** chrome are sibling `@ViewBuilder` regions.
///
/// **Live console carve-out:** keeps MCS + report + preflight paths on ``MissionRunDetailView`` while the **live** subtree is ``MissionControlLiveRunRoot`` + `live` builder — enables a cheap `#Preview` of the live branch without compiling rosters / staging maps (``README_FULL.md`` → **MC-R observation restructure — archived reference (v1 complete)**).
struct MissionRunDrillInMainColumn<Setup: View, Completed: View, Live: View>: View {
    let status: MissionRunStatus
    @ViewBuilder var setup: () -> Setup
    @ViewBuilder var completed: () -> Completed
    @ViewBuilder var live: () -> Live

    var body: some View {
        Group {
            if status == .setup {
                setup()
            } else if status == .completed {
                completed()
            } else {
                live()
            }
        }
        .layoutPriority(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
#Preview("Drill-in main column — live branch only") {
    MissionRunDrillInMainColumn(
        status: .running,
        setup: { Text("Setup placeholder").padding() },
        completed: { Text("Completed placeholder").padding() },
        live: {
            Text("Live console subtree (MissionControlLiveRunRoot + missionLiveConsole)")
                .font(.caption)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.12))
        }
    )
    .frame(width: 900, height: 520)
}
#endif
