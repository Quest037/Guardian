import Foundation

@MainActor
final class MissionRunCommandSubsystem {
    weak var environment: MissionRunEnvironment?

    func dispatchCommand(
        _ issued: MissionRunIssuedCommand,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MissionRunEvent {
        let ctx = environment?.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID) ?? (nil, nil)
        let slotIDString = issued.assignmentID.uuidString
        guard let token = FleetMissionVehicleToken(storageKey: issued.vehicleTokenKey) else {
            return MissionRunEvent(
                level: .error,
                taskID: ctx.0,
                taskLabel: ctx.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.commandInvalidToken,
                templateParams: ["slot": issued.slotName, "slotID": slotIDString]
            )
        }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            return MissionRunEvent(
                level: .error,
                taskID: ctx.0,
                taskLabel: ctx.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.commandVehicleUnavailable,
                templateParams: ["slot": issued.slotName, "slotID": slotIDString]
            )
        }
        let summary = shortDispatchSummary(issued.dispatch)
        switch issued.dispatch {
        case .vehicleCommand(let command):
            return dispatchVehicleCommand(
                issued: issued,
                command: command,
                summary: summary,
                vehicleID: vehicleID,
                slotIDString: slotIDString,
                ctx: ctx,
                fleetLink: fleetLink
            )
        case .catalogue(let name, let parameters):
            return dispatchCatalogueInvoke(
                issued: issued,
                name: name,
                parameters: parameters,
                summary: summary,
                vehicleID: vehicleID,
                slotIDString: slotIDString,
                ctx: ctx,
                fleetLink: fleetLink
            )
        case .recipe(let name, let parameters):
            return dispatchRecipeRun(
                issued: issued,
                name: name,
                parameters: parameters,
                summary: summary,
                vehicleID: vehicleID,
                slotIDString: slotIDString,
                ctx: ctx,
                fleetLink: fleetLink
            )
        }
    }

    private func dispatchVehicleCommand(
        issued: MissionRunIssuedCommand,
        command: FleetVehicleCommand,
        summary: String,
        vehicleID: String,
        slotIDString: String,
        ctx: (UUID?, String?),
        fleetLink: FleetLinkService
    ) -> MissionRunEvent {
        let commandID = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: command,
            source: issued.fleetDispatchSourceLabel,
            category: issued.category,
            onCommandOutcome: { [weak self] outcome in
                guard let self, let environment = self.environment else { return }
                switch outcome {
                case .succeeded, .succeededWithPayload:
                    let ackCtx = environment.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID)
                    environment.systems.logging.appendLogEvent(
                        level: .info,
                        taskID: ackCtx.0,
                        taskLabel: ackCtx.1,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.fleetAckSuccess,
                        templateParams: [
                            "summary": summary,
                            "vehicleID": vehicleID,
                            "slot": issued.slotName,
                            "slotID": slotIDString,
                            "issuer": issued.issuer.rawValue,
                            "issuerKey": issued.issuerKey,
                        ]
                    )
                case .failed(let reason):
                    let ackCtx = environment.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID)
                    environment.systems.logging.appendLogEvent(
                        level: .error,
                        taskID: ackCtx.0,
                        taskLabel: ackCtx.1,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.fleetAckFailed,
                        templateParams: [
                            "summary": summary,
                            "reason": reason,
                            "vehicleID": vehicleID,
                            "slot": issued.slotName,
                            "slotID": slotIDString,
                            "issuer": issued.issuer.rawValue,
                            "issuerKey": issued.issuerKey,
                        ]
                    )
                }
            }
        )
        if commandID != nil {
            return MissionRunEvent(
                level: .info,
                taskID: ctx.0,
                taskLabel: ctx.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.commandDispatched,
                templateParams: [
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "slotID": slotIDString,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        }
        return MissionRunEvent(
            level: .error,
            taskID: ctx.0,
            taskLabel: ctx.1,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.commandNotSent,
            templateParams: [
                "vehicleID": vehicleID,
                "slot": issued.slotName,
                "slotID": slotIDString,
            ]
        )
    }

    private func dispatchCatalogueInvoke(
        issued: MissionRunIssuedCommand,
        name: FleetCommandName,
        parameters: FleetCommandParameters,
        summary: String,
        vehicleID: String,
        slotIDString: String,
        ctx: (UUID?, String?),
        fleetLink: FleetLinkService
    ) -> MissionRunEvent {
        let source = issued.fleetDispatchSourceLabel
        Task { @MainActor [weak self] in
            guard let self, self.environment != nil else { return }
            let response = await FleetCommandsCatalogue.shared.invoke(
                name,
                parameters: parameters,
                vehicleID: vehicleID,
                source: source,
                fleetLink: fleetLink
            )
            self.appendCatalogueInvokeAckLogs(
                issued: issued,
                catalogueCommandName: name,
                response: response,
                vehicleID: vehicleID,
                slotIDString: slotIDString,
                summary: summary
            )
        }
        return MissionRunEvent(
            level: .info,
            taskID: ctx.0,
            taskLabel: ctx.1,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.commandDispatched,
            templateParams: [
                "vehicleID": vehicleID,
                "slot": issued.slotName,
                "slotID": slotIDString,
                "issuer": issued.issuer.rawValue,
                "issuerKey": issued.issuerKey,
            ]
        )
    }

    /// Appends ``MissionRunLogTemplateKey/commandDispatched``, **awaits** catalogue completion, then appends the same
    /// ack success / failure logs as the fire-and-forget ``dispatchCatalogueInvoke`` path. Used so abort batches can
    /// finish ``FleetCommandName/fleetVehicleDoMissionClear`` before a follow-on recipe (e.g. move+park) starts.
    /// - Returns: whether the catalogue invoke reported success (including dispatch prerequisites).
    @discardableResult
    func awaitCatalogueMissionClearDispatchAndAckLogs(
        issued: MissionRunIssuedCommand,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async -> Bool {
        guard case .catalogue(let name, _) = issued.dispatch, name == .fleetVehicleDoMissionClear else {
            return false
        }
        return await awaitCatalogueDispatchAndAckLogs(issued: issued, fleetLink: fleetLink, sitl: sitl)
    }

    /// Awaits any **catalogue** dispatch (not only mission clear) with the same logging shape as ``dispatchCatalogueInvoke``.
    /// - Returns: whether the catalogue invoke reported success (including dispatch prerequisites).
    @discardableResult
    func awaitCatalogueDispatchAndAckLogs(
        issued: MissionRunIssuedCommand,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async -> Bool {
        guard case .catalogue(let name, let parameters) = issued.dispatch else {
            return false
        }
        let ctx = environment?.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID) ?? (nil, nil)
        let slotIDString = issued.assignmentID.uuidString
        guard let environment else { return false }
        guard let token = FleetMissionVehicleToken(storageKey: issued.vehicleTokenKey) else {
            environment.appendEvent(
                MissionRunEvent(
                    level: .error,
                    taskID: ctx.0,
                    taskLabel: ctx.1,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.commandInvalidToken,
                    templateParams: ["slot": issued.slotName, "slotID": slotIDString]
                )
            )
            return false
        }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            environment.appendEvent(
                MissionRunEvent(
                    level: .error,
                    taskID: ctx.0,
                    taskLabel: ctx.1,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.commandVehicleUnavailable,
                    templateParams: ["slot": issued.slotName, "slotID": slotIDString]
                )
            )
            return false
        }
        let summary = shortDispatchSummary(issued.dispatch)
        environment.appendEvent(
            MissionRunEvent(
                level: .info,
                taskID: ctx.0,
                taskLabel: ctx.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.commandDispatched,
                templateParams: [
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "slotID": slotIDString,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        )
        let response = await FleetCommandsCatalogue.shared.invoke(
            name,
            parameters: parameters,
            vehicleID: vehicleID,
            source: issued.fleetDispatchSourceLabel,
            fleetLink: fleetLink
        )
        appendCatalogueInvokeAckLogs(
            issued: issued,
            catalogueCommandName: name,
            response: response,
            vehicleID: vehicleID,
            slotIDString: slotIDString,
            summary: summary
        )
        return response.isSuccess
    }

    private func appendCatalogueInvokeAckLogs(
        issued: MissionRunIssuedCommand,
        catalogueCommandName: FleetCommandName,
        response: FleetCommandResponse,
        vehicleID: String,
        slotIDString: String,
        summary: String
    ) {
        guard let environment else { return }
        let ackCtx = environment.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID)
        if response.isSuccess {
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: ackCtx.0,
                taskLabel: ackCtx.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.fleetAckSuccess,
                templateParams: [
                    "summary": summary,
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "slotID": slotIDString,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        } else {
            let geofenceCatalogueFailure =
                catalogueCommandName == .fleetVehicleDoGeofenceUpload || catalogueCommandName == .fleetVehicleDoGeofenceClear
            let ackKey = geofenceCatalogueFailure
                ? MissionRunLogTemplateKey.missionRunGeofenceFleetAckFailed
                : MissionRunLogTemplateKey.fleetAckFailed
            environment.systems.logging.appendLogEvent(
                level: .error,
                taskID: ackCtx.0,
                taskLabel: ackCtx.1,
                speaker: .missionControl,
                templateKey: ackKey,
                templateParams: [
                    "summary": summary,
                    "reason": Self.catalogueOutcomeReason(response),
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "slotID": slotIDString,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        }
    }

    /// Same recipe execution + ack logs as ``dispatchRecipeRun``'s background `Task`, but **awaited** so abort
    /// batches can finish move+park (etc.) before ``MissionRunExecutionSubsystem/completeRun`` flips the run
    /// into ``MissionRunSessionPhase/aborting`` (which would otherwise strand the recipe and confuse telemetry).
    /// - Returns: whether the recipe outcome is success (including dispatch prerequisites).
    @discardableResult
    func awaitRecipeDispatchAppendingDispatchedThenAckLogs(
        issued: MissionRunIssuedCommand,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async -> Bool {
        guard case .recipe(let name, let parameters) = issued.dispatch else { return false }
        let ctx = environment?.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID) ?? (nil, nil)
        let slotIDString = issued.assignmentID.uuidString
        guard let environment else { return false }
        guard let token = FleetMissionVehicleToken(storageKey: issued.vehicleTokenKey) else {
            environment.appendEvent(
                MissionRunEvent(
                    level: .error,
                    taskID: ctx.0,
                    taskLabel: ctx.1,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.commandInvalidToken,
                    templateParams: ["slot": issued.slotName, "slotID": slotIDString]
                )
            )
            return false
        }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            environment.appendEvent(
                MissionRunEvent(
                    level: .error,
                    taskID: ctx.0,
                    taskLabel: ctx.1,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.commandVehicleUnavailable,
                    templateParams: ["slot": issued.slotName, "slotID": slotIDString]
                )
            )
            return false
        }
        let summary = shortDispatchSummary(issued.dispatch)
        environment.appendEvent(
            MissionRunEvent(
                level: .info,
                taskID: ctx.0,
                taskLabel: ctx.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.commandDispatched,
                templateParams: [
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "slotID": slotIDString,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        )
        let outcome = await runRegisteredRecipeAwaitingOutcome(
            issued: issued,
            name: name,
            parameters: parameters,
            vehicleID: vehicleID,
            fleetLink: fleetLink
        )
        appendRecipeRunAckLogs(
            issued: issued,
            outcome: outcome,
            summary: summary,
            vehicleID: vehicleID,
            slotIDString: slotIDString
        )
        return outcome.isSuccess
    }

    private func ensureRecipeDescriptorsLoadedIfNeeded(name: FleetRecipeName) {
        if name == FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName
            || name == FleetMissionRecipeRegistrations.doMissionUploadStartItemRecipeName,
           FleetRecipesCatalogue.shared.descriptor(for: name) == nil {
            FleetRecipesCatalogueBootstrap.ensureRegistered()
            FleetMissionRecipeRegistrations.registerAll()
        }
        if name == FleetMissionRecipeRegistrations.doReturnHomeRecipeName,
           FleetRecipesCatalogue.shared.descriptor(for: name) == nil {
            FleetRecipesCatalogueBootstrap.ensureRegistered()
            FleetMissionRecipeRegistrations.registerAll()
        }
        if name == FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
           FleetRecipesCatalogue.shared.descriptor(for: name) == nil {
            FleetRecipesCatalogueBootstrap.ensureRegistered()
            FleetMovePointParkRecipeRegistrations.registerAll()
        }
        if name == FleetMissionRecipeRegistrations.vehicleDoParkRecipeName,
           FleetRecipesCatalogue.shared.descriptor(for: name) == nil {
            FleetRecipesCatalogueBootstrap.ensureRegistered()
            FleetMissionRecipeRegistrations.registerAll()
        }
    }

    private func missionRunRecipeEscalationHandler(
        issued: MissionRunIssuedCommand,
        vehicleID: String
    ) -> FleetRecipeEscalationHandler {
        let missionTaskID = environment?.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID).0
        let assignmentID = issued.assignmentID
        let slotLabel = issued.slotName
        return { [weak self] escalation in
            guard let self, let runID = self.environment?.id else {
                let wizard = FleetRecipeRunner.shared.vehicleInspectorWizardEscalationHandler(for: vehicleID)
                return await wizard(escalation)
            }
            return await MissionRunRecipeOperatorPromptBridge.shared.awaitMissionRecipeEscalationAnswer(
                missionRunID: runID,
                assignmentID: assignmentID,
                missionTaskID: missionTaskID,
                slotLabel: slotLabel,
                run: self.environment,
                escalation: escalation
            )
        }
    }

    private func runRegisteredRecipeAwaitingOutcome(
        issued: MissionRunIssuedCommand,
        name: FleetRecipeName,
        parameters: FleetRecipeParameters,
        vehicleID: String,
        fleetLink: FleetLinkService
    ) async -> FleetRecipeOutcome {
        ensureRecipeDescriptorsLoadedIfNeeded(name: name)
        let source = issued.fleetDispatchSourceLabel
        let escalationHandler = missionRunRecipeEscalationHandler(issued: issued, vehicleID: vehicleID)
        return await FleetRecipeRunner.shared.run(
            recipe: name,
            parameters: parameters,
            vehicleID: vehicleID,
            source: source,
            fleetLink: fleetLink,
            allowDuringLiveMission: true,
            escalationHandler: escalationHandler
        )
    }

    private func appendRecipeRunAckLogs(
        issued: MissionRunIssuedCommand,
        outcome: FleetRecipeOutcome,
        summary: String,
        vehicleID: String,
        slotIDString: String
    ) {
        guard let environment else { return }
        let ackCtx = environment.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID)
        if outcome.isSuccess {
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: ackCtx.0,
                taskLabel: ackCtx.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.fleetAckSuccess,
                templateParams: [
                    "summary": summary,
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "slotID": slotIDString,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        } else {
            let ackKey: String
            if case .recipe(let recipeName, _) = issued.dispatch,
               outcome.isMissionRunGeofenceFleetFailureForDistinctExecutorLogs(recipeName: recipeName) {
                ackKey = MissionRunLogTemplateKey.missionRunGeofenceFleetAckFailed
            } else {
                ackKey = MissionRunLogTemplateKey.fleetAckFailed
            }
            environment.systems.logging.appendLogEvent(
                level: .error,
                taskID: ackCtx.0,
                taskLabel: ackCtx.1,
                speaker: .missionControl,
                templateKey: ackKey,
                templateParams: [
                    "summary": summary,
                    "reason": outcome.loggable,
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "slotID": slotIDString,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        }
    }

    private func dispatchRecipeRun(
        issued: MissionRunIssuedCommand,
        name: FleetRecipeName,
        parameters: FleetRecipeParameters,
        summary: String,
        vehicleID: String,
        slotIDString: String,
        ctx: (UUID?, String?),
        fleetLink: FleetLinkService
    ) -> MissionRunEvent {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.runRegisteredRecipeAwaitingOutcome(
                issued: issued,
                name: name,
                parameters: parameters,
                vehicleID: vehicleID,
                fleetLink: fleetLink
            )
            self.appendRecipeRunAckLogs(
                issued: issued,
                outcome: outcome,
                summary: summary,
                vehicleID: vehicleID,
                slotIDString: slotIDString
            )
        }
        return MissionRunEvent(
            level: .info,
            taskID: ctx.0,
            taskLabel: ctx.1,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.commandDispatched,
            templateParams: [
                "vehicleID": vehicleID,
                "slot": issued.slotName,
                "slotID": slotIDString,
                "issuer": issued.issuer.rawValue,
                "issuerKey": issued.issuerKey,
            ]
        )
    }

    private static func catalogueOutcomeReason(_ response: FleetCommandResponse) -> String {
        let tail = response.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch response.outcome {
        case .succeeded:
            return tail ?? "succeeded"
        case .error(let kind):
            if let tail, !tail.isEmpty { return "\(String(describing: kind)): \(tail)" }
            return String(describing: kind)
        case .cancelled:
            return tail ?? "cancelled"
        case .timeout:
            return tail ?? "timeout"
        }
    }

    private func shortDispatchSummary(_ dispatch: MissionRunFleetDispatch) -> String {
        switch dispatch {
        case .vehicleCommand(let command):
            return command.missionRunDispatchShortLabel
        case .catalogue(let name, let parameters):
            if name == .fleetVehicleDoMissionUploadStart,
               let json = parameters.string(named: "missionItemsJSON"),
               let items = try? FleetVehicleCommandMissionItemPayload.decodeMissionItems(fromJSON: json) {
                return "catalogue upload+arm+start (\(items.count) item(s))"
            }
            return "catalogue \(name.rawValue)"
        case .recipe(let name, let parameters):
            if name == FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
               let json = parameters.string(named: "missionItemsJSON"),
               let items = try? FleetVehicleCommandMissionItemPayload.decodeMissionItems(fromJSON: json) {
                return "recipe upload+arm+start (\(items.count) item(s))"
            }
            if name == FleetMissionRecipeRegistrations.doMissionUploadStartItemRecipeName,
               let json = parameters.string(named: "missionItemsJSON"),
               let idx = parameters.integer(named: "missionStartItemIndex"),
               let items = try? FleetVehicleCommandMissionItemPayload.decodeMissionItems(fromJSON: json) {
                return "recipe upload+jump(\(idx))+arm+start (\(items.count) item(s))"
            }
            if name == FleetMissionRecipeRegistrations.doReturnHomeRecipeName {
                return "recipe return home (RTL)"
            }
            if name == FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
               let line = parameters.string(named: "procedureLogSummary") {
                return "recipe move+park — \(line)"
            }
            if name == FleetMissionRecipeRegistrations.vehicleDoParkRecipeName {
                return "recipe vehicle park (run cleanup)"
            }
            return "recipe \(name.rawValue)"
        }
    }
}

// MARK: - Log template keys (fleet commands)

extension MissionRunLogTemplateKey {
    static let commandInvalidToken = "missioncontrol.mre.command.invalid_token"
    static let commandVehicleUnavailable = "missioncontrol.mre.command.vehicle_unavailable"
    static let commandDispatched = "missioncontrol.mre.command.dispatched"
    static let commandNotSent = "missioncontrol.mre.command.not_sent"
    static let fleetAckSuccess = "missioncontrol.mre.fleet.ack_success"
    static let fleetAckFailed = "missioncontrol.mre.fleet.ack_failed"
    /// Same params as ``fleetAckFailed`` — geofence upload/clear or composite mission upload failing on the geofence stack child.
    static let missionRunGeofenceFleetAckFailed = "missioncontrol.mre.fleet.geofence_ack_failed"
}
