import Foundation

/// Runs one SITL child process (ArduPilot `sim_vehicle.py`, PX4, etc.) and forwards log lines.
@MainActor
final class SitlProcessRunner {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    /// Keeps stdin open so the child never sees EOF on fd 0 (nullDevice makes many CLIs, including sim_vehicle, exit immediately).
    private var stdinWriteKeepAlive: FileHandle?
    private var stdoutRemainder = ""
    private var stderrRemainder = ""
    private var didTeardown = false

    var onLogLine: ((String) -> Void)?
    var onTerminated: ((Int32) -> Void)?

    func start(spec: SitlProcessSpec) throws {
        guard process == nil else { return }
        didTeardown = false

        guard FileManager.default.isExecutableFile(atPath: spec.executable) else {
            throw SitlError.startFailed("Executable not found or not executable: \(spec.executable)")
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
        } catch {
            try? stdinWriteKeepAlive?.close()
            stdinWriteKeepAlive = nil
            throw error
        }
        stdoutPipe = out
        stderrPipe = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self.consumeStdout(chunk)
            }
        }

        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self.consumeStderr(chunk)
            }
        }
    }

    func stop() {
        guard let proc = process, !didTeardown else { return }
        if proc.isRunning {
            proc.terminate()
        } else {
            teardownOnce(exitCode: proc.terminationStatus)
        }
    }

    private func consumeStdout(_ chunk: String) {
        emitLines(merging: chunk, into: &stdoutRemainder, prefix: "[sitl] ")
    }

    private func consumeStderr(_ chunk: String) {
        emitLines(merging: chunk, into: &stderrRemainder, prefix: "[sitl:err] ")
    }

    private func emitLines(merging chunk: String, into buffer: inout String, prefix: String) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: "\n") {
            let raw = String(buffer[..<nl])
            let after = buffer.index(after: nl)
            buffer = String(buffer[after...])
            let line = TerminalLogFormatting.stripANSICodes(
                raw.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if !line.isEmpty {
                onLogLine?(prefix + line)
            }
        }
    }

    private func teardownOnce(exitCode: Int32) {
        guard !didTeardown else { return }
        didTeardown = true

        flushRemainder(&stdoutRemainder, prefix: "[sitl] ")
        flushRemainder(&stderrRemainder, prefix: "[sitl:err] ")

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        stdoutPipe = nil
        stderrPipe = nil
        try? stdinWriteKeepAlive?.close()
        stdinWriteKeepAlive = nil
        process?.terminationHandler = nil
        process = nil

        let cb = onTerminated
        onTerminated = nil
        onLogLine = nil
        cb?(exitCode)
    }

    private func flushRemainder(_ buffer: inout String, prefix: String) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !trimmed.isEmpty else { return }
        let line = TerminalLogFormatting.stripANSICodes(trimmed)
        if !line.isEmpty {
            onLogLine?(prefix + line)
        }
    }
}
