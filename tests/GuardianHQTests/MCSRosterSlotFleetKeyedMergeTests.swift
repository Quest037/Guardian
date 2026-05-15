import XCTest

@testable import GuardianHQ

@MainActor
final class MCSRosterSlotFleetKeyedMergeTests: XCTestCase {
    func test_fields_nil_slice_returns_fallbacks() {
        let bat = FleetVehicleOperationalModel.BatterySummary(
            percent0to100: 42,
            voltageV: nil,
            currentA: nil,
            etaSeconds: nil
        )
        let fb = MCSRosterSlotFleetKeyedMerge.Fields(
            rosterBatterySummary: bat,
            lifecycleStatus: nil,
            vehicleClassForBundledDeviceArt: .uavCopter,
            fleetDisplayShortID: "UAV-C:1"
        )
        let out = MCSRosterSlotFleetKeyedMerge.fields(
            slice: nil,
            fallbackBattery: fb.rosterBatterySummary,
            fallbackLifecycle: fb.lifecycleStatus,
            fallbackDeviceArtVehicleClass: fb.vehicleClassForBundledDeviceArt,
            fallbackFleetDisplayShortID: fb.fleetDisplayShortID
        )
        XCTAssertEqual(out, fb)
    }

    func test_fields_slice_bracketed_short_overrides_fallback() {
        let op = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil)
        let slice = MCRFleetRosterTileLiveFleetSlice(
            bracketedVehicleShortID: "[UAV-V:9]",
            vehicleClassForBundledDeviceArt: .uavFixedWing,
            vehicleModel: op
        )
        let out = MCSRosterSlotFleetKeyedMerge.fields(
            slice: slice,
            fallbackBattery: nil,
            fallbackLifecycle: nil,
            fallbackDeviceArtVehicleClass: .uavCopter,
            fallbackFleetDisplayShortID: "UAV-C:1"
        )
        XCTAssertEqual(out.fleetDisplayShortID, "UAV-V:9")
        XCTAssertEqual(out.vehicleClassForBundledDeviceArt, .uavFixedWing)
    }
}
