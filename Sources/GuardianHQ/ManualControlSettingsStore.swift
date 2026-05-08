import Combine
import Foundation

enum ManualControlAction: String, Codable, CaseIterable, Identifiable {
    case moveForward
    case moveLeft
    case moveBackward
    case moveRight
    case yawLeft
    case yawRight
    case ascend
    case descend
    case toggleArm
    case engage
    case terminate

    var id: String { rawValue }

    /// True for held-axis inputs (forward/back/left/right/yaw/up/down) that should
    /// stream body-frame velocity through `ManualControlStream`. False for one-shot
    /// discrete actions (toggleArm/engage/terminate) that still go through
    /// `FleetLinkService.executeVehicleCommand(.manualControl(_))`.
    var isAxisInput: Bool {
        switch self {
        case .moveForward, .moveLeft, .moveBackward, .moveRight,
             .yawLeft, .yawRight, .ascend, .descend:
            return true
        case .toggleArm, .engage, .terminate:
            return false
        }
    }

    var title: String {
        switch self {
        case .moveForward: return "Move forward"
        case .moveLeft: return "Move left"
        case .moveBackward: return "Move backward"
        case .moveRight: return "Move right"
        case .yawLeft: return "Yaw left"
        case .yawRight: return "Yaw right"
        case .ascend: return "Ascend / Up"
        case .descend: return "Descend / Down"
        case .toggleArm: return "Arm / Disarm"
        case .engage: return "Engage / Takeoff equivalent"
        case .terminate: return "Terminate / RTL equivalent"
        }
    }

    var behaviorHint: String {
        switch self {
        case .engage:
            return "Return: arms if disarmed, otherwise sends engage behavior."
        case .terminate:
            return "Delete: UAV uses RTL; ground/surface/sub use hold/stop."
        case .ascend, .descend:
            return "Vertical axis applies to UAV/UUV only."
        default:
            return ""
        }
    }
}

extension UniversalVehicleClass {
    var displayName: String {
        switch self {
        case .uav: return "UAV"
        case .ugv: return "UGV"
        case .usv: return "USV"
        case .uuv: return "UUV"
        case .unknown: return "Unknown"
        }
    }
}

@MainActor
final class ManualControlSettingsStore: ObservableObject {
    private static let defaultsKey = "guardian.manualControlSettings.v1"

