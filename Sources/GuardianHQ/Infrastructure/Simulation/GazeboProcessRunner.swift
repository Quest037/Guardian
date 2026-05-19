import Foundation

@MainActor
final class GazeboProcessRunner {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinWriteKeepAlive: FileHandle?
    private var stdoutRemainder = ""
    private var stderrRemainder = ""
    private var didTeardown = false

    var onLogLine: ((String) -> Void)?
    var onTerminated: ((Int32) -> Void)?

    var isRunning: Bool {
        process?.isRunning == true
    }

    var processIdentifier: pid_t? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    func start(spec: GazeboProcessSpec) throws {
        guard process == nil else { return }
        didTeardown = false

        guard FileManager.default.isExecutableFile(atPath: spec.executable) else {
            throw GazeboError.startFailed("Executable not found or not executable: \(spec.executable)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: spec.executable)
        proc.arguments = spec.arguments
        proc.currentDirectoryURL = spec.currentDirectoryURL
        var env = ProcessInfo.processInfo.environment
        for (k, v) in spec.environment {
            env[k] = v
        }
        proc.environment = env

        let out = Pipe()
        let err = Pipe()
        let stdinPipe = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = stdinPipe.fileHandleForReading
        stdinWriteKeepAlive = stdinPipe.fileHandleForWriting

        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.teardownOnce(exitCode: finished.terminationStatus)
            }
        }

        do {
            try proc.run()
            process = proc
            GuardianGazeboSpawnRegistry.register(
                pid: proc.processIdentifier,
                executablePath: spec.executable,
                arguments: spec.arguments
            )
        } catch {
            try? stdinWriteKeepAlive?.close()
            stdinWriteKeepAlive = nil
            throw GazeboError.startFailed(error.localizedDescription)
        }
        stdoutPipe = out
        stderrPipe = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self.consume(pipe: &self.stdoutRemainder, chunk: chunk) }
        }

        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self.consume(pipe: &self.stderrRemainder, chunk: chunk) }
        }
    }

    func stop() {
        guard let proc = process, proc.isRunning else {
            teardownOnce(exitCode: process?.terminationStatus ?? 0)
            return
        }
        proc.terminate()
    }

    private func consume(pipe: inout String, chunk: String) {
        pipe += chunk
        while let range = pipe.range(of: "\n") {
            let line = String(pipe[pipe.startIndex..<range.lowerBound])
            pipe.removeSubrange(pipe.startIndex...range.lowerBound)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            onLogLine?(trimmed)
        }
    }

    private func teardownOnce(exitCode: Int32) {
        guard !didTeardown else { return }
        didTeardown = true
        if let pid = process?.processIdentifier {
            GuardianGazeboSpawnRegistry.unregister(pid: pid)
        }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdinWriteKeepAlive?.close()
        stdinWriteKeepAlive = nil
        process = nil
        onTerminated?(exitCode)
    }
}
