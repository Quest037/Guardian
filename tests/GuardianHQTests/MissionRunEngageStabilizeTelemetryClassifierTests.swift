import XCTest

@testable import GuardianCore

final class MissionRunEngageStabilizeTelemetryClassifierTests: XCTestCase {

    private let fresh = Date()
    private let stale = Date().addingTimeInterval(-120)

    func test_park_fault_when_no_hub() {
        let op = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .park,
            hub: nil,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 12
        )
        guard case .fault(let r) = v else {
            return XCTFail("expected fault, got \(v)")
        }
        XCTAssertTrue(r.contains("No hub"))
    }

    func test_park_fault_when_hub_stale() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = stale
        hub.isArmed = false
        hub.inAir = false
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .park,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 12
        )
        guard case .fault(let r) = v else {
            return XCTFail("expected fault, got \(v)")
        }
        XCTAssertTrue(r.contains("stale"))
    }

    func test_park_fault_blocked_flight_mode() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.flightMode = "FlightMode.terminate"
        hub.isArmed = false
        hub.inAir = false
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .park,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        guard case .fault(let r) = v else {
            return XCTFail("expected fault, got \(v)")
        }
        XCTAssertTrue(r.contains("failsafe") || r.contains("termination"))
    }

    func test_park_stable_disarmed_on_ground() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.isArmed = false
        hub.inAir = false
        hub.flightMode = "FlightMode.hold"
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .park,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        XCTAssertEqual(v, .stable)
    }

    func test_park_pending_when_airborne_and_moving() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.isArmed = true
        hub.inAir = true
        hub.relativeAltM = 40
        hub.flightMode = "FlightMode.offboard"
        hub.velocityNorthMS = 3
        hub.velocityEastMS = 0
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .park,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        guard case .pending(let r) = v else {
            return XCTFail("expected pending, got \(v)")
        }
        XCTAssertTrue(r.contains("landed") || r.contains("disarmed") || r.contains("height"))
    }

    func test_loiter_pending_wrong_mode() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.flightMode = "FlightMode.offboard"
        hub.velocityDownMS = 0.1
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .loiter,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        guard case .pending(let r) = v else {
            return XCTFail("expected pending, got \(v)")
        }
        XCTAssertTrue(r.contains("mode"))
    }

    func test_loiter_stable_posctl_quiet_rates() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.flightMode = "FlightMode.posctl"
        hub.velocityDownMS = 0.1
        hub.positionVelVnMS = 0.05
        hub.positionVelVeMS = 0
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .loiter,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        XCTAssertEqual(v, .stable)
    }

    func test_loiter_pending_vertical_rate_high() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.flightMode = "FlightMode.posctl"
        hub.velocityDownMS = 2.0
        hub.positionVelVnMS = 0
        hub.positionVelVeMS = 0
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let v = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
            kind: .loiter,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        guard case .pending(let r) = v else {
            return XCTFail("expected pending, got \(v)")
        }
        XCTAssertTrue(r.contains("vertical"))
    }

    func test_liveDriveMissionStartGate_ugv_matches_park_stable() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.isArmed = false
        hub.inAir = false
        hub.flightMode = "FlightMode.hold"
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let g = MissionRunEngageStabilizeTelemetryClassifier.evaluateLiveDriveMissionStartStabilizeGate(
            vehicleClass: .ugv,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        XCTAssertEqual(g, .stable)
    }

    func test_liveDriveMissionStartGate_uav_accepts_loiter_stable_without_park_on_deck() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = fresh
        hub.flightMode = "FlightMode.posctl"
        hub.isArmed = true
        hub.inAir = true
        hub.relativeAltM = 40
        hub.velocityDownMS = 0.1
        hub.positionVelVnMS = 0.05
        hub.positionVelVeMS = 0
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: fresh)
        let g = MissionRunEngageStabilizeTelemetryClassifier.evaluateLiveDriveMissionStartStabilizeGate(
            vehicleClass: .uav,
            hub: hub,
            operational: op,
            now: fresh,
            maxHubAgeSeconds: 45
        )
        XCTAssertEqual(g, .stable)
    }
}
