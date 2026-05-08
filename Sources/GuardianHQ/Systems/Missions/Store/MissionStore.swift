import Foundation

@MainActor
final class MissionStore: ObservableObject {
    @Published private(set) var missions: [Mission] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        fileURL = MissionStore.makeFileURL()
        load()
        syncPaladinMissionDomainSnapshot()
    }

    func addMission(name: String, description: String, type: MissionType) {
        let mission = Mission(name: name, description: description, type: type)
        missions.insert(mission, at: 0)
        save()
        syncPaladinMissionDomainSnapshot()
    }

    func updateMission(_ updated: Mission) {
        guard let idx = missions.firstIndex(where: { $0.id == updated.id }) else { return }
        missions[idx] = updated
        save()
        syncPaladinMissionDomainSnapshot()
    }

    func deleteMission(id: UUID) {
        missions.removeAll { $0.id == id }
        save()
        syncPaladinMissionDomainSnapshot()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            missions = try decoder.decode([Mission].self, from: data)
        } catch {
            missions = []
        }
        syncPaladinMissionDomainSnapshot()
    }

    private func save() {
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try encoder.encode(missions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save missions: \(error)")
        }
    }

    private static func makeFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("GuardianHQ", isDirectory: true)
            .appendingPathComponent("missions.json")
    }

    private func syncPaladinMissionDomainSnapshot() {
        PaladinEngine.shared.missionDomain().refreshMissionSupportSnapshot(
            activeRunCount: 0,
            supportedMissionCount: missions.count
        )
    }
}
