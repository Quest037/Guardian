import Foundation

enum GazeboEntityFactoryError: LocalizedError, Equatable {
  case missingGzBinary
  case serviceFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingGzBinary:
      return "Gazebo `gz` binary not found."
    case .serviceFailed(let detail):
      return detail
    }
  }
}

/// Harmonic `gz service` calls for `/world/<name>/create` and `/remove/blocking`.
enum GazeboEntityFactoryClient {
  static func createModel(
    worldName: String,
    instanceIndex: Int,
    sdfURL: URL,
    modelName: String,
    pose: TrainingEnvironmentPose,
    footprintHeightM: Double
  ) async throws {
    guard let gz = GazeboLocator.gzExecutablePath() else {
      throw GazeboEntityFactoryError.missingGzBinary
    }
    let zCenter = pose.zM + footprintHeightM / 2.0
    let yawRad = pose.yawDeg * .pi / 180.0
    let halfYaw = yawRad / 2.0
    let qz = sin(halfYaw)
    let qw = cos(halfYaw)
    let sdfPath = sdfURL.path
    let req = """
    sdf_filename: "\(sdfPath)", name: "\(modelName)", allow_renaming: false, pose: { position: { x: \(pose.xM) y: \(pose.yM) z: \(zCenter) }, orientation: { z: \(qz) w: \(qw) } }
    """
    switch await runServiceWithOutput(
      gz: gz,
      instanceIndex: instanceIndex,
      service: "/world/\(worldName)/create",
      reqType: "gz.msgs.EntityFactory",
      repType: "gz.msgs.Boolean",
      req: req,
      timeoutMS: 8000
    ) {
    case .success(let output):
      if !parseBooleanServiceResponse(output.stdout, policy: .asyncQueueAck) {
        let detail = [output.stdout, output.stderr]
          .joined(separator: "\n")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        throw GazeboEntityFactoryError.serviceFailed(
          detail.isEmpty
            ? "Gazebo did not confirm model create for \(modelName)."
            : detail
        )
      }
    case .failure(let detail):
      throw GazeboEntityFactoryError.serviceFailed(detail)
    }

    let appeared = await waitForModelName(
      modelName,
      instanceIndex: instanceIndex,
      timeoutMS: 8000,
      pollIntervalMS: 200
    )
    guard appeared else {
      throw GazeboEntityFactoryError.serviceFailed(
        "Model \(modelName) did not appear in Gazebo after create (world \(worldName))."
      )
    }
  }

