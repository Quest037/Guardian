import Foundation

/// Footprint-aware floors for squad formation spacing — live vehicles and field ops, not SITL parking tightness.
enum MissionSquadFormationFootprintSpacing {
    struct FootprintMetres: Equatable, Sendable {
        var widthM: Double
        var lengthM: Double
    }

    /// Clearance between vehicle bodies along the formation heading (not centre-to-centre only).
    static func operationalAlongGapM(universalClass: UniversalVehicleClass) -> Double {
        switch universalClass {
        case .uav: return 5
        case .ugv: return 2.5
        case .usv, .uuv: return 4
        case .unknown: return 3
        }
    }

    /// Clearance between vehicle sides in a lateral lane / row.
    static func operationalLateralGapM(universalClass: UniversalVehicleClass) -> Double {
        switch universalClass {
        case .uav: return 3
        case .ugv: return 1.5
        case .usv, .uuv: return 2.5
        case .unknown: return 2
        }
    }

    static func footprintMetres(
        vehicleClass: FleetVehicleType,
        tier: VehicleSizeTier
    ) -> FootprintMetres {
        let m = VehicleClassSizeCatalogue.footprintMetres(vehicleClass: vehicleClass, tier: tier)
        return FootprintMetres(widthM: m.widthM, lengthM: m.lengthM)
    }

    static func footprints(
        rosterEntries: [(vehicleClass: FleetVehicleType, tier: VehicleSizeTier)]
    ) -> [FootprintMetres] {
        rosterEntries.map { footprintMetres(vehicleClass: $0.vehicleClass, tier: $0.tier) }
    }

    static func rosterEntries(
        primary: RosterDevice?,
        wingmanDevices: [RosterDevice]
    ) -> [(vehicleClass: FleetVehicleType, tier: VehicleSizeTier)] {
        var entries: [(FleetVehicleType, VehicleSizeTier)] = []
        if let primary {
            entries.append((primary.vehicleClass, primary.vehicleSizeTier))
        }
        for device in wingmanDevices {
            entries.append((device.vehicleClass, device.vehicleSizeTier))
        }
        return entries
    }

    /// Minimum along-track metres per wingman ordinal (convoy / row depth multiplier).
    static func minimumAlongOrdinalM(
        footprints: [FootprintMetres],
        universalClass: UniversalVehicleClass
    ) -> Double {
        let maxLength = footprints.map(\.lengthM).max() ?? 2
        return maxLength + operationalAlongGapM(universalClass: universalClass)
    }

    /// Minimum lateral lane offset from centreline (staggered / row spacing baseline).
    static func minimumLateralLaneM(
        footprints: [FootprintMetres],
        universalClass: UniversalVehicleClass
    ) -> Double {
        let maxWidth = footprints.map(\.widthM).max() ?? 1.6
        return maxWidth + operationalLateralGapM(universalClass: universalClass)
    }

    /// Apply footprint floors after pack / kind scaling.
    static func floored(
        spacing: MissionSquadConvoySpacing,
        formation: MissionSquadFormationKind,
        primaryGranularClass: FleetVehicleType?,
        rosterEntries: [(vehicleClass: FleetVehicleType, tier: VehicleSizeTier)]
    ) -> MissionSquadConvoySpacing {
        let entries = rosterEntries.isEmpty
            ? [(primaryGranularClass ?? .unknown, VehicleClassSizeCatalogue.defaultTier(for: primaryGranularClass ?? .unknown))]
            : rosterEntries
        let prints = footprints(rosterEntries: entries)
        let universal = primaryGranularClass?.universalClass ?? .unknown
        let minAlong = minimumAlongOrdinalM(footprints: prints, universalClass: universal)
        let minLateral = minimumLateralLaneM(footprints: prints, universalClass: universal)
        let along = max(spacing.alongTrackMetersPerOrdinal, minAlong)
        var lateral = max(spacing.lateralLaneMeters, minLateral)
        switch formation {
        case .arrowhead, .chevron:
            lateral = max(lateral, minLateral * 1.05)
        case .staggeredConvoy:
            lateral = max(lateral, minLateral)
        case .convoy:
            break
        }
        return MissionSquadConvoySpacing(
            alongTrackMetersPerOrdinal: along,
            lateralLaneMeters: lateral
        )
    }
}
