import Foundation

/// Cache key: stable map row identity + bundled art fingerprint (not lat/lon).
struct LiveLeafletMapMarkerImageCacheKey: Hashable, Sendable {
    var assignmentIdentity: String
    var imageBasenamesSignature: String
}

/// In-memory cache of `data:image/png;base64,…` strings for live map roster / pool markers.
///
/// Keyed by ``LiveLeafletMapMarkerImageCacheKey`` so **position-only** hub updates reuse encoded art
/// without repeating `NSImage` → TIFF → PNG → base64 on every telemetry tick.
@MainActor
final class LiveLeafletMapMarkerCache {
    struct Statistics: Equatable, Sendable {
        var hits: Int = 0
        var misses: Int = 0
        var encodes: Int = 0
    }

    private var store: [LiveLeafletMapMarkerImageCacheKey: String] = [:]
    private var insertionOrder: [LiveLeafletMapMarkerImageCacheKey] = []
    private let maxEntries: Int
    private(set) var statistics = Statistics()

    init(maxEntries: Int = 96) {
        self.maxEntries = max(1, maxEntries)
    }

    func resetStatistics() {
        statistics = Statistics()
    }

    /// Looks up or encodes marker art. ``assignmentIdentity`` should follow ``MapVehicleMarkerIdentity``.
    func imageDataURL(assignmentIdentity: String, basenames: [String]) -> String? {
        let trimmed = basenames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return nil }
        let key = LiveLeafletMapMarkerImageCacheKey(
            assignmentIdentity: assignmentIdentity,
            imageBasenamesSignature: LiveLeafletMapMarkerImageBasenames.signature(trimmed)
        )
        if let cached = store[key] {
            statistics.hits += 1
            return cached
        }
        statistics.misses += 1
        guard let url = LiveLeafletMapMarkerImageBasenames.encodePNGDataURL(basenames: trimmed) else {
            return nil
        }
        statistics.encodes += 1
        insert(key: key, value: url)
        return url
    }

    /// Resolves basenames from assignment + services, then uses ``MapVehicleMarkerIdentity/missionRunAssignment`` as cache identity.
    func imageDataURL(
        assignment: MissionRunAssignment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> String? {
        let basenames = LiveLeafletMapMarkerImageBasenames.resolve(
            assignment: assignment,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl
        )
        return imageDataURL(
            assignmentIdentity: MapVehicleMarkerIdentity.missionRunAssignment(assignment.id),
            basenames: basenames
        )
    }

    /// Pool markers: use ``MapVehicleMarkerIdentity/floatingReservePool`` so berth rows do not collide with roster ids.
    func imageDataURL(
        syntheticAssignment: MissionRunAssignment,
        poolTaskID: UUID,
        poolSlotID: UUID,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> String? {
        let basenames = LiveLeafletMapMarkerImageBasenames.resolve(
            assignment: syntheticAssignment,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl
        )
        return imageDataURL(
            assignmentIdentity: MapVehicleMarkerIdentity.floatingReservePool(taskID: poolTaskID, slotID: poolSlotID),
            basenames: basenames
        )
    }

    private func insert(key: LiveLeafletMapMarkerImageCacheKey, value: String) {
        if store[key] != nil {
            insertionOrder.removeAll { $0 == key }
        }
        store[key] = value
        insertionOrder.append(key)
        while insertionOrder.count > maxEntries, let evict = insertionOrder.first {
            insertionOrder.removeFirst()
            store.removeValue(forKey: evict)
        }
    }
}
