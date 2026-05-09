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
        guard let token = FleetMissionVehicleToken(storageKey: issued.vehicleTokenKey) else {
            return MissionRunEvent(
                level: .error,
                taskID: ctx.0,
                taskLabel: ctx.1,
                speaker: .paladin,
                message: "Invalid vehicle token for slot \(issued.slotName); command dropped.",
                templateKey: MissionRunLogTemplateKey.commandInvalidToken,
                templateParams: ["slot": issued.slotName]
            )
        }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            return MissionRunEvent(
                level: .error,
                taskID: ctx.0,
                taskLabel: ctx.1,
                speaker: .paladin,
                message: "Vehicle unavailable for slot \(issued.slotName); command dropped.",
                templateKey: MissionRunLogTemplateKey.commandVehicleUnavailable,
                templateParams: ["slot": issued.slotName]
            )
        }
        let summary = shortCommandSummary(issued.command)
        let commandID = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: issued.command,
            source: issued.fleetDispatchSourceLabel,
            category: issued.category,
            onPaladinCommandOutcome: { [weak self] outcome in
                guard let self, let environment = self.environment else { return }
                switch outcome {
                case .succeeded:
                    let ackCtx = environment.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID)
                    environment.systems.logging.appendLogEvent(
                        level: .info,
                        taskID: ackCtx.0,
                        taskLabel: ackCtx.1,
                        speaker: .paladin,
                        message: "Fleet acknowledged: \(summary) on \(vehicleID).",
                        templateKey: MissionRunLogTemplateKey.fleetAckSuccess,
                        templateParams: [
                            "summary": summary,
                            "vehicleID": vehicleID,
                            "slot": issued.slotName,
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
                        speaker: .paladin,
                        message: "Fleet command failed: \(summary) - \(reason)",
                        templateKey: MissionRunLogTemplateKey.fleetAckFailed,
                        templateParams: [
                            "summary": summary,
                            "reason": reason,
                            "vehicleID": vehicleID,
                            "slot": issued.slotName,
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
                speaker: .paladin,
                message: "Command dispatched to \(vehicleID).",
                templateKey: MissionRunLogTemplateKey.commandDispatched,
                templateParams: [
                    "vehicleID": vehicleID,
                    "slot": issued.slotName,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        }
        return MissionRunEvent(
            level: .error,
            taskID: ctx.0,
            taskLabel: ctx.1,
            speaker: .paladin,
            message: "Command not sent to \(vehicleID) (no session, blocked by authority gate, or dispatch error).",
            templateKey: MissionRunLogTemplateKey.commandNotSent,
            templateParams: [
                "vehicleID": vehicleID,
                "slot": issued.slotName,
            ]
        )
    }

    private func shortCommandSummary(_ command: FleetVehicleCommand) -> String {
        switch command {
        case .arm: return "arm"
        case .disarm: return "disarm"
        case .holdPosition: return "hold"
        case .gotoCoordinate: return "goto"
        case .uploadAndStartMission(let items): return "upload+start mission (\(items.count) item(s))"
        case .returnToLaunch: return "return to launch"
        case .land: return "land"
        case .idle: return "idle (manual)"
        case .manualControl(let manual): return "manual \(manual.intent.rawValue)"
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
}

