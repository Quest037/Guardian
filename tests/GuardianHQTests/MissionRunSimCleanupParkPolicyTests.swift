import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunSimCleanupParkPolicyTests: XCTestCase {
    private func attachSitlAndFleet(
        sitl: SitlService,
        fleet: FleetLinkService,
        sitlInstanceID: UUID,
        stackInstanceIndex: Int = 0
    ) {
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlInstanceID, stackInstanceIndex: stackInstanceIndex)
        let systemID = stackInstanceIndex + 1
        let vehicleID = "sysid:\(systemID)"
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vehicleID, systemID: systemID)
    }

    func test_orderedCleanupParkTargets_emptyWithoutSeededStream() {
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let ghost = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let a = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "P",
            attachedDevice: "",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(ghost).storageKey
        )
        let targets = MissionRunSimCleanupParkPolicy.orderedCleanupParkTargets(
            assignments: [a],
            reservePoolByTaskID: [:],
            fleetLink: fleet,
            sitl: sitl
        )
        XCTAssertTrue(targets.isEmpty)
    }

    func test_orderedCleanupParkTargets_dedupesSameSitlTwiceOnRoster() {
        let sitlID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let fleet = FleetLinkService()
        let sitl = SitlService()
        attachSitlAndFleet(sitl: sitl, fleet: fleet, sitlInstanceID: sitlID)
        let token = FleetMissionVehicleToken.sitl(sitlID).storageKey
        let r1 = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "Alpha",
            attachedDevice: "",
            attachedFleetVehicleToken: token
        )
        let r2 = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "Bravo",
            attachedDevice: "",
            attachedFleetVehicleToken: token
        )
        let targets = MissionRunSimCleanupParkPolicy.orderedCleanupParkTargets(
            assignments: [r1, r2],
            reservePoolByTaskID: [:],
            fleetLink: fleet,
            sitl: sitl
        )
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.assignment.slotName, "Alpha")
    }

    func test_orderedCleanupParkTargets_rosterBeforePool_sameVehicleOnce() {
        let sitlID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let fleet = FleetLinkService()
        let sitl = SitlService()
        attachSitlAndFleet(sitl: sitl, fleet: fleet, sitlInstanceID: sitlID)
        let token = FleetMissionVehicleToken.sitl(sitlID).storageKey
        let roster = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedDevice: "",
            attachedFleetVehicleToken: token
        )
        let taskID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        let poolSlot = MissionRunReservePoolSlot(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!,
            label: "Reserve 1",
            attachedFleetVehicleToken: token,
            attachedDevice: ""
        )
        let pool = MissionRunReservePool(entries: [poolSlot])
        let targets = MissionRunSimCleanupParkPolicy.orderedCleanupParkTargets(
            assignments: [roster],
            reservePoolByTaskID: [taskID: pool],
            fleetLink: fleet,
            sitl: sitl
        )
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.assignment.slotName, "Primary")
    }

    func test_catalogueMissionClearCommand_runCleanupIssuer() {
        let sid = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
        let token = FleetMissionVehicleToken.sitl(sid).storageKey
        let a = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "Slot",
            attachedDevice: "",
            attachedFleetVehicleToken: token
        )
        guard let issued = MissionRunPlannerSubsystem.catalogueMissionClearCommand(
            forAssignment: a,
            issuerKey: MissionRunCommandIssuerKey.runCleanupMissionClear
        ) else {
            XCTFail("expected mission clear issued command")
            return
        }
        XCTAssertEqual(issued.issuerKey, MissionRunCommandIssuerKey.runCleanupMissionClear)
        XCTAssertEqual(issued.issuer, .missionControl)
        guard case .catalogue(let name, _) = issued.dispatch else {
            XCTFail("expected catalogue mission clear")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoMissionClear)
    }

    func test_catalogueGeofenceClearCommand_runCleanupIssuer() {
        let sid = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
        let token = FleetMissionVehicleToken.sitl(sid).storageKey
        let a = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "Slot",
            attachedDevice: "",
            attachedFleetVehicleToken: token
        )
        guard let issued = MissionRunPlannerSubsystem.catalogueGeofenceClearCommand(
            forAssignment: a,
            issuerKey: MissionRunCommandIssuerKey.runCleanupGeofenceClear
        ) else {
            XCTFail("expected geofence clear issued command")
            return
        }
        XCTAssertEqual(issued.issuerKey, MissionRunCommandIssuerKey.runCleanupGeofenceClear)
        XCTAssertEqual(issued.issuer, .missionControl)
        guard case .catalogue(let name, _) = issued.dispatch else {
            XCTFail("expected catalogue geofence clear")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoGeofenceClear)
    }
}
