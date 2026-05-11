import XCTest
@testable import GuardianHQ

/// End-to-end SITL smoke coverage for the Layer 0 command catalogue and selected Layer 1 recipes
/// (Pattern-A calibrations, arm probe, calibration-required composite, cancelRecipe cleanup).
///
/// These tests deliberately do **not** run during normal `swift test`: booting both
/// ArduPilot and PX4 SITL is slow, stateful, and dependent on local simulator bundles.
/// Use `scripts/run_sitl_smoke_tests.sh`, which sets `GUARDIAN_RUN_SITL_SMOKE=1` and
/// filters to this suite.
@MainActor
final class GuardianHQSitlSmokeTests: XCTestCase {

    private enum SmokeStack: String, CaseIterable {
        case ardupilot
        case px4

        var platform: SimulationPlatform {
            switch self {
            case .ardupilot: return .ardupilot
            case .px4: return .px4
            }
        }

        var displayName: String {
            switch self {
            case .ardupilot: return "ArduPilot"
            case .px4: return "PX4"
            }
        }
    }

    private struct SmokeVehicle {
        let stack: SmokeStack
        let vehicleID: String
        let systemID: Int
    }

    @MainActor
    private final class Harness {
        let fleetLink = FleetLinkService()
        let sitl = SitlService()

        init() {
            fleetLink.setSimulateEnabled(true)
            sitl.attachFleetLink(fleetLink)
            FleetCommandsCatalogueBootstrap.ensureRegistered()
            FleetRecipesCatalogueBootstrap.ensureRegistered()
        }

        func stop() {
            sitl.stopAll()
        }
    }

    private static let smokeEnvKey = "GUARDIAN_RUN_SITL_SMOKE"

    private static let compassDoCommand = FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass")
    private static let cancelCalibrationCommand = FleetCommandName.literal("command.fleet.vehicle.cancel.calibration")

    private var bootTimeout: TimeInterval {
        envDouble("GUARDIAN_SITL_SMOKE_BOOT_TIMEOUT", default: 180)
    }

    private var commandTimeout: TimeInterval {
        envDouble("GUARDIAN_SITL_SMOKE_COMMAND_TIMEOUT", default: 45)
    }

    private var sideEffectTimeout: TimeInterval {
        envDouble("GUARDIAN_SITL_SMOKE_SIDE_EFFECT_TIMEOUT", default: 20)
    }

