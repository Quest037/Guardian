import Darwin
import Dispatch
import Foundation

/// After **force quit**, PX4 / ArduPilot children can survive as OS orphans. On **cold launch** and when the
/// in-app sim list has **no alive processes**, we:
/// 1. Kill PIDs recorded in ``GuardianSitlSpawnRegistry`` (every root `SitlProcessRunner` spawn) if they still match their saved fingerprint.
/// 2. Kill processes matching **bundle paths**, **developer checkout paths** (from `SitlLaunchRecipe`), and common helpers (`px4-mavlink`, runtime dirs).
/// 3. Expand each matched root to its whole **subtree** via `pgrep -P` so `mavproxy`, `px4-mavlink`, etc. are included.
///
/// Set `GUARDIAN_SKIP_SITL_ORPHAN_BLITZ=1` to disable.
enum GuardianSitlOrphanBlitz {
    private static let skipEnvKey = "GUARDIAN_SKIP_SITL_ORPHAN_BLITZ"
    private static let sigtermWaitUsec: useconds_t = 280_000
    /// Spawns registered at or after this time are never killed by pgrep during a blitz (avoids first-spawn races).
    private static let appLaunchedAt = Date().timeIntervalSince1970

    private static let coldLaunchLock = NSLock()
    /// `nonisolated(unsafe)` — all reads/writes are behind ``coldLaunchLock``.
    nonisolated(unsafe) private static var coldLaunchBlitzFinished = false
    nonisolated(unsafe) private static var coldLaunchSemaphores: [DispatchSemaphore] = []

    static func kickoffFromColdLaunch() {
        kickoffInBackground(markColdLaunch: true)
    }

    /// Blocks the caller until the cold-launch blitz completes (used from `SitlService.spawn` on the main actor).
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

    /// When every built-in SITL row is stopped (e.g. after **Stop all** or mission SIM cleanup).
    static func kickoffWhenAllInstancesStopped() {
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
        var protected = GuardianSitlSpawnRegistry.protectedPIDSet(registeredSince: appLaunchedAt)
        addDescendants(of: protected, into: &protected)

        for rec in GuardianSitlSpawnRegistry.allRecords() {
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
            GuardianSitlSpawnRegistry.removeRecordsRegisteredBefore(appLaunchedAt)
            return
        }

        let ordered = all.sorted(by: >)
        for pid in ordered {
            signalIgnoringESRCH(pid: pid, sig: SIGTERM)
        }
        usleep(sigtermWaitUsec)
        for pid in ordered {
            if isProcessAlive(pid) {
                signalIgnoringESRCH(pid: pid, sig: SIGKILL)
            }
        }

        GuardianSitlSpawnRegistry.removeRecordsRegisteredBefore(appLaunchedAt)
    }

    // MARK: - Registry fingerprint

    private static func registryEntryStillMatches(_ rec: GuardianSitlSpawnRecord) -> Bool {
        guard isProcessAlive(rec.pid) else { return false }
        guard let args = processArguments(pid: rec.pid) else { return false }
        let norm = args.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if norm.isEmpty { return false }
        if norm.contains(rec.executablePath) { return true }
        let fp = rec.fingerprint
        guard fp.count >= 16 else { return false }
        if norm.contains(fp) { return true }
        let head = String(fp.prefix(96))
        if head.count >= 16, norm.hasPrefix(head) { return true }
        return false
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

    // MARK: - Process tree

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
        var out: [pid_t] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(trimmed), pid > 0 else { continue }
            out.append(pid)
        }
        return out
    }

    // MARK: - pgrep patterns

    private static func allPgrepPatterns() -> [String] {
        var list = staticPgrepPatterns()
        list.append(contentsOf: dynamicPgrepPatterns())
        return list
    }

    /// Substrings / literals that are unlikely outside Guardian’s bundled tree.
    private static func staticPgrepPatterns() -> [String] {
        [
            "Px4SitlBundle/bin/px4",
            "px4-mavlink --instance",
            "ArduPilotSitl/Tools/autotest/sim_vehicle.py",
            "ArduPilotSitl/Tools/autotest/run_in_terminal_window.sh",
            "ArduPilotSitl/build/sitl/bin/arducopter",
            "ArduPilotSitl/build/sitl/bin/arduplane",
            "ArduPilotSitl/build/sitl/bin/ardurover",
            "ArduPilotSitl/build/sitl/bin/ardusub",
            "ArduPilotSitl/build/sitl/bin/arduboat",
            "guardian-ardupilot-runtime",
            "guardian-px4-runtime",
        ]
    }

    /// Developer checkouts and non-bundled `px4` binary paths (same resolver as `SitlLaunchRecipe` spawn).
    private static func dynamicPgrepPatterns() -> [String] {
        var out: [String] = []
        if let root = SitlLaunchRecipe.ardupilotRootPath() {
            let er = NSRegularExpression.escapedPattern(for: root)
            out.append(er + "/Tools/autotest/sim_vehicle\\.py")
            out.append(er + "/Tools/autotest/run_in_terminal_window\\.sh")
            for bin in ["arducopter", "arduplane", "ardurover", "ardusub", "arduboat"] {
                out.append(er + "/build/sitl/bin/" + bin)
            }
        }
        if let root = SitlLaunchRecipe.px4SitlRootPath(), let layout = SitlLaunchRecipe.px4ResolvedBuildLayout(root: root) {
            out.append(NSRegularExpression.escapedPattern(for: layout.px4Binary))
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
        var out: [pid_t] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(trimmed), pid > 0 else { continue }
            out.append(pid)
        }
        return out
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
