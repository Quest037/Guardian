// MissionRunPrepSharedControls.swift — MC-S / MC-R prep layout constants, map task hues, reserve pool mutation gates.
import SwiftUI

/// Spacing and widths for mission setup / roster prep.
///
/// Values alias ``GuardianSpacing`` / ``GuardianCardLayout`` so MC-S tracks the global grid; tune **here** when
/// adding sim battery, pre-place coordinates, staging waypoints, or other per-slot controls.
enum MissionRunPrepLayout {
    static let setupScrollPaddingH: CGFloat = GuardianSpacing.denseGutter
    static let setupScrollPaddingV: CGFloat = GuardianSpacing.denseGutter
    static let setupBlockSpacing: CGFloat = GuardianSpacing.denseGutter
    static let taskCardPadding: CGFloat = GuardianSpacing.missionTaskCardOuterInset
    static let taskCardInnerSpacing: CGFloat = GuardianSpacing.sectionStack
    static let tasksOuterSpacing: CGFloat = GuardianSpacing.missionTaskCardOuterInset
    /// Former default ~200pt; +50% for wider prep columns.
    static let rosterGridMinWidth: CGFloat = GuardianSpacing.missionRosterGridMinWidth
    static let rosterGridSpacing: CGFloat = GuardianSpacing.missionRosterGridGap
    static let scheduleCardPadding: CGFloat = GuardianSpacing.missionScheduleCardInset
    static let scheduleCardSpacing: CGFloat = GuardianSpacing.missionScheduleBlockGap
    static let rosterSlotPadding: CGFloat = GuardianSpacing.denseGutter
    static let rosterSlotStackSpacing: CGFloat = GuardianSpacing.denseGutter
    static let rosterSlotIconSize: CGFloat = 44
    static let rosterSlotIconRowSpacing: CGFloat = GuardianSpacing.cardBodyInset
    static let rosterTitleStackSpacing: CGFloat = GuardianSpacing.titleStackTight
    /// Wingman / reserve visual indent under a primary (matches Missions roster nesting).
    static let rosterSlotWingmanIndent: CGFloat = GuardianSpacing.cardBodyInset
    /// Slot cards use ``GuardianCard``; same radius as ``GuardianCardLayout/cornerRadius`` (theme catalog / docs).
    static let rosterSlotCornerRadius: CGFloat = GuardianCardLayout.cornerRadius
    static let rosterSlotMinHeight: CGFloat = 100
    /// Below this width, Setup **Tasks** tab stacks map above the accordion.
    static let rostersMapAccordionStackBreakpoint: CGFloat = GuardianSpacing.missionRosterMapAccordionBreakpoint
    /// Floating reserve pool slot cards in the roster accordion (horizontal strip); slightly narrower than full roster grid cells.
    static let reservePoolSlotCardWidth: CGFloat = 230

    /// MC-R live console roster strip: column-major row count for ``itemCount`` cards with at most ``slotsPerColumn`` rows per column (matches ``missionLiveVehicleStatusRow`` / ``missionLiveVehicleStatusRowRosterGrid`` indexing; used by ``MissionControlLiveRosterColumnMajorPackedStrip``).
    static func liveConsoleColumnMajorGridRowCount(itemCount: Int, slotsPerColumn: Int) -> Int {
        let n = max(0, itemCount)
        if n == 0 { return 1 }
        let cap = max(1, slotsPerColumn)
        let maxRowIndex = (0 ..< n).map { $0 % cap }.max() ?? 0
        return min(cap, maxRowIndex + 1)
    }

    /// MC-R: beyond this **exclusive** count, roster / floating-pool strips use a horizontal ``ScrollView`` + ``LazyHStack`` so large fleets do not materialize every cell at once.
    static let liveRosterStripLazyHorizontalItemThreshold: Int = 12

    /// Fixed card width in the lazy horizontal strip and in ``MissionControlLiveRosterColumnMajorPackedStrip`` (health cards no longer expand across equal-width ``Grid`` columns).
    static let liveRosterStripLazyHorizontalCardWidth: CGFloat = 230

    static func liveRosterStripUsesLazyHorizontalLayout(itemCount: Int) -> Bool {
        itemCount > liveRosterStripLazyHorizontalItemThreshold
    }

    /// Vertical row count for MC-R roster strip chrome: lazy horizontal uses **one** row; otherwise column-major depth capped by ``slotsPerColumn``.
    static func liveRosterStripEffectiveContentRows(itemCount: Int, slotsPerColumn: Int) -> Int {
        let n = max(0, itemCount)
        if n == 0 { return 1 }
        if liveRosterStripUsesLazyHorizontalLayout(itemCount: n) { return 1 }
        return liveConsoleColumnMajorGridRowCount(itemCount: n, slotsPerColumn: slotsPerColumn)
    }
}

