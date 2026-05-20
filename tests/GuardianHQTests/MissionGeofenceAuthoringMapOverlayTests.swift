import XCTest
@testable import GuardianCore

final class MissionGeofenceAuthoringMapOverlayTests: XCTestCase {

    func test_asGuardianMapOverlay_mapSelectionFenceID_setsSelectedFlag() {
        let fence = MissionGeofence.newCircle(name: "A", center: RouteCoordinate(lat: 1, lon: 2))
        let unselected = fence.asGuardianMapOverlay(mapSelectionFenceID: UUID())
        XCTAssertEqual(unselected?.isAuthoringMapSelected, false)
        let selected = fence.asGuardianMapOverlay(mapSelectionFenceID: fence.id)
        XCTAssertEqual(selected?.isAuthoringMapSelected, true)
    }

    func test_allGuardianGeofenceMapOverlays_highlightsMatchingFenceOnly() {
        let mFence = MissionGeofence.newPolygon(name: "M", around: RouteCoordinate(lat: 0, lon: 0))
        var task = MissionTask(name: "T")
        task.geofences = [MissionGeofence.newCircle(name: "C", center: RouteCoordinate(lat: 5, lon: 5))]
        let mission = Mission(
            name: "X",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [mFence]
        )
        let overlays = mission.allGuardianGeofenceMapOverlays(mapSelectionFenceID: mFence.id)
        XCTAssertEqual(overlays.count, 2)
        let mOverlay = overlays.first { $0.id == mFence.id }
        let tOverlay = overlays.first { $0.id == task.geofences[0].id }
        XCTAssertEqual(mOverlay?.isAuthoringMapSelected, true)
        XCTAssertEqual(tOverlay?.isAuthoringMapSelected, false)
    }
}
