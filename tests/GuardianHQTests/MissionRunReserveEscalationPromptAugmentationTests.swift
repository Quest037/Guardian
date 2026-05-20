import Foundation
import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunReserveEscalationPromptAugmentationTests: XCTestCase {

    func test_augmentation_empty_when_reason_not_airframe_replacement() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedDevice: "",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        let esc = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
            vehicleID: "V-1",
            stepID: .literal("s"),
            reason: .unrecoverableFailure(kind: .vehicleOffline),
            allowedVerbs: [.acknowledge],
            lastResponse: .success()
        )
        let r = MissionRunReserveEscalationPromptAugmentation.augmentation(
            run: run,
            vacancyAssignmentID: vacancy.id,
            missionTaskID: task.id,
            escalation: esc
        )
        XCTAssertTrue(r.extraFacts.isEmpty)
        XCTAssertNil(r.bodyAppendix)
    }

    func test_augmentation_counts_class_matched_pool_candidates() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "A", attachedDevice: "poolA"),
            ]),
            forTaskID: task.id
        )
        let esc = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
            vehicleID: "V-1",
            stepID: .literal("s"),
            reason: .unrecoverableFailure(kind: .needsAirframeReplacement),
            allowedVerbs: [.acknowledge],
            lastResponse: .success()
        )
        let r = MissionRunReserveEscalationPromptAugmentation.augmentation(
            run: run,
            vacancyAssignmentID: vacancy.id,
            missionTaskID: task.id,
            escalation: esc
        )
        XCTAssertEqual(r.extraFacts.count, 1)
        XCTAssertTrue(r.extraFacts[0].value.contains("1 on this task"))
        XCTAssertNotNil(r.bodyAppendix)
        XCTAssertTrue(r.bodyAppendix!.contains("Swap in reserve"))
    }

    func test_defaultsFor_needsAirframeReplacement_uses_warning_copy() {
        let triple = OperatorPromptEvent.defaultsFor(
            reason: .unrecoverableFailure(kind: .needsAirframeReplacement)
        )
        XCTAssertEqual(triple.severity, .warning)
        XCTAssertTrue(triple.title.contains("Airframe"))
    }
}