    func test_fullCommandCatalogueSmokeMatrix_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await runTelemetryReadSmoke(vehicle: vehicle, harness: harness)
            try await runParamSetCalibrationSmoke(vehicle: vehicle, harness: harness)
            try await runSetModeSmoke(vehicle: vehicle, harness: harness)
            try await runArmDisarmSmoke(vehicle: vehicle, harness: harness)
            if vehicle.stack == .px4 {
                try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
                try await runPX4CalibrationPluginSmoke(vehicle: vehicle, harness: harness)
            }
            try await runNavigationCommandSmoke(vehicle: vehicle, harness: harness)
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
        }
    }

    /// Layer 1: ``FleetRecipeRunner`` + ``recipe.fleet.calibrate.compass`` against the same
    /// live SITL links as the command matrix. Uses ``assertPatternAInteractiveCalRecipeSmokeAcceptable``
    /// (shared with accelerometer and other single-step Pattern-A cals).
    func test_recipeFleetCalibrateCompass_endToEnd_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.calibrate.compass"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.compass.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )
            assertPatternAInteractiveCalRecipeSmokeAcceptable(
                outcome,
                vehicle: vehicle,
                recipe: "recipe.fleet.calibrate.compass"
            )
        }
    }

    /// Layer 1: ``recipe.fleet.calibrate.accelerometer`` — same acceptance rules as compass
    /// (single `invokeCommand` step, procedure errors / timeout / escalation-abort).
    func test_recipeFleetCalibrateAccelerometer_endToEnd_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.calibrate.accelerometer"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.accelerometer.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )
            assertPatternAInteractiveCalRecipeSmokeAcceptable(
                outcome,
                vehicle: vehicle,
                recipe: "recipe.fleet.calibrate.accelerometer"
            )
        }
    }

    func test_recipeFleetCalibrateGyro_endToEnd_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.calibrate.gyro"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.gyro.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )
            assertPatternAInteractiveCalRecipeSmokeAcceptable(
                outcome,
                vehicle: vehicle,
                recipe: "recipe.fleet.calibrate.gyro"
            )
        }
    }

    func test_recipeFleetCalibrateBaro_endToEnd_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.calibrate.baro"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.baro.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )
            assertPatternAInteractiveCalRecipeSmokeAcceptable(
                outcome,
                vehicle: vehicle,
                recipe: "recipe.fleet.calibrate.baro"
            )
        }
    }

    func test_recipeFleetCalibrateLevel_endToEnd_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.calibrate.level"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.level.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )
            assertPatternAInteractiveCalRecipeSmokeAcceptable(
                outcome,
                vehicle: vehicle,
                recipe: "recipe.fleet.calibrate.level"
            )
        }
    }

    /// Two-step arm → disarm probe (preflight migration target).
    func test_recipeFleetDiagnoseArmprobe_endToEnd_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.diagnose.armprobe"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.armprobe.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )
            assertArmprobeRecipeSmokeAcceptable(outcome, vehicle: vehicle)
        }
    }

    /// Composite recovery: nested atomic calibration recipes then ``recipe.fleet.diagnose.armprobe``.
    /// Expect **succeeded** or an authored parent failure (first failing child / probe); rejects wiring.
    func test_recipeFleetErrorsFixCalibrationRequired_endToEnd_againstArduPilotAndPX4SITL() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.errors.fix.calibrationrequired"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.calibrationrequired.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )
            assertCalibrationRequiredCompositeSmokeAcceptable(outcome, vehicle: vehicle)
        }
    }

    /// ``FleetRecipeRunner/cancel(vehicleID:)`` mid-``recipe.fleet.calibrate.compass`` must dispatch
    /// the descriptor's ``FleetRecipeDescriptor/cancelRecipe`` (``recipe.fleet.calibrate.cancel`` →
    /// ``command.fleet.vehicle.cancel.calibration``) through the real catalogue after the parent run ends.
    func test_cancelMidRecipe_runsDeclaredCancelRecipe_cancelCalibration_sitlBothStacks() async throws {
        guard Self.isSmokeEnabled else {
            throw XCTSkip("SITL smoke tests are opt-in. Run scripts/run_sitl_smoke_tests.sh.")
        }

        let harness = Harness()
        defer { harness.stop() }

        let vehicles = try await bootSharedSITLSessions(harness: harness)
        for vehicle in vehicles {
            try await ensureDisarmedIfNeeded(vehicle: vehicle, harness: harness)
            var recordedCommands: [FleetCommandName] = []

            FleetRecipeRunner.shared.commandInvokerOverride = { command, parameters, vehicleID, source, timeout, invokingPluginID in
                recordedCommands.append(command)
                if command == Self.compassDoCommand {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 25_000_000)
                        _ = FleetRecipeRunner.shared.cancel(vehicleID: vehicleID)
                    }
                }
                return await FleetCommandsCatalogue.shared.invoke(
                    command,
                    parameters: parameters,
                    vehicleID: vehicleID,
                    source: source,
                    fleetLink: harness.fleetLink,
                    timeout: timeout,
                    invokingPluginID: invokingPluginID
                )
            }
            defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }

            _ = await FleetRecipeRunner.shared.run(
                recipe: FleetRecipeName.literal("recipe.fleet.calibrate.compass"),
                vehicleID: vehicle.vehicleID,
                source: "sitlSmoke.recipe.cancelMid.\(vehicle.stack.rawValue)",
                fleetLink: harness.fleetLink
            )

            XCTAssertTrue(
                recordedCommands.contains(Self.compassDoCommand),
                "\(vehicle.stack.displayName) expected compass calibration command to dispatch; recorded=\(recordedCommands.map(\.rawValue))"
            )
            XCTAssertTrue(
                recordedCommands.contains(Self.cancelCalibrationCommand),
                "\(vehicle.stack.displayName) cancelRecipe cleanup should invoke command.fleet.vehicle.cancel.calibration; recorded=\(recordedCommands.map(\.rawValue))"
            )
        }
    }

    // MARK: - Boot

    private func bootSharedSITLSessions(harness: Harness) async throws -> [SmokeVehicle] {
        var vehicles: [SmokeVehicle] = []

        for stack in SmokeStack.allCases {
            let nextSystemID = harness.sitl.instances.count + 1
            harness.sitl.spawn(
                preset: .uavMultirotor,
                platform: stack.platform,
                defaults: .default
            )
            if let error = harness.sitl.lastError {
                XCTFail("\(stack.displayName) SITL failed to spawn: \(error)")
                continue
            }

            let vehicle = SmokeVehicle(
                stack: stack,
                vehicleID: "sysid:\(nextSystemID)",
                systemID: nextSystemID
            )
            try await waitUntil("\(stack.displayName) vehicle reaches live telemetry") {
                guard let model = harness.fleetLink.vehicleModel(forVehicleID: vehicle.vehicleID),
                      model.collections.lifecycleStatus.stage == .live,
                      let hub = harness.fleetLink.hubTelemetry(forVehicleID: vehicle.vehicleID)
                else {
                    return false
                }
                return hub.autopilotStack != .unknown
                    && hub.latitudeDeg != nil
                    && hub.longitudeDeg != nil
                    && hub.absoluteAltM != nil
            }
            vehicles.append(vehicle)
        }

        XCTAssertEqual(
            Set(vehicles.map(\.stack)),
            Set(SmokeStack.allCases),
            "The full SITL smoke run requires both ArduPilot and PX4 sessions."
        )
        return vehicles
    }

    // MARK: - Smoke groups

    private func runTelemetryReadSmoke(vehicle: SmokeVehicle, harness: Harness) async throws {
        let reads: [FleetCommandName] = [
            .fleetVehicleGetTelemetryBattery,
            .fleetVehicleGetTelemetryCompass,
            .fleetVehicleGetTelemetryGps,
            .fleetVehicleGetTelemetryEstimator,
            .fleetVehicleGetTelemetryFlight,
            .fleetVehicleGetTelemetryRc,
            .fleetVehicleGetTelemetryLink,
            .fleetVehicleGetTelemetryMode,
        ]

        for name in reads {
            let response = await invoke(
                name,
                vehicle: vehicle,
                harness: harness,
                timeout: 5
            )
            assertSuccess(response, command: name, vehicle: vehicle)
            if case .keyValues(let payload) = response.payload {
                XCTAssertFalse(
                    payload.isEmpty,
                    "\(vehicle.stack.displayName) \(name.rawValue) should return at least one telemetry field."
                )
            } else {
                XCTFail("\(vehicle.stack.displayName) \(name.rawValue) returned unexpected payload \(response.payload).")
            }
        }
    }

    private func runParamSetCalibrationSmoke(vehicle: SmokeVehicle, harness: Harness) async throws {
        let response = await invoke(
            .fleetVehicleDoCalibrateBatteryCapacity,
            parameters: FleetCommandParameters(values: ["mAh": .integer(5000)]),
            vehicle: vehicle,
            harness: harness
        )
        assertSuccess(response, command: .fleetVehicleDoCalibrateBatteryCapacity, vehicle: vehicle)
    }

    private func runSetModeSmoke(vehicle: SmokeVehicle, harness: Harness) async throws {
        let response = await invoke(
            .fleetVehicleDoMode,
            parameters: FleetCommandParameters(values: ["mode": .string("hold")]),
            vehicle: vehicle,
            harness: harness
        )
        assertSuccess(response, command: .fleetVehicleDoMode, vehicle: vehicle)
        try await waitUntil("\(vehicle.stack.displayName) reports a hold-like flight mode", timeout: sideEffectTimeout) {
            guard let mode = harness.fleetLink.hubTelemetry(forVehicleID: vehicle.vehicleID)?.flightMode.lowercased() else {
                return false
            }
            return mode.contains("hold") || mode.contains("loiter")
        }
    }

    private func runArmDisarmSmoke(vehicle: SmokeVehicle, harness: Harness) async throws {
        try await waitUntil("\(vehicle.stack.displayName) reports armable health", timeout: bootTimeout) {
            let hub = harness.fleetLink.hubTelemetry(forVehicleID: vehicle.vehicleID)
            return hub?.healthArmable == true || hub?.healthAllOk == true
        }

        var response = await invoke(.fleetVehicleDoArm, vehicle: vehicle, harness: harness)
        assertSuccess(response, command: .fleetVehicleDoArm, vehicle: vehicle)
        try await waitUntil("\(vehicle.stack.displayName) is armed", timeout: sideEffectTimeout) {
            harness.fleetLink.hubTelemetry(forVehicleID: vehicle.vehicleID)?.isArmed == true
        }

        response = await invoke(.fleetVehicleDoDisarm, vehicle: vehicle, harness: harness)
        assertSuccess(response, command: .fleetVehicleDoDisarm, vehicle: vehicle)
        try await waitUntil("\(vehicle.stack.displayName) is disarmed", timeout: sideEffectTimeout) {
            harness.fleetLink.hubTelemetry(forVehicleID: vehicle.vehicleID)?.isArmed == false
        }
    }

    private func runNavigationCommandSmoke(vehicle: SmokeVehicle, harness: Harness) async throws {
        var response = await invoke(.fleetVehicleDoArm, vehicle: vehicle, harness: harness)
        assertSuccess(response, command: .fleetVehicleDoArm, vehicle: vehicle)
        try await waitUntil("\(vehicle.stack.displayName) is armed before nav smoke", timeout: sideEffectTimeout) {
            harness.fleetLink.hubTelemetry(forVehicleID: vehicle.vehicleID)?.isArmed == true
        }

        for name in [FleetCommandName.fleetVehicleDoLoiter, .fleetVehicleDoReturnHome, .fleetVehicleDoLand] {
            response = await invoke(name, vehicle: vehicle, harness: harness)
            assertSuccess(response, command: name, vehicle: vehicle)
        }
    }

    private func runPX4CalibrationPluginSmoke(vehicle: SmokeVehicle, harness: Harness) async throws {
        let pluginCommands: [FleetCommandName] = [
            .fleetVehicleDoCalibrateGyro,
            .fleetVehicleDoCalibrateLevel,
            .fleetVehicleDoCalibrateGimbal,
        ]

        for name in pluginCommands {
            let response = await invoke(
                name,
                vehicle: vehicle,
                harness: harness,
                timeout: envDouble("GUARDIAN_SITL_SMOKE_CALIBRATION_TIMEOUT", default: 90)
            )
            assertNoTransportFailure(response, command: name, vehicle: vehicle)
        }
    }

    // MARK: - Invocation helpers

    private func invoke(
        _ name: FleetCommandName,
        parameters: FleetCommandParameters = .empty,
        vehicle: SmokeVehicle,
        harness: Harness,
        timeout: TimeInterval? = nil
    ) async -> FleetCommandResponse {
        await FleetCommandsCatalogue.shared.invoke(
            name,
            parameters: parameters,
            vehicleID: vehicle.vehicleID,
            source: "sitlSmoke.\(vehicle.stack.rawValue)",
            fleetLink: harness.fleetLink,
            timeout: timeout ?? commandTimeout
        )
    }

    private func assertSuccess(
        _ response: FleetCommandResponse,
        command: FleetCommandName,
        vehicle: SmokeVehicle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            response.isSuccess,
            "\(vehicle.stack.displayName) \(command.rawValue) expected success, got \(response.outcome) detail=\(response.detail ?? "nil")",
            file: file,
            line: line
        )
    }

    /// Calibration plugin procedures can complete or decline depending on SITL health
    /// and simulator support. For smoke purposes the hard failure is transport/catalogue
    /// breakage (`notImplemented`, no vehicle, no session, parameter validation, etc.).
    private func assertNoTransportFailure(
        _ response: FleetCommandResponse,
        command: FleetCommandName,
        vehicle: SmokeVehicle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if response.isSuccess || response.outcome == .cancelled {
            return
        }
        guard let kind = response.errorKind else {
            XCTFail(
                "\(vehicle.stack.displayName) \(command.rawValue) unexpected non-error outcome \(response.outcome) detail=\(response.detail ?? "nil")",
                file: file,
                line: line
            )
            return
        }
        let allowedProcedureOutcomes: Set<FleetCommandErrorKind> = [
            .calibrationDeclined,
            .calibrationDidNotConverge,
            .autopilotBusy,
            .modeNotSupported,
            .unknown,
        ]
        XCTAssertTrue(
            allowedProcedureOutcomes.contains(kind),
            "\(vehicle.stack.displayName) \(command.rawValue) hit transport/catalogue failure \(kind) detail=\(response.detail ?? "nil")",
            file: file,
            line: line
        )
    }

    /// Pattern-A interactive cal recipes (single ``invokeCommand`` step, success / escalate /
    /// `any`-fail). SITL may succeed, hit procedure-class errors (escalation + default abort),
    /// or **timeout** at the Layer 0 per-step cap (``FleetCommandsCatalogue/defaultDispatchTimeoutSeconds``).
    private func assertPatternAInteractiveCalRecipeSmokeAcceptable(
        _ outcome: FleetRecipeOutcome,
        vehicle: SmokeVehicle,
        recipe: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch outcome {
        case .succeeded:
            return
        case .failed(_, let lastResponse, let detail, let trace):
            if let detail, detail.contains("Operator aborted at escalation") {
                return
            }
            if let detail, detail.contains("recipe budget exceeded") {
                XCTFail(
                    "\(vehicle.stack.displayName) \(recipe) exceeded budget: \(detail)",
                    file: file,
                    line: line
                )
                return
            }
            if let lastResponse, case .timeout = lastResponse.outcome {
                // Interactive cals often exceed the catalogue's fixed per-step cap in SITL;
                // timeout still proves the runner + recipe + dispatch path stayed coherent.
                return
            }
            if let detail, detail.contains("unhandled outcome") {
                XCTFail(
                    "\(vehicle.stack.displayName) \(recipe) unhandled branch (trace: \(trace.entries.count) entries) detail=\(detail) last=\(describeLastResponse(lastResponse))",
                    file: file,
                    line: line
                )
                return
            }
            guard let lastResponse else {
                XCTFail(
                    "\(vehicle.stack.displayName) \(recipe) failed with no lastResponse: \(detail ?? "nil")",
                    file: file,
                    line: line
                )
                return
            }
            let allowedProcedureOutcomes: Set<FleetCommandErrorKind> = [
                .calibrationDeclined,
                .calibrationDidNotConverge,
                .autopilotBusy,
                .modeNotSupported,
                .unknown,
            ]
            guard let kind = lastResponse.errorKind else {
                XCTFail(
                    "\(vehicle.stack.displayName) \(recipe) unexpected non-error outcome \(lastResponse.outcome) detail=\(detail ?? "nil")",
                    file: file,
                    line: line
                )
                return
            }
            XCTAssertTrue(
                allowedProcedureOutcomes.contains(kind),
                "\(vehicle.stack.displayName) \(recipe) hit transport/catalogue failure \(kind) detail=\(lastResponse.detail ?? "nil") recipeDetail=\(detail ?? "nil")",
                file: file,
                line: line
            )
        }
    }

    /// ``recipe.fleet.diagnose.armprobe`` — arm step may refuse with explicit catalogue kinds;
    /// disarm failures still prove the two-step runner executed past arm.
    private func assertArmprobeRecipeSmokeAcceptable(
        _ outcome: FleetRecipeOutcome,
        vehicle: SmokeVehicle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch outcome {
        case .succeeded:
            return
        case .failed(let path, let lastResponse, let detail, let trace):
            if let detail, detail.contains("recipe budget exceeded") {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe exceeded budget: \(detail)",
                    file: file,
                    line: line
                )
                return
            }
            if let detail,
               detail.contains("No descriptor")
                || detail.contains("Parameter validation")
                || detail.contains("has no body")
            {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe wiring failure: \(detail)",
                    file: file,
                    line: line
                )
                return
            }
            guard let firstStep = path.first?.rawValue else {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe failed with empty path: \(detail ?? "nil") traceEntries=\(trace.entries.count)",
                    file: file,
                    line: line
                )
                return
            }
            if firstStep == "disarm" {
                return
            }
            guard firstStep == "arm" else {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe unexpected path \(path.map(\.rawValue)) detail=\(detail ?? "nil")",
                    file: file,
                    line: line
                )
                return
            }
            if let detail, detail.contains("Arm probe cancelled by operator") {
                return
            }
            if let lastResponse, case .timeout = lastResponse.outcome {
                return
            }
            if let lastResponse, case .cancelled = lastResponse.outcome {
                return
            }
            if let detail, detail.contains("Arm probe failed with an unhandled outcome") {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe arm step unhandled (trace: \(trace.entries.count)) detail=\(detail) last=\(describeLastResponse(lastResponse))",
                    file: file,
                    line: line
                )
                return
            }
            let allowedArmRefusal: Set<FleetCommandErrorKind> = [
                .armRejectedByAutopilot,
                .calibrationDeclined,
                .modeNotSupported,
                .autopilotBusy,
                .notConnected,
                .noSession,
                .authorityGated,
            ]
            guard let lastResponse else {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe arm failed with no lastResponse: \(detail ?? "nil")",
                    file: file,
                    line: line
                )
                return
            }
            guard let kind = lastResponse.errorKind else {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe arm unexpected outcome \(lastResponse.outcome) detail=\(detail ?? "nil")",
                    file: file,
                    line: line
                )
                return
            }
            XCTAssertTrue(
                allowedArmRefusal.contains(kind),
                "\(vehicle.stack.displayName) recipe.fleet.diagnose.armprobe arm hit unexpected kind \(kind) detail=\(lastResponse.detail ?? "nil") recipeDetail=\(detail ?? "nil")",
                file: file,
                line: line
            )
        }
    }

    /// ``recipe.fleet.errors.fix.calibrationrequired`` — full green path is rare in unattended SITL;
    /// accept authored parent ``fail`` details from any of the four ``invokeRecipe`` steps.
    private func assertCalibrationRequiredCompositeSmokeAcceptable(
        _ outcome: FleetRecipeOutcome,
        vehicle: SmokeVehicle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch outcome {
        case .succeeded:
            return
        case .failed(_, _, let detail, _):
            if let detail, detail.contains("recipe budget exceeded") {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.errors.fix.calibrationrequired exceeded budget: \(detail)",
                    file: file,
                    line: line
                )
                return
            }
            if let detail,
               detail.contains("No descriptor")
                || detail.contains("Parameter validation")
                || detail.contains("has no body")
            {
                XCTFail(
                    "\(vehicle.stack.displayName) recipe.fleet.errors.fix.calibrationrequired wiring failure: \(detail)",
                    file: file,
                    line: line
                )
                return
            }
            let authoredFailureMarkers = [
                "Compass calibration failed",
                "Accelerometer calibration failed",
                "Gyro calibration failed",
                "All three calibrations converged but the post-cal arm probe still failed",
            ]
            if let detail, authoredFailureMarkers.contains(where: { detail.contains($0) }) {
                return
            }
            XCTFail(
                "\(vehicle.stack.displayName) recipe.fleet.errors.fix.calibrationrequired unexpected outcome: \(outcome.loggable)",
                file: file,
                line: line
            )
        }
    }

    private func describeLastResponse(_ response: FleetCommandResponse?) -> String {
        guard let response else { return "nil" }
        switch response.outcome {
        case .succeeded: return "succeeded"
        case .error(let k): return "error.\(k.rawValue)"
        case .cancelled: return "cancelled"
        case .timeout: return "timeout"
        }
    }

    private func ensureDisarmedIfNeeded(vehicle: SmokeVehicle, harness: Harness) async throws {
        guard harness.fleetLink.hubTelemetry(forVehicleID: vehicle.vehicleID)?.isArmed == true else {
            return
        }
        let response = await invoke(.fleetVehicleDoDisarm, vehicle: vehicle, harness: harness, timeout: 20)
        assertSuccess(response, command: .fleetVehicleDoDisarm, vehicle: vehicle)
    }

    // MARK: - Wait / env helpers

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval? = nil,
        pollInterval: TimeInterval = 0.5,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout ?? bootTimeout)
        while Date() < deadline {
            if condition() {
                return
            }
            let nanos = UInt64(max(0.05, pollInterval) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
        }
        XCTFail("Timed out waiting for \(description) after \(Int(timeout ?? bootTimeout))s.")
    }

    private static var isSmokeEnabled: Bool {
        let raw = ProcessInfo.processInfo.environment[smokeEnvKey]?.lowercased()
        return raw == "1" || raw == "true" || raw == "yes"
    }

    private func envDouble(_ key: String, default fallback: TimeInterval) -> TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = TimeInterval(raw),
              value > 0
        else {
            return fallback
        }
        return value
    }
}
