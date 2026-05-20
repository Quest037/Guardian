import XCTest
@testable import GuardianCore

final class MissionGeofenceFenceMavlinkAltitudeTests: XCTestCase {

    func test_mavlink_frame_maps_relative_home_to_relative_alt_int() {
        XCTAssertEqual(
            MissionGeofenceFenceMavlinkAltitude.mavlinkFrameUInt32(for: .relativeHome),
            MissionGeofenceFenceMavlinkAltitude.mavFrameGlobalRelativeAltInt
        )
    }

    func test_mavlink_frame_maps_msl_to_global_int() {
        XCTAssertEqual(
            MissionGeofenceFenceMavlinkAltitude.mavlinkFrameUInt32(for: .msl),
            MissionGeofenceFenceMavlinkAltitude.mavFrameGlobalInt
        )
    }

    func test_mavlink_frame_maps_agl_to_terrain_alt_int() {
        XCTAssertEqual(
            MissionGeofenceFenceMavlinkAltitude.mavlinkFrameUInt32(for: .agl),
            MissionGeofenceFenceMavlinkAltitude.mavFrameGlobalTerrainAltInt
        )
    }

    func test_recommended_vertex_z_uses_upper_envelope_bound() {
        var fence = MissionGeofence.newCircle(name: "c", center: RouteCoordinate(lat: 0, lon: 0))
        fence.minAltitudeMeters = 30
        fence.maxAltitudeMeters = 120
        XCTAssertEqual(MissionGeofenceFenceMavlinkAltitude.recommendedVertexAltitudeZMeters(for: fence), 120)
    }
}
