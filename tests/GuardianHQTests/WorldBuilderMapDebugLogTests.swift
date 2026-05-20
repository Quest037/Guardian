import XCTest
@testable import GuardianCore

final class WorldBuilderMapDebugLogTests: XCTestCase {
    func test_obstaclePlaceLine_includesPrefixAndDetail() {
        let line = WorldBuilderMapDebugLog.obstaclePlaceLine("tryPlace", detail: "placementActive=false")
        XCTAssertTrue(line.hasPrefix(WorldBuilderMapDebugLog.obstaclePlacePrefix))
        XCTAssertTrue(line.contains("tryPlace"))
        XCTAssertTrue(line.contains("placementActive=false"))
    }

    func test_obstaclePlaceLine_withoutDetail() {
        let line = WorldBuilderMapDebugLog.obstaclePlaceLine("pointerDown")
        XCTAssertEqual(line, "\(WorldBuilderMapDebugLog.obstaclePlacePrefix): pointerDown")
    }

    func test_zoneOverlayLine_includesPrefixAndDetail() {
        let line = WorldBuilderMapDebugLog.zoneOverlayLine("viewport commit", detail: "swiftRejected=false")
        XCTAssertTrue(line.hasPrefix(WorldBuilderMapDebugLog.zoneOverlayPrefix))
        XCTAssertTrue(line.contains("viewport commit"))
        XCTAssertTrue(line.contains("swiftRejected=false"))
    }

    func test_formationSlotLine_includesPrefixAndDetail() {
        let line = WorldBuilderMapDebugLog.formationSlotLine("swift push", detail: "linkedSquads=1")
        XCTAssertTrue(line.hasPrefix(WorldBuilderMapDebugLog.formationSlotPrefix))
        XCTAssertTrue(line.contains("swift push"))
        XCTAssertTrue(line.contains("linkedSquads=1"))
    }

    func test_formationSlotPushSummary_listsZonesAndSquads() {
        var zones = WorldBuilderZonesSnapshot.empty
        zones.start = WorldBuilderZoneState(
            placed: true,
            centerXM: -10,
            centerYM: 0,
            centerZM: 0,
            radiusM: 25,
            shape: .square
        )
        zones.end = WorldBuilderZoneState(
            placed: true,
            centerXM: 10,
            centerYM: 0,
            centerZM: 0,
            radiusM: 25,
            shape: .square
        )
        let summary = WorldBuilderMapDebugLog.formationSlotPushSummary(
            linkedSquadCount: 1,
            zones: zones,
            squadBriefs: ["Alpha vehicles=1 startSlots=1 endSlots=1"],
            editSquadID: UUID(),
            mapHalfExtentM: 50
        )
        XCTAssertTrue(summary.contains("linkedSquads=1"))
        XCTAssertTrue(summary.contains("start placed"))
        XCTAssertTrue(summary.contains("Alpha vehicles=1"))
    }

    func test_zoneSnapshotSummary_includesCenterZMRadiusAndFloor() {
        let zones = WorldBuilderZonesSnapshot(
            start: WorldBuilderZoneState(
                placed: true,
                centerXM: 0,
                centerYM: 0,
                centerZM: 12,
                radiusM: 50,
                shape: .circle
            ),
            end: WorldBuilderZoneState(
                placed: true,
                centerXM: 10,
                centerYM: -5,
                centerZM: 0,
                radiusM: 30,
                shape: .square
            )
        )
        let summary = WorldBuilderMapDebugLog.zoneSnapshotSummary(zones: zones, floorHalfM: 50)
        XCTAssertTrue(summary.contains("floorHalf=50.0m tile=100x100m"))
        XCTAssertTrue(summary.contains("start placed r=50.0m centerZM=12.000"))
        XCTAssertTrue(summary.contains("end placed r=30.0m centerZM=0.000"))
        XCTAssertTrue(summary.contains("xy=(10.0,-5.0) square"))
    }

    func test_zoneSnapshotSummary_unplacedKind() {
        let zones = WorldBuilderZonesSnapshot(start: .unplaced(), end: .unplaced())
        let summary = WorldBuilderMapDebugLog.zoneSnapshotSummary(zones: zones)
        XCTAssertTrue(summary.contains("start=unplaced"))
        XCTAssertTrue(summary.contains("end=unplaced"))
    }
}
