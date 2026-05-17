import Foundation

/// App-wide squad formation geometry (pad offsets, path astern depth, chevron / arrowhead rows).
/// Consumed by MRE wingman follow, formation playground, and MCS preview targets.
enum MissionSquadFormationGeometry {
    static let metresPerDegreeLatitude: Double = 111_320

    /// Chevron pad / path shape — shallow wide V (not a deep narrow wedge).
    private enum ChevronShapeTuning {
        /// Multiplier on row-index astern depth (1.0 = full ``alongTrackMetersPerOrdinal`` per row).
        static let alongTrackDepthScale: Double = 0.58
        /// Lateral lane spacing vs along spacing (~2× v1 `0.72` for wing span).
        static let lateralLaneAlongScale: Double = 1.44
        static let minLateralLaneMeters: Double = 1.5
    }

    struct BodyOffsetMeters: Equatable, Sendable {
        /// Metres along primary heading; negative = astern.
        let forwardM: Double
        /// Metres to starboard (body-right positive).
        let rightM: Double
    }

    // MARK: - Pad / heading-locked slots

    /// Body-frame wingman slot relative to primary pose (no task polyline).
    static func desiredPadSlotCoordinate(
        formation: MissionSquadFormationKind,
        primaryLatitudeDeg: Double,
        primaryLongitudeDeg: Double,
        primaryHeadingDeg: Double,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> RouteCoordinate {
        let offset = bodyOffsetMeters(
            formation: formation,
            wingmanOrdinal: wingmanOrdinal,
            spacing: spacing
        )
        return offsetCoordinate(
            latitudeDeg: primaryLatitudeDeg,
            longitudeDeg: primaryLongitudeDeg,
            headingDeg: primaryHeadingDeg,
            forwardMeters: offset.forwardM,
            rightMeters: offset.rightM
        )
    }

    static func bodyOffsetMeters(
        formation: MissionSquadFormationKind,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> BodyOffsetMeters {
        BodyOffsetMeters(
            forwardM: alongTrackBodyMeters(formation: formation, wingmanOrdinal: wingmanOrdinal, spacing: spacing),
            rightM: lateralBodyMeters(formation: formation, wingmanOrdinal: wingmanOrdinal, spacing: spacing)
        )
    }

    /// Along-track body offset (negative = behind primary).
    static func alongTrackBodyMeters(
        formation: MissionSquadFormationKind,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> Double {
        switch formation {
        case .convoy, .staggeredConvoy:
            let depth = Double(wingmanOrdinal + 1) * spacing.alongTrackMetersPerOrdinal
            return -depth
        case .chevron:
            let row = chevronRowPlacement(wingmanOrdinal: wingmanOrdinal).row
            return -Double(row) * spacing.alongTrackMetersPerOrdinal * ChevronShapeTuning.alongTrackDepthScale
        case .arrowhead:
            let row = arrowheadRowPlacement(wingmanOrdinal: wingmanOrdinal).row
            return -Double(row) * spacing.alongTrackMetersPerOrdinal
        }
    }

    /// Astern distance along a path polyline (positive metres behind primary projection).
    static func pathBehindMeters(
        formation: MissionSquadFormationKind,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> Double {
        abs(alongTrackBodyMeters(formation: formation, wingmanOrdinal: wingmanOrdinal, spacing: spacing))
    }

    /// Lateral body offset (starboard positive).
    static func lateralBodyMeters(
        formation: MissionSquadFormationKind,
        wingmanOrdinal: Int,
        spacing: MissionSquadConvoySpacing
    ) -> Double {
        switch formation {
        case .convoy:
            return 0
        case .staggeredConvoy:
            let sign: Double = wingmanOrdinal % 2 == 0 ? 1.0 : -1.0
            return sign * max(spacing.lateralLaneMeters, spacing.alongTrackMetersPerOrdinal * 0.35)
        case .chevron:
            let placement = chevronRowPlacement(wingmanOrdinal: wingmanOrdinal)
            return formationRowLateralMeters(
                formation: formation,
                row: placement.row,
                indexInRow: placement.indexInRow,
                countInRow: placement.countInRow,
                spacing: spacing
            )
        case .arrowhead:
            let placement = arrowheadRowPlacement(wingmanOrdinal: wingmanOrdinal)
            return formationRowLateralMeters(
                formation: formation,
                row: placement.row,
                indexInRow: placement.indexInRow,
                countInRow: placement.countInRow,
                spacing: spacing
            )
        }
    }

    // MARK: - Row placement (chevron / arrowhead)

    static func chevronRowPlacement(wingmanOrdinal: Int) -> (row: Int, indexInRow: Int, countInRow: Int) {
        let row = wingmanOrdinal / 2 + 1
        return (row, wingmanOrdinal % 2, 2)
    }

    /// Primary occupies the arrow tip; row 1 astern is **two** wingmen, then 3, 4, … per row.
    static func arrowheadRowPlacement(wingmanOrdinal: Int) -> (row: Int, indexInRow: Int, countInRow: Int) {
        var remaining = wingmanOrdinal
        var row = 1
        while remaining >= row + 1 {
            remaining -= row + 1
            row += 1
        }
        let countInRow = row + 1
        return (row, remaining, countInRow)
    }

    // MARK: - Geo helpers

    static func offsetCoordinate(
        latitudeDeg: Double,
        longitudeDeg: Double,
        headingDeg: Double,
        forwardMeters: Double,
        rightMeters: Double
    ) -> RouteCoordinate {
        let h = headingDeg * .pi / 180
        let sinH = sin(h)
        let cosH = cos(h)
        let eastM = forwardMeters * sinH + rightMeters * cosH
        let northM = forwardMeters * cosH - rightMeters * sinH
        let latRad = latitudeDeg * .pi / 180
        let metresPerDegreeLon = metresPerDegreeLatitude * max(0.01, cos(latRad))
        let lat = latitudeDeg + northM / metresPerDegreeLatitude
        let lon = longitudeDeg + eastM / metresPerDegreeLon
        return RouteCoordinate(lat: lat, lon: lon)
    }

    private static func formationRowLaneSpacingMeters(
        formation: MissionSquadFormationKind,
        row: Int,
        spacing: MissionSquadConvoySpacing
    ) -> Double {
        let along = spacing.alongTrackMetersPerOrdinal
        let rowScale = Double(row)
        switch formation {
        case .arrowhead:
            return max(along * 0.42 * rowScale, 1.0)
        case .chevron:
            return max(
                along * ChevronShapeTuning.lateralLaneAlongScale * rowScale,
                ChevronShapeTuning.minLateralLaneMeters
            )
        case .convoy, .staggeredConvoy:
            return max(along * 0.9 * rowScale, 2.0)
        }
    }

    private static func formationRowLateralMeters(
        formation: MissionSquadFormationKind,
        row: Int,
        indexInRow: Int,
        countInRow: Int,
        spacing: MissionSquadConvoySpacing
    ) -> Double {
        let laneSpacing = formationRowLaneSpacingMeters(formation: formation, row: row, spacing: spacing)
        let n = Double(countInRow)
        let index = Double(indexInRow)
        return (index - (n - 1) / 2.0) * laneSpacing
    }
}