/// MC-R roster / reserve strips (≤ lazy-horizontal threshold): column-major order with **fixed** ``cardWidth`` columns
/// packed from the **leading** edge. SwiftUI ``Grid`` / ``GridRow`` distributes columns to equal width of the container,
/// which leaves large gaps when only a few columns are present; this layout matches the lazy horizontal strip width
/// and bunches cards left.
struct MissionControlLiveRosterColumnMajorPackedStrip<ItemContent: View>: View {
    let itemCount: Int
    let slotsPerColumn: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    @ViewBuilder let content: (Int) -> ItemContent

    private var columnCount: Int {
        max(1, (itemCount + max(1, slotsPerColumn) - 1) / max(1, slotsPerColumn))
    }

    private var effectiveRows: Int {
        MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(
            itemCount: itemCount,
            slotsPerColumn: slotsPerColumn
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: horizontalSpacing) {
            ForEach(0 ..< columnCount, id: \.self) { col in
                VStack(alignment: .leading, spacing: verticalSpacing) {
                    ForEach(0 ..< effectiveRows, id: \.self) { row in
                        let index = col * max(1, slotsPerColumn) + row
                        Group {
                            if index < itemCount {
                                content(index)
                            } else {
                                Color.clear
                                    .frame(width: cardWidth, height: cardHeight)
                            }
                        }
                        .frame(width: cardWidth, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Matches the golden-angle route line hue in ``OSMMapView`` so route lines and progress bars align visually.
enum MissionTaskMapColor {
    static func hueDegrees(forTaskIndex index: Int) -> Double {
        (Double(index) * 137.508).truncatingRemainder(dividingBy: 360)
    }

    /// CSS HSL (`hue`, 88%, 62%) — same formula as Leaflet `pathColor` in ``OSMMapView`` (not SwiftUI HSB).
    static func swiftUIColor(forTaskIndex index: Int) -> Color {
        let h = hueDegrees(forTaskIndex: index)
        let (r, g, b) = hslCssToSRGBUnit(hueDegrees: h, saturation: 0.88, lightness: 0.62)
        return Color(red: r, green: g, blue: b)
    }

    /// Converts CSS `hsl(h, s%, l%)` with `h` in degrees to linear sRGB components in 0...1.
    internal static func hslCssToSRGBUnit(hueDegrees: Double, saturation s: Double, lightness l: Double) -> (
        Double,
        Double,
        Double
    ) {
        let h = ((hueDegrees / 360).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let hs = h * 6
        let (rp, gp, bp): (Double, Double, Double)
        if hs < 1 { (rp, gp, bp) = (c, x, 0) }
        else if hs < 2 { (rp, gp, bp) = (x, c, 0) }
        else if hs < 3 { (rp, gp, bp) = (0, c, x) }
        else if hs < 4 { (rp, gp, bp) = (0, x, c) }
        else if hs < 5 { (rp, gp, bp) = (x, 0, c) }
        else { (rp, gp, bp) = (c, 0, x) }
        return (rp + m, gp + m, bp + m)
    }
}

/// Timing for MCS **Set reserve pool home** staging map behaviour (`MCSReservePoolMapToDo.md`).
enum MCSReservePoolHomeStagingMapTiming {
    /// Hub / digest often lag the first ``applySimState`` pass; a second fit widens bbox once markers move.
    static let postBatchFitDelaySeconds: Double = 0.35
}

// MARK: - MC-R reserve pool mutation gates

/// Pure predicates for **which** floating reserve pool berths must reject competing operator mutations
/// (reserve swap-in preflight→commit vs berth arm preflight vs vehicle binding edits).
enum MissionControlReservePoolMutationGate: Sendable {

    /// Held for the whole ``MissionRunDetailView/runMcrFloatingReservePoolSwapAfterReservePreflight`` pipeline
    /// (after eligibility checks, through hub probe, roster/pool commit, and plan recompile).
    struct SwapOperationLock: Equatable, Sendable {
        let vacancyAssignmentID: UUID
        let taskID: UUID
        /// Set for floating-pool swap-in; `nil` while a **fixed template reserve** roster swap pipeline runs (no berth is locked).
        let poolSlotID: UUID?
    }

    /// `true` when a reserve swap-in pipeline is active (second confirms / new swap picks / berth edits must wait).
    static func swapOperationInFlight(lock: SwapOperationLock?) -> Bool {
        lock != nil
    }

    /// `true` when this **task + pool berth** must not accept vehicle binding changes, berth removal, or overlapping probes.
    static func reservePoolSlotMutationLocked(
        swapLock: SwapOperationLock?,
        berthPreflightTaskID: UUID?,
        berthPreflightSlotID: UUID?,
        taskID: UUID,
        slotID: UUID
    ) -> Bool {
        if let swapLock, swapLock.taskID == taskID,
           let lockedPool = swapLock.poolSlotID, lockedPool == slotID { return true }
        if let t = berthPreflightTaskID, let s = berthPreflightSlotID, t == taskID, s == slotID { return true }
        return false
    }
}
