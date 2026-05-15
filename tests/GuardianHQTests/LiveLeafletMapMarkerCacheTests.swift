import XCTest

@testable import GuardianHQ

@MainActor
final class LiveLeafletMapMarkerCacheTests: XCTestCase {

    func test_signature_is_order_independent() {
        let a = LiveLeafletMapMarkerImageBasenames.signature(["b.png", "a.png"])
        let b = LiveLeafletMapMarkerImageBasenames.signature(["a.png", "b.png"])
        XCTAssertEqual(a, b)
    }

    func test_second_lookup_same_identity_and_basenames_is_cache_hit() {
        let cache = LiveLeafletMapMarkerCache(maxEntries: 8)
        let identity = MapVehicleMarkerIdentity.missionRunAssignment(UUID())
        let basenames = ["multicopter", "quad_x"]
        let first = cache.imageDataURL(assignmentIdentity: identity, basenames: basenames)
        XCTAssertNotNil(first)
        XCTAssertEqual(cache.statistics.encodes, 1)
        XCTAssertEqual(cache.statistics.hits, 0)

        let second = cache.imageDataURL(assignmentIdentity: identity, basenames: ["quad_x", "multicopter"])
        XCTAssertEqual(second, first)
        XCTAssertEqual(cache.statistics.encodes, 1)
        XCTAssertEqual(cache.statistics.hits, 1)
        XCTAssertEqual(cache.statistics.misses, 1)
    }

    func test_different_assignment_identity_misses_even_with_same_basenames() {
        let cache = LiveLeafletMapMarkerCache(maxEntries: 8)
        let basenames = ["multicopter"]
        _ = cache.imageDataURL(
            assignmentIdentity: MapVehicleMarkerIdentity.missionRunAssignment(UUID()),
            basenames: basenames
        )
        _ = cache.imageDataURL(
            assignmentIdentity: MapVehicleMarkerIdentity.missionRunAssignment(UUID()),
            basenames: basenames
        )
        XCTAssertEqual(cache.statistics.encodes, 2)
        XCTAssertEqual(cache.statistics.hits, 0)
    }

    func test_basename_change_for_same_identity_re_encodes() {
        let cache = LiveLeafletMapMarkerCache(maxEntries: 8)
        let identity = "row-a"
        _ = cache.imageDataURL(assignmentIdentity: identity, basenames: ["multicopter"])
        _ = cache.imageDataURL(assignmentIdentity: identity, basenames: ["rover"])
        XCTAssertEqual(cache.statistics.encodes, 2)
        XCTAssertEqual(cache.statistics.hits, 0)
    }

    func test_lru_evicts_oldest_when_over_capacity() {
        let cache = LiveLeafletMapMarkerCache(maxEntries: 2)
        let keyA = "a"
        let keyB = "b"
        let keyC = "c"
        _ = cache.imageDataURL(assignmentIdentity: keyA, basenames: ["multicopter"])
        _ = cache.imageDataURL(assignmentIdentity: keyB, basenames: ["multicopter"])
        _ = cache.imageDataURL(assignmentIdentity: keyC, basenames: ["multicopter"])
        cache.resetStatistics()
        _ = cache.imageDataURL(assignmentIdentity: keyA, basenames: ["multicopter"])
        XCTAssertEqual(cache.statistics.hits, 0)
        XCTAssertEqual(cache.statistics.encodes, 1)
        _ = cache.imageDataURL(assignmentIdentity: keyB, basenames: ["multicopter"])
        XCTAssertEqual(cache.statistics.hits, 1)
    }

    func test_pool_identity_does_not_collide_with_roster_assignment_id() {
        let slotID = UUID()
        let taskID = UUID()
        let cache = LiveLeafletMapMarkerCache(maxEntries: 8)
        let basenames = ["multicopter"]
        _ = cache.imageDataURL(
            assignmentIdentity: MapVehicleMarkerIdentity.missionRunAssignment(slotID),
            basenames: basenames
        )
        _ = cache.imageDataURL(
            assignmentIdentity: MapVehicleMarkerIdentity.floatingReservePool(taskID: taskID, slotID: slotID),
            basenames: basenames
        )
        XCTAssertEqual(cache.statistics.encodes, 2)
    }
}
