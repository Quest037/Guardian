import XCTest

@testable import GuardianHQ

@MainActor
final class GuardianBrainRos2SidecarPolicyTests: XCTestCase {
    func test_missionEnrollment_enrolls_px4_with_planner_overlay() throws {
        let sessionID = UUID()
        let deviceId = UUID()
        let mission = Mission(
            name: "Test",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(
                    id: deviceId,
                    name: "Alpha",
                    behaviorRoleID: RosterRole.none.rawValue,
                    slot: .primary,
                    vehicleClass: .ugvWheeled
                ),
            ],
            routeMacro: RouteMacro(tasks: [])
        )
        let assignment = MissionRunAssignment(
            rosterDeviceId: deviceId,
            slotName: "Alpha",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sessionID).storageKey
        )

        var pack = try GuardianBrainPackBuilder.makePack(
            from: TrainedVehicleSkill(
                taskKind: .reverseIntoSlot,
                vehicleClass: .ugvWheeled,
                segments: [],
                score: TrainingSkillScore(
                    positionErrorM: 0.2,
                    headingErrorDeg: 1,
                    episodeDurationS: 5,
                    constraintViolations: [],
                    succeeded: true
                ),
                layout: TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default),
                trialIndex: 0,
                summary: "planner"
            ),
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "UGV lab"
        )
        pack.plannerHints = GuardianBrainPackBuilder.plannerHints(
            from: GuardianBrainPackTrainingPlannerContext(
                vehicleClass: .ugvWheeled,
                vehicleSizeTier: .medium,
                layout: pack.skill.layout,
                segments: [.forward(0.6, durationS: 2)],
                planPathSource: .nav2,
                nav2StackReady: true,
                nav2StackStatus: "ready",
                gazeboEnvironmentId: "bundled.open_field",
                planWaypointCount: 8
            )
        )
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianBrainRos2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let exportURL = tempDir.appendingPathComponent("pack.guardianbrain")
        try GuardianBrainPackExportService.write(pack: pack, to: exportURL)
        let entry = try GuardianBrainCatalogueStore.importPackFile(from: exportURL)
        defer { try? GuardianBrainCatalogueStore.deleteEntry(entry) }
        let binding = MissionRunBrainBinding(manifest: entry.manifest)

        let sitl = SitlService()
        let fleetLink = FleetLinkService()
        sitl.seedMissionRunTestSitlRunningInstance(
            id: sessionID,
            mavlinkSystemID: 12,
            preset: .ugvWheeled
        )
        fleetLink.setSimulateEnabled(true)
        fleetLink.registerSimulatedVehicle(
            systemID: 12,
            mavlinkConnectionURL: "udpin://0.0.0.0:14562",
            autopilotStack: .px4,
            vehicleType: .ugvWheeled,
            spawnDefaults: .default
        )

        let enrollment = GuardianBrainRos2SidecarPolicy.missionEnrollment(
            mission: mission,
            assignments: [assignment],
            bindings: [binding],
            fleetLink: fleetLink,
            sitl: sitl
        )

        XCTAssertEqual(enrollment.enrollPX4VehicleIDs, ["sysid:12"])
        let overlay = try XCTUnwrap(enrollment.overlaysByVehicleID["sysid:12"])
        XCTAssertEqual(overlay.brainId, binding.brainId)
        XCTAssertEqual(overlay.brainVersion, binding.brainVersion)
        XCTAssertTrue(overlay.nav2ParamOverlayJSON?.contains("guardian_training_lab") == true)
    }

    func test_missionEnrollment_empty_without_bindings() {
        let enrollment = GuardianBrainRos2SidecarPolicy.missionEnrollment(
            mission: Mission(name: "X", description: "", type: .mobile, rosterDevices: [], routeMacro: RouteMacro(tasks: [])),
            assignments: [],
            bindings: [],
            fleetLink: FleetLinkService(),
            sitl: SitlService()
        )
        XCTAssertTrue(enrollment.enrollPX4VehicleIDs.isEmpty)
        XCTAssertTrue(enrollment.overlaysByVehicleID.isEmpty)
    }
}
