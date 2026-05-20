import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunFleetWindDownBeforeShellChangeTests: XCTestCase {

    func test_awaitFleetWindDownBeforeRunShellChange_waits_for_in_flight_sim_cleanup_latch() async {
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let mission = Mission(name: "Op", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        run.attachServices(fleetLink: fleet, sitl: sitl, generalSettings: GeneralSettingsStore())
        run.setMissionRunSimCleanupPassRunning(true)

        let waitTask = Task {
            await run.awaitFleetWindDownBeforeRunShellChange(fleetLink: fleet, sitl: sitl)
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(waitTask.isCancelled)
        run.setMissionRunSimCleanupPassRunning(false)
        await waitTask.value
    }
}
