import Foundation

/// Persists **root** SITL PIDs Guardian spawned (`SitlProcessRunner`) so a **cold launch** can terminate them after **force quit**
/// (children like `px4-mavlink` / `mavproxy` are found via `pgrep -P` during the blitz).
struct GuardianSitlSpawnRecord: Codable, Equatable, Sendable {
    let pid: Int32
    let executablePath: String
    let fingerprint: String
    let registeredAt: TimeInterval
}

enum GuardianSitlSpawnRegistry {
    private static let fileName = "sitl-spawn-registry-v1.json"
    private static let appSupportFolderName = "com.calwest.guardianhq"
    private static let maxRecords = 96

    private static func registryURL() throws -> URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let dir = base.appendingPathComponent(appSupportFolderName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func fingerprint(executablePath: String, arguments: [String]) -> String {
        ([executablePath] + arguments).joined(separator: " ")
    }

    /// Call after `Process.run()` succeeds for any Guardian SITL root (`px4`, `python … sim_vehicle.py`, etc.).
    static func register(pid: pid_t, executablePath: String, arguments: [String]) {
        guard pid > 1 else { return }
        let record = GuardianSitlSpawnRecord(
            pid: pid,
            executablePath: executablePath,
            fingerprint: fingerprint(executablePath: executablePath, arguments: arguments),
            registeredAt: Date().timeIntervalSince1970
        )
        do {
            var list = try readAll()
            list.removeAll { $0.pid == record.pid }
            list.append(record)
            list.sort { $0.registeredAt > $1.registeredAt }
            if list.count > maxRecords {
                list = Array(list.prefix(maxRecords))
            }
            try writeAll(list)
        } catch {}
    }

    static func unregister(pid: pid_t) {
        guard pid > 1 else { return }
        do {
            var list = try readAll()
            list.removeAll { $0.pid == pid }
            try writeAll(list)
        } catch {}
    }

    static func allRecords() -> [GuardianSitlSpawnRecord] {
        (try? readAll()) ?? []
    }

    /// PIDs Guardian registered since `launchTime` (current session spawns — must not be orphan-blitzed).
    static func protectedPIDSet(registeredSince launchTime: TimeInterval) -> Set<pid_t> {
        Set(
            allRecords()
                .filter { $0.registeredAt >= launchTime }
                .map { pid_t($0.pid) }
        )
    }

    /// Drops persisted rows from prior sessions; keeps rows registered at or after `launchTime`.
    static func removeRecordsRegisteredBefore(_ launchTime: TimeInterval) {
        do {
            let kept = try readAll().filter { $0.registeredAt >= launchTime }
            try writeAll(kept)
        } catch {}
    }

    /// Clears persisted PIDs (e.g. after a startup orphan blitz).
    static func clearAll() {
        try? writeAll([])
    }

    private static func readAll() throws -> [GuardianSitlSpawnRecord] {
        let url = try registryURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([GuardianSitlSpawnRecord].self, from: data)
    }

    private static func writeAll(_ records: [GuardianSitlSpawnRecord]) throws {
        let url = try registryURL()
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: [.atomic])
    }
}
