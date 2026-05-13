import Foundation
import os

/// Core **mission execution** recipes (Layer 1) used by Mission Run Environment (MRE).
///
/// Bodies live under ``bodiesSubdirectoryName`` (`MissionBodies`) and are copied into
/// the GuardianHQ bundle via `Package.swift` resources (same pattern as calibration).
@MainActor
enum FleetMissionRecipeRegistrations {

    private static let log = OSLog(
        subsystem: "guardian.fleet.recipesCatalogue",
        category: "mission"
    )

    static let bodiesSubdirectoryName = "MissionBodies"

    /// Canonical name for the MRE MAVLink mission start recipe (`do.mission.upload.start` — arm is in the body, not the id).
    static let doMissionUploadStartRecipeName = FleetRecipeName.literal(
        "recipe.fleet.do.mission.upload.start"
    )

    /// Upload full mission, **set current mission item** (0-based index), arm, start — used when the displaced
    /// stream had **mission progress &gt; 0** so the reserve picks up mid-mission; otherwise use ``doMissionUploadStartRecipeName``.
    static let doMissionUploadStartItemRecipeName = FleetRecipeName.literal(
        "recipe.fleet.do.mission.upload.start.item"
    )

    /// Single-step RTL / return-home recipe wrapping ``FleetCommandName/fleetVehicleDoReturnHome``.
    static let doReturnHomeRecipeName = FleetRecipeName.literal(
        "recipe.fleet.do.return.home"
    )

    /// Single-step park recipe wrapping ``FleetCommandName/fleetVehicleDoPark`` (Mission Run cleanup, SIM park shells).
    static let vehicleDoParkRecipeName = FleetRecipeName.literal(
        "recipe.fleet.vehicle.do.park"
    )

    /// After **PX4 UGV** operator park (offboard brake + disarm): set AUTO_MISSION, arm, ``Mission/startMission`` (MAVSDK has no resume).
    nonisolated static let doContinueMissionAfterOperatorParkRecipeName = FleetRecipeName.literal(
        "recipe.fleet.do.mission.continue.after.operator.park"
    )

    static func registerAll() {
        let before = FleetRecipesCatalogue.shared.descriptors.count
        registerDoMissionUploadStart()
        registerDoMissionUploadStartItem()
        registerDoReturnHome()
        registerVehicleDoPark()
        registerDoContinueMissionAfterOperatorPark()
        let added = FleetRecipesCatalogue.shared.descriptors.count - before
        os_log(.info, log: log, "Fleet mission recipes registered (%{public}d new).", added)
    }

