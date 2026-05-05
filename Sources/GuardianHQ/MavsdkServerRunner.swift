import Foundation

/// Launches and supervises a `mavsdk_server` child process.
@MainActor
final class MavsdkServerRunner {
    private var process: Process?
    private var outputPipe: Pipe?
    private var aggregatedLog = ""
    private var lineBuffer = ""
    private let maxLogCharacters = 12_000
    private var didTeardown = false

    var onLogLine: ((String) -> Void)?
    var onTerminated: ((Int32) -> Void)?

    func start(configuration: FleetLinkConfiguration) throws {
        guard process == nil else { return }
        didTeardown = false

        let executable = try MavsdkServerLocator.resolveExecutable(configuredPath: configuration.mavsdkServerPath)
        guard configuration.grpcPort > 0, configuration.grpcPort < 65_536 else {
            throw FleetLinkError.startFailed("gRPC port must be between 1 and 65535.")
        }
        let primary = configuration.primaryMavlinkConnectionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty else {
            throw FleetLinkError.startFailed("Primary MAVLink connection URL must not be empty.")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        var args: [String] = ["-p", "\(configuration.grpcPort)", primary]
        args.append(contentsOf: configuration.additionalMavlinkConnectionURLs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        proc.arguments = args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.standardInput = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.teardownOnce(exitCode: finished.terminationStatus)
            }
        }

        try proc.run()

        process = proc
        outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self.appendLogChunk(chunk)
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

    private func appendLogChunk(_ chunk: String) {
        aggregatedLog.append(chunk)
        if aggregatedLog.count > maxLogCharacters {
            aggregatedLog = String(aggregatedLog.suffix(maxLogCharacters))
        }

        lineBuffer.append(chunk)
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let raw = String(lineBuffer[..<nl])
            let after = lineBuffer.index(after: nl)
            lineBuffer = String(lineBuffer[after...])
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let line = TerminalLogFormatting.stripANSICodes(trimmed)
                if !line.isEmpty {
                    onLogLine?(line)
                }
            }
        }
    }

    private func teardownOnce(exitCode: Int32) {
        guard !didTeardown else { return }
        didTeardown = true

        if !lineBuffer.isEmpty {
            let trimmed = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let line = TerminalLogFormatting.stripANSICodes(trimmed)
                if !line.isEmpty {
                    onLogLine?(line)
                }
            }
            lineBuffer = ""
        }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        outputPipe = nil
        process?.terminationHandler = nil
        process = nil

        let callback = onTerminated
        onTerminated = nil
        onLogLine = nil
        callback?(exitCode)
    }
}
