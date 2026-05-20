import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunBrainExecutionSubsystemTests: XCTestCase {
    func test_segmentSkipReason_convoy_pattern() {
        let subsystem = MissionRunBrainExecutionSubsystem()
        let deviceId = UUID()
        let task = MissionTask(
            name: "Convoy",
            pattern: .convoy,
            regularity: .onceAtStart,
            cycles: 1,
            betweenCycles: .park
        )
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
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: deviceId,
            slotName: "Alpha"
        )
        let bindings = [
            MissionRunBrainBinding(
                taskKindRaw: TrainingTaskKind.reverseIntoSlot.rawValue,
                vehicleClassRaw: TrainingVehicleClass.ugvWheeled.rawValue,
                brainId: UUID(),
                brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
                displayName: "Test"
            ),
        ]
        let reason = subsystem.segmentSkipReason(
            primaryAssignment: assignment,
            task: task,
            mission: mission,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            bindings: bindings
        )
        XCTAssertEqual(reason, "Convoy task pattern uses the squad assembly pipeline, not brain segments.")
    }

    func test_segmentSkipReason_nil_for_planner_only_pack_with_layout() throws {
        let subsystem = MissionRunBrainExecutionSubsystem()
        let deviceId = UUID()
        let task = MissionTask(
            name: "Patrol",
            pattern: .patrol,
            regularity: .onceAtStart,
            cycles: 1,
            betweenCycles: .park
        )
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
            routeMacro: RouteMacro(tasks: [task])
        )
        let sessionID = UUID()
        let assignment = MissionRunAssignment(
            taskId: task.id,
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
            displayName: "Planner brain"
        )
        pack.skill.segments = []
        pack.plannerHints = GuardianBrainPackPlannerHints(frameId: "map", maxSpeedMS: 0.5)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissionRunBrainExec-\(UUID().uuidString)", isDirectory: true)
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
            mavlinkSystemID: 1,
            preset: .ugvWheeled
        )
        fleetLink.setSimulateEnabled(true)
        fleetLink.registerSimulatedVehicle(
            systemID: 1,
            mavlinkConnectionURL: "udpin://0.0.0.0:14560",
            autopilotStack: .px4,
            vehicleType: .ugvWheeled,
            spawnDefaults: .default
        )
        let reason = subsystem.segmentSkipReason(
            primaryAssignment: assignment,
            task: task,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            bindings: [binding]
        )
        XCTAssertNil(reason)
    }

    func test_finishBrainSegmentSuccess_posts_missionCycleFinished() {
        let sitl = UUID()
        let deviceId = UUID()
        let task = MissionTask(
            name: "Once",
            pattern: .patrol,
            regularity: .onceAtStart,
            cycles: 1,
            betweenCycles: .park
        )
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
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: deviceId,
            slotName: "Alpha",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitl).storageKey
        )
        let fleet = FleetLinkService()
        let sitlSvc = SitlService()
        sitlSvc.attachFleetLink(fleet)
        sitlSvc.seedMissionRunTestSitlRunningInstance(id: sitl, mavlinkSystemID: 3, preset: .ugvWheeled)
        guard let vid = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleet, sitl: sitlSvc) else {
            XCTFail("Expected stream id")
            return
        }

        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        run.attachServices(fleetLink: fleet, sitl: sitlSvc)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markTaskActiveInCurrentCycle(task.id)
        let squads = run.systems.planner.buildTaskSquadMissions(mission: mission, taskId: task.id)
        run.markSquadActiveInCurrentCycle(squads[0].squad.primaryAssignment.id)

        let subsystem = MissionRunBrainExecutionSubsystem()
        subsystem.environment = run
        let binding = MissionRunBrainBinding(
            taskKindRaw: TrainingTaskKind.reverseIntoSlot.rawValue,
            vehicleClassRaw: TrainingVehicleClass.ugvWheeled.rawValue,
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Test"
        )
        let plan = MissionRunBrainExecutionSubsystem.SegmentLaunchPlan(
            assignmentID: assignment.id,
            slotName: assignment.slotName,
            vehicleID: vid,
            taskID: task.id,
            taskLabel: task.name,
            binding: binding,
            segments: [.forward(0.5, durationS: 1)],
            correlationSource: "test",
            formatVersion: 1
        )
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitlSvc,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)

        subsystem.finishBrainSegmentSuccess(plan: plan)
        XCTAssertEqual(run.taskCyclesCompletedByTaskID[task.id], 1)
    }
}
