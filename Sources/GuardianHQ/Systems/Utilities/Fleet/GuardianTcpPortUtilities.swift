import Darwin
import Foundation

enum GuardianTcpPortUtilities {
    /// `true` when this process can bind the TCP port now (port is free).
    static func isTcpPortBindable(_ port: Int, host: String = "127.0.0.1") -> Bool {
        guard port > 0, port < 65_536 else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr(host)

        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0
            }
        }
    }

    /// `true` when something is accepting TCP connections on the port (e.g. Gazebo websocket bridge).
    static func isTcpPortListening(port: Int, host: String = "127.0.0.1") -> Bool {
        guard port > 0, port < 65_536 else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr(host)

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                connect(fd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0
            }
        }
        return connected
    }

    static func waitForTcpPortBindable(port: Int, timeout: TimeInterval, host: String = "127.0.0.1") async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isTcpPortBindable(port, host: host) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return isTcpPortBindable(port, host: host)
    }

    static func waitForTcpPortListening(port: Int, timeout: TimeInterval, host: String = "127.0.0.1") async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isTcpPortListening(port: port, host: host) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return isTcpPortListening(port: port, host: host)
    }

    /// PIDs with a TCP listener on ``port`` (`lsof`, macOS).
    static func processIDsListeningOnTcpPort(_ port: Int) -> [pid_t] {
        guard port > 0, port < 65_536 else { return [] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return []
        }
        guard proc.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(trimmed), pid > 1 else { return nil }
            return pid
        }
    }

    /// Stops orphaned listeners (e.g. stale ``gz-launch``) so the Harmonic websocket plugin can bind.
    static func terminateListeners(on port: Int, excludingPIDs: Set<pid_t> = []) {
        let ownPid = pid_t(ProcessInfo.processInfo.processIdentifier)
        var targets = Set(processIDsListeningOnTcpPort(port))
        targets.subtract(excludingPIDs)
        targets.remove(ownPid)
        guard !targets.isEmpty else { return }
        for pid in targets {
            _ = kill(pid, SIGTERM)
        }
        usleep(280_000)
        for pid in targets where kill(pid, 0) == 0 {
            _ = kill(pid, SIGKILL)
        }
    }

    /// Confirms the Gazebo websocket server accepts connections (not just a stray TCP listener).
    static func canOpenGazeboWebsocket(port: Int, host: String = "127.0.0.1", timeout: TimeInterval = 3) async -> Bool {
        guard let url = URL(string: "ws://\(host):\(port)") else { return false }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        return await withCheckedContinuation { continuation in
            final class ResumeOnce: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                func resume(_ value: Bool, continuation: CheckedContinuation<Bool, Never>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: value)
                }
            }
            let gate = ResumeOnce()
            task.resume()
            task.sendPing { error in
                task.cancel(with: .goingAway, reason: nil)
                gate.resume(error == nil, continuation: continuation)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                task.cancel(with: .goingAway, reason: nil)
                gate.resume(false, continuation: continuation)
            }
        }
    }
}
