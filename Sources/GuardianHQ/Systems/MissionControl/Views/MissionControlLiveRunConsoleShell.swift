// MissionControlLiveRunConsoleShell.swift — MC-R live console: 70/30 split + map / roster / log flex (layout-only).
import SwiftUI

/// Geometry-driven MC-R console chrome. Keeps flex math and ``GeometryReader`` in a narrow generic surface so the parent type-checker stays lighter.
struct MissionControlLiveRunConsoleShell<MapColumn: View, RosterStrip: View, LogPanel: View, TasksCard: View>: View {
    let gutter: CGFloat
    let baseMapHeight: CGFloat
    let rosterStripHeight: CGFloat
    let verticalGap: CGFloat
    let liveLogCollapsedCardHeight: CGFloat
    @Binding var liveLogPanelCollapsed: Bool
    @ViewBuilder var mapColumn: (_ width: CGFloat, _ height: CGFloat) -> MapColumn
    @ViewBuilder var rosterStrip: () -> RosterStrip
    @ViewBuilder var logPanel: (_ maxTotalHeight: CGFloat, _ collapsed: Binding<Bool>) -> LogPanel
    @ViewBuilder var tasksCard: () -> TasksCard

    var body: some View {
        GeometryReader { geo in
            let innerW = max(0, geo.size.width)
            let innerH = max(0, geo.size.height)
            let leftW = (innerW - gutter) * 0.7
            let rightW = (innerW - gutter) * 0.3
            let defaultLogH = max(0, innerH - baseMapHeight - verticalGap - rosterStripHeight - verticalGap)
            let collapsedLogH = min(liveLogCollapsedCardHeight, defaultLogH)
            let logH = liveLogPanelCollapsed ? collapsedLogH : defaultLogH
            let mapH = liveLogPanelCollapsed ? baseMapHeight + max(0, defaultLogH - collapsedLogH) : baseMapHeight
            HStack(alignment: .top, spacing: gutter) {
                VStack(alignment: .leading, spacing: verticalGap) {
                    mapColumn(leftW, mapH)
                    rosterStrip()
                        .frame(maxWidth: .infinity)
                        .frame(height: rosterStripHeight, alignment: .topLeading)
                        .clipped()
                    logPanel(logH, $liveLogPanelCollapsed)
                        .frame(maxWidth: .infinity)
                        .frame(height: logH, alignment: .topLeading)
                }
                .frame(width: leftW, height: innerH, alignment: .topLeading)
                .clipped()
                .animation(GuardianMotion.drawerSlide, value: liveLogPanelCollapsed)

                tasksCard()
                    .frame(width: rightW)
                    .frame(height: innerH, alignment: .topLeading)
            }
            .frame(width: innerW)
            .frame(height: innerH, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
