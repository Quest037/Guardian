import Foundation

struct GuardianGazeboSpawnRecord: Codable, Equatable, Sendable {
    let pid: Int32
    let executablePath: String
    let fingerprint: String
    let registeredAt: TimeInterval
}

enum GuardianGazeboSpawnRegistry {
    private static let fileName = "gazebo-spawn-registry-v1.json"
    private static let appSupportFolderName = "com.calwest.guardianhq"
    private static let maxRecords = 48

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

    static func register(pid: pid_t, executablePath: String, arguments: [String]) {
        guard pid > 1 else { return }
        let record = GuardianGazeboSpawnRecord(
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

    static func allRecords() -> [GuardianGazeboSpawnRecord] {
        (try? readAll()) ?? []
    }

    static func protectedPIDSet(registeredSince launchTime: TimeInterval) -> Set<pid_t> {
        Set(
            allRecords()
                .filter { $0.registeredAt >= launchTime }
                .map { pid_t($0.pid) }
        )
    }

    static func removeRecordsRegisteredBefore(_ launchTime: TimeInterval) {
        do {
            let kept = try readAll().filter { $0.registeredAt >= launchTime }
            try writeAll(kept)
        } catch {}
    }

    private static func readAll() throws -> [GuardianGazeboSpawnRecord] {
        let url = try registryURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([GuardianGazeboSpawnRecord].self, from: data)
    }

    private static func writeAll(_ records: [GuardianGazeboSpawnRecord]) throws {
        let url = try registryURL()
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
    }
}
