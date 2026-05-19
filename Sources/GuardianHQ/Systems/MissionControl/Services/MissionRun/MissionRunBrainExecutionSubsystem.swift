import Foundation

/// MRE OFFBOARD brain segment execution (imported `.guardianbrain` skill chains).
@MainActor
final class MissionRunBrainExecutionSubsystem {

    enum BrainDispatchKind: String, Equatable, Sendable {
        case segmentPack
        case plannerOpenLoop
    }

    struct SegmentLaunchPlan: Equatable, Sendable {
        let assignmentID: UUID
        let slotName: String
        let vehicleID: String
        let taskID: UUID
        let taskLabel: String
        let binding: MissionRunBrainBinding
        let segments: [TrainingControlSegment]
        let correlationSource: String
        let formatVersion: Int
        let dispatchKind: BrainDispatchKind
        let pathSource: String?

        init(
            assignmentID: UUID,
            slotName: String,
            vehicleID: String,
            taskID: UUID,
            taskLabel: String,
            binding: MissionRunBrainBinding,
            segments: [TrainingControlSegment],
            correlationSource: String,
            formatVersion: Int,
            dispatchKind: BrainDispatchKind = .segmentPack,
            pathSource: String? = nil
        ) {
            self.assignmentID = assignmentID
            self.slotName = slotName
            self.vehicleID = vehicleID
            self.taskID = taskID
            self.taskLabel = taskLabel
            self.binding = binding
            self.segments = segments
            self.correlationSource = correlationSource
            self.formatVersion = formatVersion
            self.dispatchKind = dispatchKind
            self.pathSource = pathSource
        }
    }

    weak var environment: MissionRunEnvironment?

    private var inFlightAssignmentIDs: Set<UUID> = []

