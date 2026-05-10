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
        let summary = shortCommandSummary(issued.command)
        let commandID = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: issued.command,
            source: issued.fleetDispatchSourceLabel,
            category: issued.category,
            onCommandOutcome: { [weak self] outcome in
                guard let self, let environment = self.environment else { return }
                switch outcome {
                case .succeeded:
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

    private func shortCommandSummary(_ command: FleetVehicleCommand) -> String {
        switch command {
        case .arm: return "arm"
        case .disarm: return "disarm"
        case .holdPosition: return "hold"
        case .gotoCoordinate: return "goto"
        case .uploadAndStartMission(let items): return "upload+start mission (\(items.count) item(s))"
        case .uploadMission(let items): return "upload mission (\(items.count) item(s))"
        case .returnToLaunch: return "return to launch"
        case .land: return "land"
        case .idle: return "idle (manual)"
        case .manualControl(let manual): return "manual \(manual.intent.rawValue)"
        case .calibrateMavsdk(let kind): return "calibrate \(kind.rawValue)"
        case .mavlinkCommandLong(let request): return "mavlink command \(request.command)"
        case .cancelCalibration: return "cancel calibration"
        case .setParameterFloat(let name, _): return "param \(name) (float)"
        case .setParameterInt(let name, _): return "param \(name) (int)"
        case .setMode(let mode): return "set mode \(mode.rawValue)"
        case .rebootAutopilot: return "reboot autopilot"
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

