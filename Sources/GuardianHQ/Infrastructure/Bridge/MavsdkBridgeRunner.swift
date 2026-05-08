import Foundation

/// Runs `mavsdk_bridge.py` (MAVSDK-Python) and forwards line-delimited JSON to the app.
@MainActor
final class MavsdkBridgeRunner {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?
    private var lineBuffer = ""
    private var didTeardown = false

    var onStdoutLine: ((String) -> Void)?
    var onStderrLine: ((String) -> Void)?
    var onTerminated: ((Int32) -> Void)?

    func start(grpcHost: String, grpcPort: Int, connectURL: String?, systemIDs: [Int], scriptDirectory: URL) throws {
        guard process == nil else { return }
        didTeardown = false

        let script = scriptDirectory.appendingPathComponent("mavsdk_bridge.py", isDirectory: false)
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            throw FleetLinkError.startFailed("mavsdk_bridge.py missing at \(script.path)")
        }

        let python = Self.resolvePython3Executable()
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw FleetLinkError.startFailed("python3 not executable at \(python). Set GUARDIAN_PYTHON or install Python 3.")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        var args = [script.path, grpcHost, "\(grpcPort)"]
        if let connectURL {
            let trimmed = connectURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                args.append(trimmed)
            }
        }
        if !systemIDs.isEmpty {
            args.append(systemIDs.map(String.init).joined(separator: ","))
        }
        proc.arguments = args
        proc.currentDirectoryURL = scriptDirectory

        let input = Pipe()
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = input

        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.teardownOnce(exitCode: finished.terminationStatus)
            }
        }

        try proc.run()
        process = proc
        stdinPipe = input
        stdoutPipe = out
        stderrPipe = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self.consumeStdoutChunk(chunk)
            }
        }

        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self.consumeStderrChunk(chunk)
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

    func updateSystemIDs(_ systemIDs: [Int]) {
        guard let input = stdinPipe else { return }
        let normalized = Array(Set(systemIDs.filter { $0 > 0 && $0 < 256 })).sorted()
        let payload: [String: Any] = [
            "type": "set_system_ids",
            "system_ids": normalized,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        var framed = data
        framed.append(0x0A) // newline-delimited JSON
        do {
            try input.fileHandleForWriting.write(contentsOf: framed)
        } catch {
            // Ignore broken pipe; termination handler will clean up process state.
        }
    }

    private func consumeStdoutChunk(_ chunk: String) {
        lineBuffer.append(chunk)
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = lineBuffer.index(after: nl)
            lineBuffer = String(lineBuffer[after...])
            if !line.isEmpty {
                onStdoutLine?(line)
            }
        }
    }

    private func consumeStderrChunk(_ chunk: String) {
        for part in chunk.split(whereSeparator: \.isNewline) {
            let line = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                onStderrLine?(TerminalLogFormatting.stripANSICodes(line))
            }
        }
    }

    private func teardownOnce(exitCode: Int32) {
        guard !didTeardown else { return }
        didTeardown = true

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process?.terminationHandler = nil
        process = nil
        lineBuffer = ""

        let cb = onTerminated
        onTerminated = nil
        onStdoutLine = nil
        onStderrLine = nil
        cb?(exitCode)
    }

    private static func resolvePython3Executable() -> String {
        if let env = ProcessInfo.processInfo.environment["GUARDIAN_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        for candidate in ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/bin/python3"
    }
}

enum MavsdkBridgeLocator {
    /// Directory containing `mavsdk_bridge.py` inside the SwiftPM resource bundle.
    static func bridgeDirectoryURL() -> URL? {
        guard let base = Bundle.module.resourceURL else { return nil }
        let dir = base.appendingPathComponent("MavsdkBridge", isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) { return dir }
        return nil
    }
}