    @Published var keyByAction: [ManualControlAction: String] {
        didSet {
            keyByAction = Self.sanitized(keyByAction)
            save()
        }
    }
    @Published var stepProfileByVehicleClass: [UniversalVehicleClass: ManualControlStepProfile] {
        didSet {
            stepProfileByVehicleClass = Self.sanitizedProfiles(stepProfileByVehicleClass)
            save()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        if let loaded = Self.load(from: userDefaults) {
            keyByAction = Self.sanitized(loaded)
            stepProfileByVehicleClass = Self.sanitizedProfiles(Self.loadProfiles(from: userDefaults) ?? Self.defaultStepProfilesByVehicleClass)
        } else {
            keyByAction = Self.defaultKeyByAction
            stepProfileByVehicleClass = Self.defaultStepProfilesByVehicleClass
        }
    }

    func key(for action: ManualControlAction) -> String {
        keyByAction[action] ?? (Self.defaultKeyByAction[action] ?? "")
    }

    func setKey(_ key: String, for action: ManualControlAction) {
        var next = keyByAction
        next[action] = key
        keyByAction = Self.sanitized(next)
    }

    func resetDefaults() {
        keyByAction = Self.defaultKeyByAction
        stepProfileByVehicleClass = Self.defaultStepProfilesByVehicleClass
    }

    func stepProfile(for vehicleClass: UniversalVehicleClass) -> ManualControlStepProfile {
        stepProfileByVehicleClass[vehicleClass] ?? Self.defaultStepProfilesByVehicleClass[vehicleClass]!
    }

    func setMoveForwardBackward(_ value: Double, for vehicleClass: UniversalVehicleClass) {
        updateProfile(for: vehicleClass) { $0.moveForwardBackwardM = value }
    }

    func setMoveLeftRight(_ value: Double, for vehicleClass: UniversalVehicleClass) {
        updateProfile(for: vehicleClass) { $0.moveLeftRightM = value }
    }

    func setYaw(_ value: Double, for vehicleClass: UniversalVehicleClass) {
        updateProfile(for: vehicleClass) { $0.yawDeg = value }
    }

    func setVertical(_ value: Double, for vehicleClass: UniversalVehicleClass) {
        updateProfile(for: vehicleClass) { $0.verticalM = value }
    }

    static let defaultKeyByAction: [ManualControlAction: String] = [
        .moveForward: "W",
        .moveLeft: "A",
        .moveBackward: "S",
        .moveRight: "D",
        .yawLeft: "Q",
        .yawRight: "E",
        .ascend: "K",
        .descend: "L",
        .toggleArm: "Space",
        .engage: "Return",
        .terminate: "Delete",
    ]

    /// Per-class manual control profile.
    ///
    /// `move…M` / `yawDeg` / `verticalM` are the legacy discrete bump amounts (used by the
    /// `gotoLocation`-based engage / recovery path).
    ///
    /// `max…MS` / `maxYawRateDegS` are the body-frame velocity setpoints streamed at full
    /// keyboard or stick deflection through `ManualControlStream` (Offboard / ManualControl).
    /// Defaults are intentionally gentle so first-time SITL flights are predictable.
    static let defaultStepProfilesByVehicleClass: [UniversalVehicleClass: ManualControlStepProfile] = [
        .uav: .init(
            moveForwardBackwardM: 0.05, moveLeftRightM: 0.05, yawDeg: 1.0, verticalM: 0.1,
            maxForwardMS: 1.5, maxStrafeMS: 1.5, maxVerticalMS: 0.8, maxYawRateDegS: 30
        ),
        .ugv: .init(
            moveForwardBackwardM: 0.05, moveLeftRightM: 0.05, yawDeg: 1.0, verticalM: 0.0,
            maxForwardMS: 1.0, maxStrafeMS: 0, maxVerticalMS: 0, maxYawRateDegS: 25
        ),
        .usv: .init(
            moveForwardBackwardM: 0.05, moveLeftRightM: 0.05, yawDeg: 1.0, verticalM: 0.0,
            maxForwardMS: 1.0, maxStrafeMS: 0, maxVerticalMS: 0, maxYawRateDegS: 20
        ),
        .uuv: .init(
            moveForwardBackwardM: 0.05, moveLeftRightM: 0.05, yawDeg: 1.0, verticalM: 0.1,
            maxForwardMS: 0.8, maxStrafeMS: 0.5, maxVerticalMS: 0.4, maxYawRateDegS: 20
        ),
        .unknown: .init(
            moveForwardBackwardM: 0.05, moveLeftRightM: 0.05, yawDeg: 1.0, verticalM: 0.0,
            maxForwardMS: 1.0, maxStrafeMS: 0, maxVerticalMS: 0, maxYawRateDegS: 20
        ),
    ]

    private func save(userDefaults: UserDefaults = .standard) {
        let snapshot = Snapshot(
            keyByAction: keyByAction.mapKeys(\.rawValue),
            stepProfileByVehicleClass: stepProfileByVehicleClass.mapKeys(\.rawValue)
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load(from userDefaults: UserDefaults) -> [ManualControlAction: String]? {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        var out: [ManualControlAction: String] = [:]
        for (raw, key) in snap.keyByAction {
            guard let action = ManualControlAction(rawValue: raw) else { continue }
            out[action] = key
        }
        return out
    }

    private static func loadProfiles(from userDefaults: UserDefaults) -> [UniversalVehicleClass: ManualControlStepProfile]? {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        var out: [UniversalVehicleClass: ManualControlStepProfile] = [:]
        for (raw, value) in snap.stepProfileByVehicleClass ?? [:] {
            guard let vehicleClass = UniversalVehicleClass(rawValue: raw) else { continue }
            out[vehicleClass] = value
        }
        return out
    }

    private static func sanitized(_ raw: [ManualControlAction: String]) -> [ManualControlAction: String] {
        var next = defaultKeyByAction
        for action in ManualControlAction.allCases {
            if let value = raw[action], let normalized = normalizeKeyToken(value) {
                next[action] = normalized
            }
        }
        return next
    }

    private static func sanitizedProfiles(_ raw: [UniversalVehicleClass: ManualControlStepProfile]) -> [UniversalVehicleClass: ManualControlStepProfile] {
        var next = defaultStepProfilesByVehicleClass
        for vehicleClass in UniversalVehicleClass.allCases {
            if let value = raw[vehicleClass] {
                next[vehicleClass] = sanitizeProfile(value)
            }
        }
        return next
    }

    private static func sanitizeProfile(_ p: ManualControlStepProfile) -> ManualControlStepProfile {
        ManualControlStepProfile(
            moveForwardBackwardM: min(5, max(0.001, p.moveForwardBackwardM)),
            moveLeftRightM: min(5, max(0.001, p.moveLeftRightM)),
            yawDeg: min(45, max(0.1, p.yawDeg)),
            verticalM: min(5, max(0, p.verticalM)),
            maxForwardMS: min(15, max(0, p.maxForwardMS)),
            maxStrafeMS: min(15, max(0, p.maxStrafeMS)),
            maxVerticalMS: min(8, max(0, p.maxVerticalMS)),
            maxYawRateDegS: min(180, max(0, p.maxYawRateDegS))
        )
    }

    private func updateProfile(for vehicleClass: UniversalVehicleClass, mutate: (inout ManualControlStepProfile) -> Void) {
        var next = stepProfileByVehicleClass
        var profile = next[vehicleClass] ?? Self.defaultStepProfilesByVehicleClass[vehicleClass]!
        mutate(&profile)
        next[vehicleClass] = Self.sanitizeProfile(profile)
        stepProfileByVehicleClass = next
    }

    static func normalizeKeyToken(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let lower = trimmed.lowercased()
        if lower == "space" { return "Space" }
        if lower == "return" || lower == "enter" { return "Return" }
        if lower == "delete" || lower == "backspace" { return "Delete" }
        guard let first = trimmed.first, first.isASCII else { return nil }
        return String(first).uppercased()
    }

    private struct Snapshot: Codable {
        var keyByAction: [String: String]
        var stepProfileByVehicleClass: [String: ManualControlStepProfile]?
    }
}

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var out: [T: Value] = [:]
        for (k, v) in self { out[transform(k)] = v }
        return out
    }
}
