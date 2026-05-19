import Darwin
import Dispatch
import Foundation

/// Terminates orphaned `gz sim` / Harmonic Ruby CLI children after force quit (mirrors ``GuardianSitlOrphanBlitz``).
/// Set `GUARDIAN_SKIP_GAZEBO_ORPHAN_BLITZ=1` to disable.
enum GuardianGazeboOrphanBlitz {
    private static let skipEnvKey = "GUARDIAN_SKIP_GAZEBO_ORPHAN_BLITZ"
    private static let sigtermWaitUsec: useconds_t = 280_000
    private static let appLaunchedAt = Date().timeIntervalSince1970

    private static let coldLaunchLock = NSLock()
    nonisolated(unsafe) private static var coldLaunchBlitzFinished = false
    nonisolated(unsafe) private static var coldLaunchSemaphores: [DispatchSemaphore] = []

    static func kickoffFromColdLaunch() {
        kickoffInBackground(markColdLaunch: true)
    }

    static func blockUntilColdLaunchBlitzFinishedIfNeeded() {
        coldLaunchLock.lock()
        if coldLaunchBlitzFinished {
            coldLaunchLock.unlock()
            return
        }
        let sem = DispatchSemaphore(value: 0)
        coldLaunchSemaphores.append(sem)
        coldLaunchLock.unlock()
        sem.wait()
    }

    private static func finishColdLaunchBlitz() {
        coldLaunchLock.lock()
        coldLaunchBlitzFinished = true
        let semaphores = coldLaunchSemaphores
        coldLaunchSemaphores.removeAll(keepingCapacity: true)
        coldLaunchLock.unlock()
        for sem in semaphores {
            sem.signal()
        }
    }

    static func kickoffWhenAllWorldsStopped() {
        kickoffInBackground()
    }

    private static func kickoffInBackground(markColdLaunch: Bool = false) {
        guard ProcessInfo.processInfo.environment[skipEnvKey] == nil else {
            if markColdLaunch { finishColdLaunchBlitz() }
            return
        }
        DispatchQueue.global(qos: .utility).async {
            runBlocking()
            if markColdLaunch { finishColdLaunchBlitz() }
        }
    }

    static func runBlocking() {
        guard ProcessInfo.processInfo.environment[skipEnvKey] == nil else { return }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let ownPid32 = Int32(ownPid)

        var roots: Set<pid_t> = []
        var protected = GuardianGazeboSpawnRegistry.protectedPIDSet(registeredSince: appLaunchedAt)
        addDescendants(of: protected, into: &protected)

        for rec in GuardianGazeboSpawnRegistry.allRecords() {
            guard rec.pid > 1, rec.pid != ownPid32 else { continue }
            guard rec.registeredAt < appLaunchedAt else { continue }
            if registryEntryStillMatches(rec) {
                roots.insert(rec.pid)
            }
        }

        for pattern in allPgrepPatterns() {
            for pid in matchingPids(pattern: pattern) where pid > 1 && pid != ownPid32 {
                guard !protected.contains(pid) else { continue }
                roots.insert(pid)
            }
        }

        var all = roots
        addDescendants(of: roots, into: &all)
        guard !all.isEmpty else {
            GuardianGazeboSpawnRegistry.removeRecordsRegisteredBefore(appLaunchedAt)
            return
        }

        let ordered = all.sorted(by: >)
        for pid in ordered {
            signalIgnoringESRCH(pid: pid, sig: SIGTERM)
        }
        usleep(sigtermWaitUsec)
        for pid in ordered where isProcessAlive(pid) {
            signalIgnoringESRCH(pid: pid, sig: SIGKILL)
        }
        GuardianGazeboSpawnRegistry.removeRecordsRegisteredBefore(appLaunchedAt)
    }

    private static func registryEntryStillMatches(_ rec: GuardianGazeboSpawnRecord) -> Bool {
        guard isProcessAlive(rec.pid) else { return false }
        guard let args = processArguments(pid: rec.pid) else { return false }
        let norm = args.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if norm.isEmpty { return false }
        if norm.contains(rec.executablePath) { return true }
        let fp = rec.fingerprint
        guard fp.count >= 16 else { return false }
        return norm.contains(fp)
    }

    private static func processArguments(pid: pid_t) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", "\(pid)", "-ww", "-o", "args="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func addDescendants(of roots: Set<pid_t>, into all: inout Set<pid_t>) {
        var queue = Array(roots)
        var seen = all
        var idx = 0
        while idx < queue.count {
            let p = queue[idx]
            idx += 1
            for c in childPids(ofParent: p) where c > 1 && !seen.contains(c) {
                seen.insert(c)
                all.insert(c)
                queue.append(c)
            }
        }
    }

    private static func childPids(ofParent parent: pid_t) -> [pid_t] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-P", "\(parent)"]
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
            guard let pid = Int32(trimmed), pid > 0 else { return nil }
            return pid
        }
    }

    static func allPgrepPatternsForTesting() -> [String] {
        allPgrepPatterns()
    }

    private static func allPgrepPatterns() -> [String] {
        var list = staticPgrepPatterns()
        list.append(contentsOf: dynamicPgrepPatterns())
        return list
    }

    private static func staticPgrepPatterns() -> [String] {
        [
            "GazeboRuntime/bin/gz",
            "GazeboRuntime/lib/ruby/gz",
            "guardian-gazebo-runtime",
            "GUARDIAN_GAZEBO_WORLD",
            "GUARDIAN_GAZEBO_WEBSOCKET_PORT",
            "guardian_websocket_",
            "lib/ruby/gz/cmdsim",
            "lib/ruby/gz/cmdgui",
            "lib/ruby/gz/cmdlaunch",
            "gz sim server",
            "gz sim gui",
            "gz-launch",
            "libgz-launch-websocket-server",
        ]
    }

    private static func dynamicPgrepPatterns() -> [String] {
        var out: [String] = []
        if let root = GazeboLaunchRecipe.runtimeRootPath() {
            let escaped = NSRegularExpression.escapedPattern(for: root)
            out.append(escaped + "/bin/gz")
            out.append(escaped + "/lib/ruby/gz")
        }
        for base in ["/opt/homebrew", "/usr/local"] {
            out.append(NSRegularExpression.escapedPattern(for: base) + "/Cellar/gz-.*/lib/ruby/gz")
        }
        return out
    }

    private static func matchingPids(pattern: String) -> [pid_t] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-f", pattern]
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
            guard let pid = Int32(trimmed), pid > 0 else { return nil }
            return pid
        }
    }

    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid, 0) == 0
    }

    private static func signalIgnoringESRCH(pid: pid_t, sig: Int32) {
        guard pid > 1 else { return }
        _ = kill(pid, sig)
    }
}
