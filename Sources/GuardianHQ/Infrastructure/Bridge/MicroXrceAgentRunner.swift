import Foundation

/// Runs Micro XRCE-DDS Agent (UDP) for PX4 uXRCE-DDS ↔ ROS 2 bridging.
@MainActor
final class MicroXrceAgentRunner {
    private var process: Process?
    private var stderrPipe: Pipe?
    private var didTeardown = false

    var onStderrLine: ((String) -> Void)?
    var onTerminated: ((Int32) -> Void)?

    var isRunning: Bool { process?.isRunning == true }

    func start(executablePath: String, udpPort: Int) throws {
        guard process == nil else { return }
        didTeardown = false
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw FleetLinkError.startFailed("MicroXRCEAgent not executable at \(executablePath)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = ["udp4", "-p", "\(udpPort)"]
        let err = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = err
        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.teardownOnce(exitCode: finished.terminationStatus)
            }
        }
        try proc.run()
        process = proc
        stderrPipe = err
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
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
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stderrPipe?.fileHandleForReading.close()
        stderrPipe = nil
        process?.terminationHandler = nil
        process = nil
        let cb = onTerminated
        onTerminated = nil
        onStderrLine = nil
        cb?(exitCode)
    }
}
