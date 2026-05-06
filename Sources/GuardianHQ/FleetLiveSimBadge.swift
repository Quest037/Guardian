import SwiftUI

/// **Live** (green) vs **Sim** (orange) — same treatment in fleet grid, assign sidebar, and mission roster cards.
struct FleetLiveSimBadge: View {
    let isSimulation: Bool

    var body: some View {
        Text(isSimulation ? "Sim" : "Live")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSimulation ? Color.orange : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
