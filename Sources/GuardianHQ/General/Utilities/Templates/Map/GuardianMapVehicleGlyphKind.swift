import Foundation

/// Leaflet vehicle marker shape (inline SVG in ``OSMMapView`` — no raster thumbnails).
enum GuardianMapVehicleGlyphKind: String, Equatable, Codable, Sendable {
    /// Multicopter / fixed-wing / VTOL — arrowhead points **north** in marker space; JS rotates for hub heading.
    case uavArrow = "uav"
    /// Wheeled / tracked / legged / unknown template class — square outline.
    case ugvSquare = "ugv"
    /// Surface / underwater — plus / cross with a small north-pointing triangle at the centre (heading).
    case usvUuvCross = "usv"
    /// Hollow red-outline slot (Formations playground target positions).
    case formationSlotTarget = "formationTarget"
    /// Gold-outline preview clone (Formations playground map edit — not streamed until edit ends).
    case formationSlotClone = "formationSlotClone"

    static func forFleetVehicleType(_ type: FleetVehicleType) -> GuardianMapVehicleGlyphKind {
        switch type {
        case .uavCopter, .uavFixedWing, .uavVTOL:
            return .uavArrow
        case .ugvWheeled, .ugvTracked, .ugvLegged, .unknown:
            return .ugvSquare
        case .usv, .uuv:
            return .usvUuvCross
        }
    }

    /// Expected class from the mission roster row (``RosterDevice/vehicleClass``).
    static func forRosterAssignment(_ assignment: MissionRunAssignment, mission: Mission) -> GuardianMapVehicleGlyphKind {
        let cls = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })?.vehicleClass ?? .unknown
        return forFleetVehicleType(cls)
    }
}
