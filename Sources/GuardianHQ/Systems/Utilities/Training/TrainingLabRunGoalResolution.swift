import Foundation

/// Per-vehicle transit plan for a Training lab **Run** (start zone → end zone).
struct TrainingLabRunVehiclePlan: Equatable, Sendable {
    enum SquadRole: Equatable, Sendable {
        /// Skill teach / eval target for this run.
        case learning
        /// Brain runs a known-simple transit the stack already handles well.
        case supporting
    }

    let entryID: UUID
    let squadID: UUID
    let squadIndex: Int
    let squadLabel: String
    let vehicleID: String
    let role: SquadRole
    let layout: TrainingTaskLayout
    let endSlot: TrainingLabFormationSlotGeometry.Slot
    /// When true, run monitor requires the vehicle centre inside the end slot footprint (explicit end formation policy).
    let requiresStrictEndSlotBox: Bool
}

/// Resolved plans for all linked squads on one Run.
struct TrainingLabRunSessionPlan: Equatable, Sendable {
    let vehiclePlans: [TrainingLabRunVehiclePlan]
}

enum TrainingLabRunGoalResolution {
    struct Issue: Equatable, Sendable {
        var message: String
    }

    struct BuildResult: Equatable, Sendable {
        var plans: TrainingLabRunSessionPlan?
        var issues: [Issue]

        var isReady: Bool { issues.isEmpty && plans != nil }
    }

    /// Build start→end layouts for every squad with a linked simulator (primary-only v1).
    static func buildSessionPlan(
        squads: [TrainingLabSquad],
        zones: WorldBuilderZonesSnapshot,
        environment: TrainingEnvironmentPackage,
        mapGeodeticOrigin: SimSpawnDefaults,
        learningSquadID: UUID?
    ) -> BuildResult {
        var issues: [Issue] = []
        var plans: [TrainingLabRunVehiclePlan] = []
        let resolvedLearningID = learningSquadID ?? squads.first?.id

        for (squadIndex, squad) in squads.enumerated() {
            guard squad.hasLinkedSimulator else { continue }
            let label = TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex)

            if !squad.isSingleVehicle {
                issues.append(
                    Issue(
                        message: "\(label) has wingmen — multi-vehicle transit is not available yet. Use a single-vehicle squad for this run."
                    )
                )
                continue
            }

            guard let vehicleID = squad.primary.vehicleID else {
                issues.append(Issue(message: "\(label) has no linked simulator."))
                continue
            }

            let planner = GuardianAutonomyPlannerRouting.defaultPlannerKind(
                for: squad.primary.vehicleClass.fleetVehicleType
            )
            if planner != .nav2 {
                issues.append(
                    Issue(message: "\(label) vehicle class does not use Nav2 transit in v1.")
                )
                continue
            }

            let startAnchor = squad.startZoneAnchor ?? .seeded(in: zones.start)
            let endAnchor = squad.endZoneAnchor ?? .seeded(in: zones.end)
            let startLayout = TrainingLabFormationSlotGeometry.groupLayout(
                squad: squad,
                squadIndex: squadIndex,
                phase: .start,
                anchor: startAnchor
            )
            let endLayout = TrainingLabFormationSlotGeometry.groupLayout(
                squad: squad,
                squadIndex: squadIndex,
                phase: .end,
                anchor: endAnchor
            )
            guard let startSlot = startLayout.slots.first, let endSlot = endLayout.slots.first else {
                issues.append(Issue(message: "\(label) could not resolve formation slots."))
                continue
            }

            let startPose = taskPose(slot: startSlot, mapGeodeticOrigin: mapGeodeticOrigin)
            let goalPose = taskPose(slot: endSlot, mapGeodeticOrigin: mapGeodeticOrigin)
            let role: TrainingLabRunVehiclePlan.SquadRole =
                squad.id == resolvedLearningID ? .learning : .supporting

            plans.append(
                TrainingLabRunVehiclePlan(
                    entryID: squad.primary.id,
                    squadID: squad.id,
                    squadIndex: squadIndex,
                    squadLabel: label,
                    vehicleID: vehicleID,
                    role: role,
                    layout: TrainingTaskLayout(start: startPose, goal: goalPose),
                    endSlot: endSlot,
                    requiresStrictEndSlotBox: squad.formationPolicy.endFormation != nil
                )
            )
        }

        if plans.isEmpty, issues.isEmpty {
            issues.append(Issue(message: "Add at least one linked single-vehicle squad before Run."))
        }

        guard issues.isEmpty else {
            return BuildResult(plans: nil, issues: issues)
        }
        return BuildResult(plans: TrainingLabRunSessionPlan(vehiclePlans: plans), issues: [])
    }

    private static func taskPose(
        slot: TrainingLabFormationSlotGeometry.Slot,
        mapGeodeticOrigin: SimSpawnDefaults
    ) -> TrainingTaskPose {
        let env = TrainingEnvironmentPose(
            xM: slot.centerXM,
            yM: slot.centerYM,
            zM: WorldBuilderZoneBoundsCheck.mapBaseTopZM,
            yawDeg: slot.headingDeg
        )
        return TrainingEnvironmentGeodesy.taskPose(environmentPose: env, origin: mapGeodeticOrigin)
    }
}
