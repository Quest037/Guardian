import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunEnvironmentAttachServicesTests: XCTestCase {
    func test_attachServices_secondCall_sameFleetAndSitl_isNoOp() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        let fleet = FleetLinkService()
        let sitl = SitlService()
        run.attachServices(fleetLink: fleet, sitl: sitl)
        XCTAssertTrue(run.fleetLink === fleet)
        XCTAssertTrue(run.sitl === sitl)
        run.attachServices(fleetLink: fleet, sitl: sitl)
        XCTAssertTrue(run.fleetLink === fleet)
        XCTAssertTrue(run.sitl === sitl)
    }

    func test_attachServices_replaces_whenFleetInstanceChanges() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        let fleet1 = FleetLinkService()
        let fleet2 = FleetLinkService()
        let sitl = SitlService()
        run.attachServices(fleetLink: fleet1, sitl: sitl)
        XCTAssertTrue(run.fleetLink === fleet1)
        run.attachServices(fleetLink: fleet2, sitl: sitl)
        XCTAssertTrue(run.fleetLink === fleet2)
        XCTAssertTrue(run.sitl === sitl)
    }
}
