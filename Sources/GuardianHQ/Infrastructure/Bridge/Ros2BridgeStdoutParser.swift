import Foundation

/// Decodes newline JSON from `guardian_ros2_vehicle_bridge` stdout.
enum Ros2BridgeStdoutParser {
    struct Nav2PlanPathPayload: Equatable, Sendable {
        var requestID: UUID
        var vehicleID: String
        var ok: Bool
        var source: String
        var points: [RouteCoordinate]
        var message: String?
    }

    struct Event: Equatable, Sendable {
        var type: String
        var vehicleID: String?
        var state: Ros2VehicleConnectionState?
        var plannerKind: String?
        var message: String?
        var trainingStackStatus: String?
        var nav2PlanPath: Nav2PlanPathPayload?
    }

    static func parse(line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        let vehicleID = json["vehicle_id"] as? String
        var state: Ros2VehicleConnectionState?
        if let raw = json["state"] as? String {
            state = Ros2VehicleConnectionState(rawValue: raw)
        }
        let message = json["message"] as? String
        let plannerKind = json["planner"] as? String
        var trainingStackStatus: String?
        if type == "ros2_nav2_training_stack" {
            trainingStackStatus = json["status"] as? String
        }
        var nav2PlanPath: Nav2PlanPathPayload?
        if type == "ros2_nav2_plan_path",
           let requestIDStr = json["request_id"] as? String,
           let requestID = UUID(uuidString: requestIDStr),
           let vid = vehicleID ?? json["vehicle_id"] as? String {
            let points = parsePlanPoints(json["points"])
            nav2PlanPath = Nav2PlanPathPayload(
                requestID: requestID,
                vehicleID: vid,
                ok: json["ok"] as? Bool ?? false,
                source: json["source"] as? String ?? "error",
                points: points,
                message: json["message"] as? String
            )
        }
        return Event(
            type: type,
            vehicleID: vehicleID,
            state: state,
            plannerKind: plannerKind,
            message: message,
            trainingStackStatus: trainingStackStatus,
            nav2PlanPath: nav2PlanPath
        )
    }

    private static func parsePlanPoints(_ raw: Any?) -> [RouteCoordinate] {
        guard let list = raw as? [[String: Any]] else { return [] }
        var out: [RouteCoordinate] = []
        out.reserveCapacity(list.count)
        for item in list {
            guard let lat = item["lat"] as? Double, let lon = item["lon"] as? Double else { continue }
            out.append(RouteCoordinate(lat: lat, lon: lon))
        }
        return out
    }
}