  /// Polls `gz model --list` until a model name is present (async create ack is not enough).
  static func waitForModelName(
    _ modelName: String,
    instanceIndex: Int,
    timeoutMS: Int = 8000,
    pollIntervalMS: Int = 200
  ) async -> Bool {
    let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)
    while Date() < deadline {
      let names = await listWorldModelNames(instanceIndex: instanceIndex)
      if names.contains(modelName) {
        return true
      }
      let sleepNs = UInt64(max(pollIntervalMS, 50)) * 1_000_000
      try? await Task.sleep(nanoseconds: sleepNs)
    }
    return false
  }

  /// Moves an existing model in-place (drag / nudge) without remove+respawn.
  @discardableResult
  static func setModelPose(
    worldName: String,
    instanceIndex: Int,
    modelName: String,
    pose: TrainingEnvironmentPose,
    footprintHeightM: Double
  ) async -> Bool {
    guard let gz = GazeboLocator.gzExecutablePath() else { return false }
    let zCenter = pose.zM + footprintHeightM / 2.0
    let yawRad = pose.yawDeg * .pi / 180.0
    let halfYaw = yawRad / 2.0
    let qz = sin(halfYaw)
    let qw = cos(halfYaw)
    let req = """
    name: "\(modelName)", position: { x: \(pose.xM) y: \(pose.yM) z: \(zCenter) }, orientation: { z: \(qz) w: \(qw) }
    """
    return (try? await runService(
      gz: gz,
      instanceIndex: instanceIndex,
      service: "/world/\(worldName)/set_pose",
      reqType: "gz.msgs.Pose",
      repType: "gz.msgs.Boolean",
      req: req,
      timeoutMS: 4000,
      booleanPolicy: .asyncQueueAck
    )) ?? false
  }

  /// Removes a model via `/world/<name>/remove/blocking` using the exact name from spawn (`allow_renaming: false`).
  @discardableResult
  static func removeModel(
    worldName: String,
    instanceIndex: Int,
    gazeboModelName: String,
    obstacleID: String? = nil,
    knownLiveModelNames: [String]? = nil
  ) async -> Bool {
    guard GazeboLocator.gzExecutablePath() != nil else { return false }

    var candidates: [String] = []
    func appendCandidate(_ name: String) {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
      candidates.append(trimmed)
    }

    appendCandidate(gazeboModelName)

    let liveNames: [String]
    if let knownLiveModelNames {
      liveNames = knownLiveModelNames
    } else {
      liveNames = await listWorldModelNames(instanceIndex: instanceIndex)
    }
    if let obstacleID {
      for name in liveNames where TrainingEnvironmentObstacleNaming.matchesModelName(name, obstacleID: obstacleID) {
        appendCandidate(name)
      }
    } else if !liveNames.contains(gazeboModelName) {
      for name in liveNames where name.hasPrefix(TrainingEnvironmentObstacleNaming.modelPrefix) {
        appendCandidate(name)
      }
    }

    for name in candidates {
      if await removeModelOnce(
        worldName: worldName,
        instanceIndex: instanceIndex,
        modelName: name
      ) {
        return true
      }
    }
    return false
  }

  enum BooleanServiceStdoutPolicy: Sendable {
    case asyncQueueAck
    case blockingExecuteResult
  }

  static func interpretBlockingRemoveResponse(stdout: String, stderr: String) -> Bool {
    if stderrIndicatesRemoveFailure(stderr) { return false }
    let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty, !stderrIndicatesRemoveFailure(stderr) {
      return true
    }
    return parseBooleanServiceResponse(stdout, policy: .blockingExecuteResult)
  }

  static func stderrIndicatesRemoveFailure(_ stderr: String) -> Bool {
    let lower = stderr.lowercased()
    return lower.contains("not found, so not removed")
      || lower.contains("can't be removed")
      || lower.contains("cannot be removed")
  }

  static func parseBooleanServiceResponse(
    _ stdout: String,
    policy: BooleanServiceStdoutPolicy
  ) -> Bool {
    let lower = stdout.lowercased()
    if lower.contains("data: true") { return true }
    if lower.contains("data: false") { return false }
    switch policy {
    case .asyncQueueAck:
      return stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .blockingExecuteResult:
      return false
    }
  }

  static func listWorldModelNames(instanceIndex: Int) async -> [String] {
    guard let gz = GazeboLocator.gzExecutablePath() else { return [] }
    let result = await runGazeboCommand(
      gz: gz,
      instanceIndex: instanceIndex,
      arguments: ["model", "--list"],
      timeoutMS: 8000
    )
    guard result.exitCode == 0 else { return [] }
    return parseModelListOutput(result.stdout + "\n" + result.stderr)
  }

  static func parseModelListOutput(_ text: String) -> [String] {
    var names: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("- ") else { continue }
      let name = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
      if !name.isEmpty { names.append(name) }
    }
    return names
  }

  static func removeModelOnce(
    worldName: String,
    instanceIndex: Int,
    modelName: String
  ) async -> Bool {
    guard let gz = GazeboLocator.gzExecutablePath() else { return false }
    let req = "type: MODEL, name: \"\(modelName)\""
    let result = await runServiceWithOutput(
      gz: gz,
      instanceIndex: instanceIndex,
      service: "/world/\(worldName)/remove/blocking",
      reqType: "gz.msgs.Entity",
      repType: "gz.msgs.Boolean",
      req: req,
      timeoutMS: 10_000
    )
    switch result {
    case .success(let payload):
      return interpretBlockingRemoveResponse(stdout: payload.stdout, stderr: payload.stderr)
    case .failure:
      return false
    }
  }

  struct CommandOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
  }

  /// `gz topic -i` — lists publishers (fast; does not block like `topic -e`).
  static func runTopicInfoProbe(
    gz: String,
    instanceIndex: Int,
    topic: String,
    timeoutMS: Int = 4000
  ) async -> CommandOutput {
    await runGazeboCommand(
      gz: gz,
      instanceIndex: instanceIndex,
      arguments: ["topic", "-i", "-t", topic],
      timeoutMS: timeoutMS
    )
  }

  /// `gz topic -e` probe for embedded map scene readiness (shared transport partition with sim).
  static func runTopicEchoProbe(
    gz: String,
    instanceIndex: Int,
    topic: String,
    messageCount: Int,
    timeoutMS: Int
  ) async -> CommandOutput {
    await runGazeboCommand(
      gz: gz,
      instanceIndex: instanceIndex,
      arguments: ["topic", "-e", "-t", topic, "-n", "\(messageCount)"],
      timeoutMS: timeoutMS
    )
  }

  private enum ServiceOutputResult: Sendable {
    case success(CommandOutput)
    case failure(String)
  }

  private static func gazeboChildEnvironment(instanceIndex: Int) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    GazeboLaunchRecipe.augmentGazeboProcessEnvironment(&env)
    GazeboLaunchRecipe.applyTransportPartition(
      GazeboLaunchRecipe.transportPartition(forInstanceIndex: instanceIndex),
      to: &env
    )
    return env
  }

  private static func runGazeboCommand(
    gz: String,
    instanceIndex: Int,
    arguments: [String],
    timeoutMS: Int
  ) async -> CommandOutput {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: gz)
      process.arguments = arguments
      process.environment = gazeboChildEnvironment(instanceIndex: instanceIndex)

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      process.terminationHandler = { proc in
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        continuation.resume(
          returning: CommandOutput(stdout: stdout, stderr: stderr, exitCode: proc.terminationStatus)
        )
      }

      do {
        try process.run()
      } catch {
        continuation.resume(returning: CommandOutput(stdout: "", stderr: error.localizedDescription, exitCode: -1))
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMS + 500)) {
        if process.isRunning {
          process.terminate()
        }
      }
    }
  }

  private static func runService(
    gz: String,
    instanceIndex: Int,
    service: String,
    reqType: String,
    repType: String,
    req: String,
    timeoutMS: Int,
    booleanPolicy: BooleanServiceStdoutPolicy
  ) async throws -> Bool {
    switch await runServiceWithOutput(
      gz: gz,
      instanceIndex: instanceIndex,
      service: service,
      reqType: reqType,
      repType: repType,
      req: req,
      timeoutMS: timeoutMS
    ) {
    case .success(let output):
      if booleanPolicy == .blockingExecuteResult {
        return interpretBlockingRemoveResponse(stdout: output.stdout, stderr: output.stderr)
      }
      if stderrIndicatesRemoveFailure(output.stderr) { return false }
      return parseBooleanServiceResponse(output.stdout, policy: booleanPolicy)
    case .failure(let detail):
      throw GazeboEntityFactoryError.serviceFailed(detail)
    }
  }

  private static func runServiceWithOutput(
    gz: String,
    instanceIndex: Int,
    service: String,
    reqType: String,
    repType: String,
    req: String,
    timeoutMS: Int
  ) async -> ServiceOutputResult {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: gz)
      process.arguments = [
        "service",
        "-s", service,
        "--reqtype", reqType,
        "--reptype", repType,
        "--timeout", "\(timeoutMS)",
        "--req", req,
      ]
      process.environment = gazeboChildEnvironment(instanceIndex: instanceIndex)

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      process.terminationHandler = { proc in
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if proc.terminationStatus == 0 {
          continuation.resume(returning: .success(CommandOutput(stdout: stdout, stderr: stderr, exitCode: 0)))
        } else {
          let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
          continuation.resume(returning: .failure(detail.isEmpty ? "exit \(proc.terminationStatus)" : detail))
        }
      }

      do {
        try process.run()
      } catch {
        continuation.resume(returning: .failure(error.localizedDescription))
      }
    }
  }
}
