// MissionControlLiveLazyHorizontalRosterStrip.swift — MC-R large-fleet roster strip: horizontal lazy card lane.
import SwiftUI

/// Horizontal scroll lane of identically sized cards; only visible cards are built (``LazyHStack``).
struct MissionControlLiveLazyHorizontalRosterStrip<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let horizontalSpacing: CGFloat
    let cardHeight: CGFloat
    let cardWidth: CGFloat
    @ViewBuilder var card: (Item) -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(alignment: .top, spacing: horizontalSpacing) {
                ForEach(items) { item in
                    card(item)
                        .frame(width: cardWidth, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight)
    }
}
