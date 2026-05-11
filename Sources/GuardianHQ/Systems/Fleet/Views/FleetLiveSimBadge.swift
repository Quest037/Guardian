import SwiftUI

enum FleetBadgeStyle {
    static let font = GuardianTypography.relativeFixed(size: 9, weight: .heavy, relativeTo: .caption2)
    static let horizontalPadding: CGFloat = 9
    static let verticalPadding: CGFloat = 5
    static let cornerRadius: CGFloat = 5
}

/// **Live** (green) vs **Sim** (orange) — same treatment in fleet grid, assign sidebar, and mission roster cards.
struct FleetLiveSimBadge: View {
    let isSimulation: Bool

    var body: some View {
        Text(isSimulation ? "Sim" : "Live")
            .font(FleetBadgeStyle.font)
            .foregroundStyle(.white)
            .padding(.horizontal, FleetBadgeStyle.horizontalPadding)
            .padding(.vertical, FleetBadgeStyle.verticalPadding)
            .background(isSimulation ? Color.orange : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: FleetBadgeStyle.cornerRadius))
    }
}

struct FleetAutopilotStackBadge: View {
    let stack: FleetAutopilotStack

    var body: some View {
        Text(stack.displayName)
            .font(FleetBadgeStyle.font)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, FleetBadgeStyle.horizontalPadding)
            .padding(.vertical, FleetBadgeStyle.verticalPadding)
            .background(stack.badgeBackground)
            .clipShape(RoundedRectangle(cornerRadius: FleetBadgeStyle.cornerRadius))
    }
}