    /// Why segment dispatch was not chosen (for MRE fallback logs when bindings exist).
    func segmentSkipReason(
        primaryAssignment: MissionRunAssignment,
        task: RoutePath,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        bindings: [MissionRunBrainBinding]
    ) -> String? {
        guard !bindings.isEmpty else { return nil }
        if task.pattern == .convoy {
            return "Convoy task pattern uses the squad assembly pipeline, not brain segments."
        }
        guard let tokenKey = primaryAssignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey),
              let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
        else {
            return "No fleet stream is bound to this roster slot."
        }
        if fleetLink.isLiveDriveControlSessionActive(forVehicleID: vehicleID) {
            return "Live Drive holds the control session for this vehicle."
        }
        let fleetType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType
            ?? mission.rosterDevices.first(where: { $0.id == primaryAssignment.rosterDeviceId })?.vehicleClass
            ?? .unknown
        switch GuardianBrainDispatchResolver.resolve(fleetVehicleType: fleetType, bindings: bindings) {
        case .success(.segmentPath(let binding, _)):
            guard let pack = try? GuardianBrainRunUtilities.loadPack(for: binding),
                  !pack.skill.segments.isEmpty
            else {
                return "Brain pack on disk has no segments."
            }
            return nil
        case .success(.plannerPath(let binding, _)):
            guard let pack = try? GuardianBrainRunUtilities.loadPack(for: binding),
                  pack.plannerHints != nil,
                  !Self.synthesizedPlannerSegments(pack: pack).isEmpty
            else {
                return "Brain pack planner hints could not be turned into open-loop segments."
            }
            return nil
        case .failure(.noBinding):
            return "No brain binding matches this vehicle class."
        case .failure(.packNotFound):
            return "Imported brain pack file is missing from the catalogue."
        case .failure(.emptyExecutableContent):
            return "Brain pack has no segments or planner hints."
        }
    }

    /// When a bound segment brain exists and mission upload is not already required (non-convoy), prefer OFFBOARD segments.
    func segmentLaunchPlan(
        primaryAssignment: MissionRunAssignment,
        task: RoutePath,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        bindings: [MissionRunBrainBinding],
        skipWhenConvoyFormation: Bool
    ) -> SegmentLaunchPlan? {
        if skipWhenConvoyFormation, task.pattern == .convoy { return nil }
        guard let tokenKey = primaryAssignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey),
              let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
        else { return nil }
        if fleetLink.isLiveDriveControlSessionActive(forVehicleID: vehicleID) { return nil }
        let fleetType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType
            ?? mission.rosterDevices.first(where: { $0.id == primaryAssignment.rosterDeviceId })?.vehicleClass
            ?? .unknown
        guard case .success(.segmentPath(let binding, let formatVersion)) = GuardianBrainDispatchResolver.resolve(
            fleetVehicleType: fleetType,
            bindings: bindings
        ) else { return nil }
        guard let pack = try? GuardianBrainRunUtilities.loadPack(for: binding),
              !pack.skill.segments.isEmpty
        else { return nil }
        return SegmentLaunchPlan(
            assignmentID: primaryAssignment.id,
            slotName: primaryAssignment.slotName,
            vehicleID: vehicleID,
            taskID: task.id,
            taskLabel: task.name,
            binding: binding,
            segments: pack.skill.segments,
            correlationSource: GuardianBrainDispatchResolver.correlationSource(for: binding),
            formatVersion: formatVersion,
            dispatchKind: .segmentPack
        )
    }

    /// Planner-only packs: open-loop segments synthesized from pack layout + path (Nav2 plan when available at launch).
    func plannerLaunchPlan(
        primaryAssignment: MissionRunAssignment,
        task: RoutePath,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        bindings: [MissionRunBrainBinding],
        skipWhenConvoyFormation: Bool
    ) -> SegmentLaunchPlan? {
        if skipWhenConvoyFormation, task.pattern == .convoy { return nil }
        guard let tokenKey = primaryAssignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey),
              let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
        else { return nil }
        if fleetLink.isLiveDriveControlSessionActive(forVehicleID: vehicleID) { return nil }
        let fleetType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType
            ?? mission.rosterDevices.first(where: { $0.id == primaryAssignment.rosterDeviceId })?.vehicleClass
            ?? .unknown
        guard case .success(.plannerPath(let binding, let formatVersion)) = GuardianBrainDispatchResolver.resolve(
            fleetVehicleType: fleetType,
            bindings: bindings
        ) else { return nil }
        guard let pack = try? GuardianBrainRunUtilities.loadPack(for: binding),
              pack.plannerHints != nil
        else { return nil }
        let segments = Self.synthesizedPlannerSegments(pack: pack)
        guard !segments.isEmpty else { return nil }
        return SegmentLaunchPlan(
            assignmentID: primaryAssignment.id,
            slotName: primaryAssignment.slotName,
            vehicleID: vehicleID,
            taskID: task.id,
            taskLabel: task.name,
            binding: binding,
            segments: segments,
            correlationSource: GuardianBrainDispatchResolver.correlationSource(for: binding),
            formatVersion: formatVersion,
            dispatchKind: .plannerOpenLoop,
            pathSource: "geodesic_open_loop"
        )
    }

    /// Segment pack when present; otherwise planner-synthesized open-loop path.
    func brainLaunchPlan(
        primaryAssignment: MissionRunAssignment,
        task: RoutePath,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        bindings: [MissionRunBrainBinding],
        skipWhenConvoyFormation: Bool
    ) -> SegmentLaunchPlan? {
        segmentLaunchPlan(
            primaryAssignment: primaryAssignment,
            task: task,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            bindings: bindings,
            skipWhenConvoyFormation: skipWhenConvoyFormation
        )
        ?? plannerLaunchPlan(
            primaryAssignment: primaryAssignment,
            task: task,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            bindings: bindings,
            skipWhenConvoyFormation: skipWhenConvoyFormation
        )
    }

    func launchSegmentPlans(_ plans: [SegmentLaunchPlan], fleetLink: FleetLinkService) {
        for plan in plans {
            launchSegmentPlan(plan, fleetLink: fleetLink)
        }
    }

    func launchSegmentPlan(_ plan: SegmentLaunchPlan, fleetLink: FleetLinkService) {
        guard let environment else { return }
        guard inFlightAssignmentIDs.insert(plan.assignmentID).inserted else { return }
        var startParams: [String: String] = [
            "slot": plan.slotName,
            "slotID": plan.assignmentID.uuidString,
            "vehicleID": plan.vehicleID,
            "brain": plan.binding.displayName,
            "brainVersion": plan.binding.brainVersion.semverString,
            "formatVersion": String(plan.formatVersion),
            "source": plan.correlationSource,
            "segmentCount": String(plan.segments.count),
            "pathKind": plan.dispatchKind.rawValue,
        ]
        if let pathSource = plan.pathSource {
            startParams["pathSource"] = pathSource
        }
        environment.appendEvent(
            MissionRunEvent(
                level: .info,
                taskID: plan.taskID,
                taskLabel: plan.taskLabel,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.brainDispatchSegmentStarted,
                templateParams: startParams
            )
        )
        Task { @MainActor [weak self] in
            defer { self?.inFlightAssignmentIDs.remove(plan.assignmentID) }
            guard let self, let environment = self.environment else { return }
            guard await fleetLink.startTrainingControlStream(vehicleID: plan.vehicleID) else {
                self.handleSegmentFailure(
                    plan: plan,
                    detail: "Training control stream did not start.",
                    fleetLink: fleetLink
                )
                return
            }
            var segments = plan.segments
            if plan.dispatchKind == .plannerOpenLoop,
               let pack = try? GuardianBrainRunUtilities.loadPack(for: plan.binding) {
                let layout = pack.skill.layout
                let pathResponse = await fleetLink.requestTrainingNav2PlanPath(
                    vehicleID: plan.vehicleID,
                    layout: layout
                )
                let path: [RouteCoordinate]
                let pathSource: String
                if pathResponse.points.count >= 2 {
                    path = pathResponse.points
                    pathSource = pathResponse.source.rawValue
                } else {
                    path = TrainingGeodesicPathPlanner.plan(start: layout.start, goal: layout.goal)
                    pathSource = TrainingNav2PlanPathResponse.Source.geodesicFallback.rawValue
                }
                let maxSpeed = pack.plannerHints?.maxSpeedMS
                    ?? GuardianBrainPackBuilder.inferredMaxSpeedMS(from: pack.skill.segments)
                let synthesized = GuardianBrainPlannerSegmentSynthesis.segments(
                    path: path,
                    maxSpeedMS: maxSpeed,
                    initialHeadingDeg: layout.start.headingDeg
                )
                if !synthesized.isEmpty {
                    segments = synthesized
                }
                environment.appendEvent(
                    MissionRunEvent(
                        level: .info,
                        taskID: plan.taskID,
                        taskLabel: plan.taskLabel,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.brainDispatchPlannerPathResolved,
                        templateParams: [
                            "slot": plan.slotName,
                            "slotID": plan.assignmentID.uuidString,
                            "pathSource": pathSource,
                            "segmentCount": String(segments.count),
                            "source": plan.correlationSource,
                        ]
                    )
                )
            }
            do {
                for segment in segments {
                    try Task.checkCancellation()
                    try await fleetLink.executeTrainingSegment(vehicleID: plan.vehicleID, segment: segment)
                }
                await fleetLink.stopTrainingControlStream(vehicleID: plan.vehicleID)
                environment.appendEvent(
                    MissionRunEvent(
                        level: .info,
                        taskID: plan.taskID,
                        taskLabel: plan.taskLabel,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.brainDispatchSegmentSucceeded,
                        templateParams: [
                            "slot": plan.slotName,
                            "slotID": plan.assignmentID.uuidString,
                            "vehicleID": plan.vehicleID,
                            "source": plan.correlationSource,
                        ]
                    )
                )
                finishBrainSegmentSuccess(plan: plan)
            } catch {
                await fleetLink.stopTrainingControlStream(vehicleID: plan.vehicleID)
                self.handleSegmentFailure(
                    plan: plan,
                    detail: error.localizedDescription,
                    fleetLink: fleetLink
                )
            }
        }
    }

    /// Posts ``MissionRunExecutionEvent/missionCycleFinished`` after a brain segment chain succeeds.
    func finishBrainSegmentSuccess(plan: SegmentLaunchPlan) {
        guard let environment,
              let ctx = environment.effectiveExecutionContextForDispatch()
        else { return }
        _ = environment.systems.executor.handleEvent(
            .missionCycleFinished(vehicleID: plan.vehicleID),
            context: ctx
        )
    }

    private func handleSegmentFailure(
        plan: SegmentLaunchPlan,
        detail: String,
        fleetLink: FleetLinkService
    ) {
        guard let environment else { return }
        environment.appendEvent(
            MissionRunEvent(
                level: .error,
                taskID: plan.taskID,
                taskLabel: plan.taskLabel,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.brainDispatchSegmentFailed,
                templateParams: [
                    "slot": plan.slotName,
                    "slotID": plan.assignmentID.uuidString,
                    "vehicleID": plan.vehicleID,
                    "source": plan.correlationSource,
                    "detail": detail,
                ]
            )
        )
        MissionRunBrainOperatorPromptBridge.presentExecutionFailure(
            missionRunID: environment.id,
            plan: plan,
            detail: detail
        )
    }

    private static func synthesizedPlannerSegments(pack: GuardianBrainPack) -> [TrainingControlSegment] {
        guard pack.plannerHints != nil else { return [] }
        let layout = pack.skill.layout
        let maxSpeed = pack.plannerHints?.maxSpeedMS
            ?? GuardianBrainPackBuilder.inferredMaxSpeedMS(from: pack.skill.segments)
        let path = TrainingGeodesicPathPlanner.plan(start: layout.start, goal: layout.goal)
        return GuardianBrainPlannerSegmentSynthesis.segments(
            path: path,
            maxSpeedMS: maxSpeed,
            initialHeadingDeg: layout.start.headingDeg
        )
    }
}
