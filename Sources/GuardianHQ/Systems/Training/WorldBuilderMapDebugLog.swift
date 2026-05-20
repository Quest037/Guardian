import Foundation

/// Ring buffer of timestamped lines for World Builder map / gzweb diagnostics (Debug overlay).
@MainActor
enum WorldBuilderMapDebugLog {
    static let maxLines = 400

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func stamp() -> String {
        stampFormatter.string(from: Date())
    }

    static func formattedLine(_ message: String, at date: Date = Date()) -> String {
        "[\(stampFormatter.string(from: date))] \(message)"
    }

    /// Prefix for World Builder obstacle add-click tracing (gzweb → Swift).
    static let obstaclePlacePrefix = "obstacle place"

    static func obstaclePlaceLine(_ step: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "\(obstaclePlacePrefix): \(step) — \(detail)"
        }
        return "\(obstaclePlacePrefix): \(step)"
    }

    /// Prefix for start/end zone overlay height / fit tracing (gzweb ↔ Swift).
    static let zoneOverlayPrefix = "zone overlay"

    /// Prefix for Training lab squad formation slot overlays (Swift push ↔ gzweb).
    static let formationSlotPrefix = "formation slots"

    static func formationSlotLine(_ step: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "\(formationSlotPrefix): \(step) — \(detail)"
        }
        return "\(formationSlotPrefix): \(step)"
    }

    /// Summary for a formation-slot viewport push (linked squads, zone placement, mesh counts).
    static func formationSlotPushSummary(
        linkedSquadCount: Int,
        zones: WorldBuilderZonesSnapshot,
        squadBriefs: [String],
        editSquadID: UUID?,
        mapHalfExtentM: Double
    ) -> String {
        var parts: [String] = [
            String(format: "linkedSquads=%d halfExtent=%.1fm", linkedSquadCount, mapHalfExtentM),
            zoneSnapshotSummary(zones: zones),
        ]
        if let editSquadID {
            parts.append("editSquad=\(editSquadID.uuidString.prefix(8))…")
        } else {
            parts.append("editSquad=nil")
        }
        if !squadBriefs.isEmpty {
            parts.append(squadBriefs.joined(separator: ", "))
        }
        return parts.joined(separator: "; ")
    }

    static func zoneOverlayLine(_ step: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "\(zoneOverlayPrefix): \(step) — \(detail)"
        }
        return "\(zoneOverlayPrefix): \(step)"
    }

    /// Compact start/end snapshot for diagnosing centreZM drift vs map tile size.
    static func zoneSnapshotSummary(
        zones: WorldBuilderZonesSnapshot,
        floorHalfM: Double? = nil
    ) -> String {
        var parts: [String] = []
        if let floorHalfM {
            let side = floorHalfM * 2
            parts.append(
                String(format: "floorHalf=%.1fm tile=%.0fx%.0fm", floorHalfM, side, side)
            )
        }
        parts.append(zoneBrief(label: "start", zone: zones.start))
        parts.append(zoneBrief(label: "end", zone: zones.end))
        return parts.joined(separator: "; ")
    }

    private static func zoneBrief(label: String, zone: WorldBuilderZoneState) -> String {
        guard zone.placed else {
            return "\(label)=unplaced"
        }
        return String(
            format: "%@ placed r=%.1fm centerZM=%.3f xy=(%.1f,%.1f) %@",
            label,
            zone.radiusM,
            zone.centerZM,
            zone.centerXM,
            zone.centerYM,
            zone.shape.rawValue
        )
    }
}