    private static func registerDoMissionUploadStart() {
        let name = doMissionUploadStartRecipeName
        let body: FleetRecipeBody
        if let loaded = loadBody(for: name) {
            body = loaded
        } else {
            os_log(
                .info,
                log: log,
                "Using compiled-in body for %{public}@ (MissionBodies JSON not loaded from bundle).",
                name.rawValue
            )
            body = makeDoMissionUploadStartBodyBuiltIn()
        }

        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "Mission upload, arm, and start",
            humanDescription:
                "Uploads the MAVLink mission plan, arms the vehicle, then starts mission execution. " +
                "Catalogue id is recipe.fleet.do.mission.upload.start (arm is part of this flow, not a segment in the name). " +
                "Used by Mission Control runs; transient autopilot/link errors retry before escalating to the operator on the run panel.",
            parameters: [
                FleetRecipeParameterDeclaration(
                    name: "missionItemsJSON",
                    type: .string,
                    required: true,
                    humanLabel: "Mission items (JSON array)"
                ),
            ],
            riskTier: .confirmInLiveMission,
            expectedDuration: 45,
            appliesToSystems: ["mission"],
            defaultRetryPolicy: .catalogueDefault,
            relaxRetryCaps: false,
            body: body,
            cancelRecipe: nil
        )
        if !FleetRecipesCatalogue.shared.register(descriptor) {
            os_log(.fault, log: log, "FleetRecipesCatalogue refused mission recipe %{public}@.", name.rawValue)
        }
    }

    private static func registerDoMissionUploadStartItem() {
        let name = doMissionUploadStartItemRecipeName
        let body: FleetRecipeBody
        if let loaded = loadBody(for: name) {
            body = loaded
        } else {
            os_log(
                .info,
                log: log,
                "Using compiled-in body for %{public}@ (MissionBodies JSON not loaded from bundle).",
                name.rawValue
            )
            body = makeDoMissionUploadStartItemBodyBuiltIn()
        }

        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "Mission upload, set current item, arm, and start",
            humanDescription:
                "Uploads the full MAVLink mission plan, sets the current mission item index (`command.fleet.vehicle.do.mission.jump.to`), " +
                "arms, then starts mission execution. Used when reserve swap-in must resume from the displaced stream’s last-known " +
                "mission progress; when progress is 0 or unknown use `recipe.fleet.do.mission.upload.start` instead.",
            parameters: [
                FleetRecipeParameterDeclaration(
                    name: "missionItemsJSON",
                    type: .string,
                    required: true,
                    humanLabel: "Mission items (JSON array)"
                ),
                FleetRecipeParameterDeclaration(
                    name: "missionStartItemIndex",
                    type: .integer,
                    required: true,
                    humanLabel: "Mission item index (0-based) after upload"
                ),
            ],
            riskTier: .confirmInLiveMission,
            expectedDuration: 50,
            appliesToSystems: ["mission"],
            defaultRetryPolicy: .catalogueDefault,
            relaxRetryCaps: false,
            body: body,
            cancelRecipe: nil
        )
        if !FleetRecipesCatalogue.shared.register(descriptor) {
            os_log(.fault, log: log, "FleetRecipesCatalogue refused mission recipe %{public}@.", name.rawValue)
        }
    }

    private static func registerDoReturnHome() {
        let name = doReturnHomeRecipeName
        let body: FleetRecipeBody
        if let loaded = loadBody(for: name) {
            body = loaded
        } else {
            os_log(
                .info,
                log: log,
                "Using compiled-in body for %{public}@ (MissionBodies JSON not loaded from bundle).",
                name.rawValue
            )
            body = makeDoReturnHomeBodyBuiltIn()
        }

        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "Return home",
            humanDescription:
                "Invokes catalogue command.fleet.vehicle.do.return.home (RTL toward home / launch). " +
                "Used by Mission Control runs and recipes that need a Layer-1 wrapper with retries and live-mission escalation.",
            parameters: [],
            riskTier: .confirmInLiveMission,
            expectedDuration: 60,
            appliesToSystems: ["mission"],
            defaultRetryPolicy: .catalogueDefault,
            relaxRetryCaps: false,
            body: body,
            cancelRecipe: nil
        )
        if !FleetRecipesCatalogue.shared.register(descriptor) {
            os_log(.fault, log: log, "FleetRecipesCatalogue refused mission recipe %{public}@.", name.rawValue)
        }
    }

    private static func registerVehicleDoPark() {
        let name = vehicleDoParkRecipeName
        let body: FleetRecipeBody
        if let loaded = loadBody(for: name) {
            body = loaded
        } else {
            os_log(
                .info,
                log: log,
                "Using compiled-in body for %{public}@ (MissionBodies JSON not loaded from bundle).",
                name.rawValue
            )
            body = makeVehicleDoParkBodyBuiltIn()
        }

        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "Park vehicle",
            humanDescription:
                "Invokes catalogue command.fleet.vehicle.do.park (class-aware park / hold / disarm per stack). " +
                "Used for Mission Run SIM cleanup and other Layer-1 callers that need retries and live-mission escalation without the full move-then-park recipe.",
            parameters: [],
            riskTier: .confirmInLiveMission,
            expectedDuration: 45,
            appliesToSystems: ["mission"],
            defaultRetryPolicy: .catalogueDefault,
            relaxRetryCaps: false,
            body: body,
            cancelRecipe: nil
        )
        if !FleetRecipesCatalogue.shared.register(descriptor) {
            os_log(.fault, log: log, "FleetRecipesCatalogue refused mission recipe %{public}@.", name.rawValue)
        }
    }

    private static func registerDoContinueMissionAfterOperatorPark() {
        let name = doContinueMissionAfterOperatorParkRecipeName
        let body: FleetRecipeBody
        if let loaded = loadBody(for: name) {
            body = loaded
        } else {
            os_log(
                .info,
                log: log,
                "Using compiled-in body for %{public}@ (MissionBodies JSON not loaded from bundle).",
                name.rawValue
            )
            body = makeDoContinueMissionAfterOperatorParkBodyBuiltIn()
        }

        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "Continue mission after operator park",
            humanDescription:
                "Stops offboard first (`command.fleet.vehicle.do.offboard.stop`) so PX4 exits the parked offboard stream before mode change, then sets mission mode (`command.fleet.vehicle.do.mode` mission / AUTO_MISSION on PX4), arms if needed, and starts mission execution (`Mission.startMission`). " +
                "Used after PX4 UGV **Park** when offboard was left active; behaviour on a paused mission is stack-defined.",
            parameters: [],
            riskTier: .confirmInLiveMission,
            expectedDuration: 55,
            appliesToSystems: ["mission"],
            defaultRetryPolicy: .catalogueDefault,
            relaxRetryCaps: false,
            body: body,
            cancelRecipe: nil
        )
        if !FleetRecipesCatalogue.shared.register(descriptor) {
            os_log(.fault, log: log, "FleetRecipesCatalogue refused mission recipe %{public}@.", name.rawValue)
        }
    }

    private static func loadBody(for name: FleetRecipeName) -> FleetRecipeBody? {
        let outcome = FleetRecipeBodyLoader.load(
            recipeName: name,
            inSubdirectory: bodiesSubdirectoryName,
            bundle: .module
        )
        switch outcome {
        case .success(let body):
            return body
        case .failure(let err):
            os_log(.fault, log: log, "Body load failed for %{public}@: %{public}@", name.rawValue, err.description)
            return nil
        }
    }

    /// Same steps as `MissionBodies/recipe.fleet.do.mission.upload.start.json`, authored in Swift so
    /// registration succeeds when the JSON resource is not present in the host bundle (Xcode/CI).
    private static func makeDoMissionUploadStartBodyBuiltIn() -> FleetRecipeBody {
        let missionItemsJSON = FleetRecipeParameters(values: [
            "missionItemsJSON": .reference(name: "missionItemsJSON"),
        ])
        let stepRetry = FleetRecipeRetryPolicy(
            maxAttempts: 3,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let liveMissionEscalate = FleetRecipeControlOutcome.escalate(
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.abort, .acknowledge, .retry]
        )

        let upload = FleetRecipeStep.invokeCommand(
            id: .literal("upload"),
            command: .fleetVehicleDoMissionUpload,
            parameters: missionItemsJSON,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let arm = FleetRecipeStep.invokeCommand(
            id: .literal("arm"),
            command: .fleetVehicleDoArm,
            parameters: .empty,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .error(kind: .alreadyArmed), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let start = FleetRecipeStep.invokeCommand(
            id: .literal("start"),
            command: .fleetVehicleDoMissionStart,
            parameters: missionItemsJSON,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .succeed),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )

        return FleetRecipeBody(
            entryStepID: .literal("upload"),
            steps: [upload, arm, start],
            overallBudgetSeconds: 180
        )
    }

    /// Same steps as `MissionBodies/recipe.fleet.do.mission.upload.start.item.json`, authored in Swift so
    /// registration succeeds when the JSON resource is not present in the host bundle (Xcode/CI).
    private static func makeDoMissionUploadStartItemBodyBuiltIn() -> FleetRecipeBody {
        let missionItemsJSON = FleetRecipeParameters(values: [
            "missionItemsJSON": .reference(name: "missionItemsJSON"),
        ])
        let jumpParams = FleetRecipeParameters(values: [
            "index": .reference(name: "missionStartItemIndex"),
        ])
        let stepRetry = FleetRecipeRetryPolicy(
            maxAttempts: 3,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let liveMissionEscalate = FleetRecipeControlOutcome.escalate(
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.abort, .acknowledge, .retry]
        )

        let upload = FleetRecipeStep.invokeCommand(
            id: .literal("upload"),
            command: .fleetVehicleDoMissionUpload,
            parameters: missionItemsJSON,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let setMissionItem = FleetRecipeStep.invokeCommand(
            id: .literal("setMissionItem"),
            command: .fleetVehicleDoMissionJumpTo,
            parameters: jumpParams,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let arm = FleetRecipeStep.invokeCommand(
            id: .literal("arm"),
            command: .fleetVehicleDoArm,
            parameters: .empty,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .error(kind: .alreadyArmed), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let start = FleetRecipeStep.invokeCommand(
            id: .literal("start"),
            command: .fleetVehicleDoMissionStart,
            parameters: missionItemsJSON,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .succeed),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )

        return FleetRecipeBody(
            entryStepID: .literal("upload"),
            steps: [upload, setMissionItem, arm, start],
            overallBudgetSeconds: 180
        )
    }

    /// Same step as `MissionBodies/recipe.fleet.do.return.home.json`, authored in Swift so
    /// registration succeeds when the JSON resource is not present in the host bundle.
    private static func makeDoReturnHomeBodyBuiltIn() -> FleetRecipeBody {
        let stepRetry = FleetRecipeRetryPolicy(
            maxAttempts: 3,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let liveMissionEscalate = FleetRecipeControlOutcome.escalate(
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.abort, .acknowledge, .retry]
        )
        let rtl = FleetRecipeStep.invokeCommand(
            id: .literal("returnHome"),
            command: .fleetVehicleDoReturnHome,
            parameters: .empty,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .succeed),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        return FleetRecipeBody(
            entryStepID: .literal("returnHome"),
            steps: [rtl],
            overallBudgetSeconds: 120
        )
    }

    /// Same step as `MissionBodies/recipe.fleet.vehicle.do.park.json`, authored in Swift so
    /// registration succeeds when the JSON resource is not present in the host bundle.
    private static func makeVehicleDoParkBodyBuiltIn() -> FleetRecipeBody {
        let stepRetry = FleetRecipeRetryPolicy(
            maxAttempts: 3,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let liveMissionEscalate = FleetRecipeControlOutcome.escalate(
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.abort, .acknowledge, .retry]
        )
        let park = FleetRecipeStep.invokeCommand(
            id: .literal("park"),
            command: .fleetVehicleDoPark,
            parameters: .empty,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .succeed),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        return FleetRecipeBody(
            entryStepID: .literal("park"),
            steps: [park],
            overallBudgetSeconds: 120
        )
    }

    private static func makeDoContinueMissionAfterOperatorParkBodyBuiltIn() -> FleetRecipeBody {
        let modeMissionParams = FleetRecipeParameters(values: [
            "mode": .string(FleetVehicleMode.mission.rawValue),
        ])
        let stepRetry = FleetRecipeRetryPolicy(
            maxAttempts: 3,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let liveMissionEscalate = FleetRecipeControlOutcome.escalate(
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.abort, .acknowledge, .retry]
        )
        let stopOffboard = FleetRecipeStep.invokeCommand(
            id: .literal("stopOffboard"),
            command: .fleetVehicleDoOffboardStop,
            parameters: .empty,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let modeMission = FleetRecipeStep.invokeCommand(
            id: .literal("modeMission"),
            command: .fleetVehicleDoMode,
            parameters: modeMissionParams,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let arm = FleetRecipeStep.invokeCommand(
            id: .literal("arm"),
            command: .fleetVehicleDoArm,
            parameters: .empty,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .error(kind: .alreadyArmed), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let startMission = FleetRecipeStep.invokeCommand(
            id: .literal("startMission"),
            command: .fleetVehicleDoMissionStart,
            parameters: .empty,
            retry: stepRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .succeed),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        return FleetRecipeBody(
            entryStepID: .literal("stopOffboard"),
            steps: [stopOffboard, modeMission, arm, startMission],
            overallBudgetSeconds: 150
        )
    }
}
