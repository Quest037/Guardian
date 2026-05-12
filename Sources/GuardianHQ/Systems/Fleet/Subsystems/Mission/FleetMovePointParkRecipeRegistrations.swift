import Foundation
import os

/// Layer 1 **navigate then park** recipe for Mission Control / MRE (`recipe.fleet.do.move.point.park`).
///
/// Body lives in ``bodiesSubdirectoryName`` with ``FleetMissionRecipeRegistrations`` (`MissionBodies`).
@MainActor
enum FleetMovePointParkRecipeRegistrations {

    private static let log = OSLog(
        subsystem: "guardian.fleet.recipesCatalogue",
        category: "mission.movePointPark"
    )

    static let bodiesSubdirectoryName = FleetMissionRecipeRegistrations.bodiesSubdirectoryName

    static let movePointParkRecipeName = FleetRecipeName.literal(
        "recipe.fleet.do.move.point.park"
    )

    static func registerAll() {
        let before = FleetRecipesCatalogue.shared.descriptors.count
        registerMovePointPark()
        let added = FleetRecipesCatalogue.shared.descriptors.count - before
        os_log(.info, log: log, "Fleet move+park recipe registered (%{public}d new).", added)
    }

    private static func registerMovePointPark() {
        let name = movePointParkRecipeName
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
            body = makeMovePointParkBodyBuiltIn()
        }

        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "Move to point and park",
            humanDescription:
                "Runs the catalogue arm probe (arm then disarm to verify the vehicle is arm-ready), arms again for the manoeuvre, moves to explicit latitude/longitude at the supplied relative altitude (use current vehicle AGL when resolving), then runs the park pipeline (class-aware land/surface, disarm, hold). " +
                "Pass procedureLogSummary for MC-R logs (e.g. \"Move to rally point [RP:1]\").",
            parameters: [
                FleetRecipeParameterDeclaration(
                    name: "procedureLogSummary",
                    type: .string,
                    required: true,
                    humanLabel: "Procedure log line"
                ),
                FleetRecipeParameterDeclaration(
                    name: "pointKind",
                    type: .string,
                    required: true,
                    allowedStringValues: FleetVehicleCoreCommandPointKind.allowedSet,
                    humanLabel: "Move.point pointKind"
                ),
                FleetRecipeParameterDeclaration(
                    name: "latitudeDeg",
                    type: .double,
                    required: true,
                    humanLabel: "Target latitude (deg)"
                ),
                FleetRecipeParameterDeclaration(
                    name: "longitudeDeg",
                    type: .double,
                    required: true,
                    humanLabel: "Target longitude (deg)"
                ),
                FleetRecipeParameterDeclaration(
                    name: "relativeAltitudeM",
                    type: .double,
                    required: true,
                    humanLabel: "Relative altitude (m)"
                ),
                FleetRecipeParameterDeclaration(
                    name: "yawDeg",
                    type: .double,
                    required: false,
                    humanLabel: "Yaw (deg)"
                ),
            ],
            riskTier: .confirmInLiveMission,
            expectedDuration: 180,
            appliesToSystems: ["mission"],
            defaultRetryPolicy: .catalogueDefault,
            relaxRetryCaps: false,
            containsRecipes: [
                .literal("recipe.fleet.diagnose.armprobe"),
            ],
            body: body,
            cancelRecipe: nil
        )
        if !FleetRecipesCatalogue.shared.register(descriptor) {
            os_log(.fault, log: log, "FleetRecipesCatalogue refused move+park recipe %{public}@.", name.rawValue)
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

    /// Same steps as `MissionBodies/recipe.fleet.do.move.point.park.json`, authored in Swift so
    /// registration succeeds when the JSON resource is not present in the host bundle (Xcode/CI).
    private static func makeMovePointParkBodyBuiltIn() -> FleetRecipeBody {
        let moveParams = FleetRecipeParameters(values: [
            "pointKind": .reference(name: "pointKind"),
            "latitudeDeg": .reference(name: "latitudeDeg"),
            "longitudeDeg": .reference(name: "longitudeDeg"),
            "relativeAltitudeM": .reference(name: "relativeAltitudeM"),
            "yawDeg": .reference(name: "yawDeg"),
        ])
        let armRetry = FleetRecipeRetryPolicy(
            maxAttempts: 3,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let moveRetry = FleetRecipeRetryPolicy(
            maxAttempts: 3,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let parkRetry = FleetRecipeRetryPolicy(
            maxAttempts: 2,
            delaySeconds: 0.5,
            retryableErrorKinds: [.autopilotBusy, .noSession, .notConnected],
            retryOnTimeout: true
        )
        let liveMissionEscalate = FleetRecipeControlOutcome.escalate(
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.abort, .acknowledge, .retry]
        )

        let armProbe = FleetRecipeStep.invokeRecipe(
            id: .literal("armProbe"),
            recipe: .literal("recipe.fleet.diagnose.armprobe"),
            parameters: .empty,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let reArm = FleetRecipeStep.invokeCommand(
            id: .literal("reArm"),
            command: .fleetVehicleDoArm,
            parameters: .empty,
            retry: armRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .error(kind: .alreadyArmed), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let move = FleetRecipeStep.invokeCommand(
            id: .literal("move"),
            command: .fleetVehicleDoMovePoint,
            parameters: moveParams,
            retry: moveRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )
        let park = FleetRecipeStep.invokeCommand(
            id: .literal("park"),
            command: .fleetVehicleDoPark,
            parameters: .empty,
            retry: parkRetry,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .succeed),
                FleetRecipeStepMatcher(when: .any, then: liveMissionEscalate),
            ]
        )

        return FleetRecipeBody(
            entryStepID: .literal("armProbe"),
            steps: [armProbe, reArm, move, park],
            overallBudgetSeconds: 600
        )
    }
}
