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
        scheduleCardThumbnailGeneration(for: mission.id)
    }

    func updateMission(_ updated: Mission) {
        guard let idx = missions.firstIndex(where: { $0.id == updated.id }) else { return }
        missions[idx] = updated
        save()
        syncPaladinMissionDomainSnapshot()
    }

    func deleteMission(id: UUID) {
        MissionCardThumbnailSubsystem.deleteFileIfPresent(for: id)
        missions.removeAll { $0.id == id }
        save()
        syncPaladinMissionDomainSnapshot()
    }

    func setMissionArchived(id: UUID, archived: Bool) {
        guard let idx = missions.firstIndex(where: { $0.id == id }) else { return }
        missions[idx].isArchived = archived
        save()
        syncPaladinMissionDomainSnapshot()
    }

    @discardableResult
    func cloneMission(id: UUID, newName: String) -> Mission? {
        guard let source = missions.first(where: { $0.id == id }) else { return nil }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cloned = Mission(
            name: trimmed,
            description: source.description,
            type: source.type,
            isArchived: false,
            count: source.count,
            duration: source.duration,
            deviceIDs: source.deviceIDs,
            rosterDevices: source.rosterDevices,
            routeMacro: source.routeMacro
        )
        missions.insert(cloned, at: 0)
        save()
        syncPaladinMissionDomainSnapshot()
        scheduleCardThumbnailGeneration(for: cloned.id)
        return cloned
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            missions = try decoder.decode([Mission].self, from: data)
        } catch {
            missions = []
        }
        syncPaladinMissionDomainSnapshot()
        ensureCardThumbnailsForLoadedMissions()
    }

    /// One-time JPEG generation for missions saved before thumbnails existed.
    private func ensureCardThumbnailsForLoadedMissions() {
        Task { @MainActor in
            var anyChanged = false
            for mission in missions {
                let url = MissionCardThumbnailSubsystem.fileURL(forMissionID: mission.id)
                guard !FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try await MissionCardThumbnailSubsystem.generateAndSave(for: mission.id)
                    guard let idx = missions.firstIndex(where: { $0.id == mission.id }) else { continue }
                    missions[idx].cardThumbnailVersion += 1
                    anyChanged = true
                } catch {
                    print("Mission card thumbnail backfill failed: \(error)")
                }
            }
            if anyChanged {
                save()
                syncPaladinMissionDomainSnapshot()
            }
        }
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

    nonisolated private static func makeFileURL() -> URL {
        guardianAppSupportDirectoryURL.appendingPathComponent("missions.json")
    }

    /// Application Support / GuardianHQ (missions.json and MissionCardThumbnails live here).
    nonisolated static var guardianAppSupportDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("GuardianHQ", isDirectory: true)
    }

    nonisolated static var missionCardThumbnailsDirectoryURL: URL {
        guardianAppSupportDirectoryURL.appendingPathComponent("MissionCardThumbnails", isDirectory: true)
    }

    private func scheduleCardThumbnailGeneration(for missionID: UUID) {
        Task { @MainActor in
            do {
                try await MissionCardThumbnailSubsystem.generateAndSave(for: missionID)
                guard let idx = missions.firstIndex(where: { $0.id == missionID }) else { return }
                missions[idx].cardThumbnailVersion += 1
                save()
                syncPaladinMissionDomainSnapshot()
            } catch {
                print("Mission card thumbnail failed: \(error)")
            }
        }
    }

    private func syncPaladinMissionDomainSnapshot() {
        PaladinEngine.shared.missionDomain().refreshMissionSupportSnapshot(
            activeRunCount: 0,
            supportedMissionCount: missions.count
        )
    }
}
