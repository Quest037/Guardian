import Foundation

/// Persists the training panel target slot per environment (Application Support).
enum TrainingTargetSlotStore {
  private static let legacyFileName = "training_target_slot.json"
  private static let fileName = "training_target_slots.json"

  private struct FilePayload: Codable, Equatable {
    var slotsByEnvironmentID: [String: TrainingTaskPose]
  }

  static func load(environmentID: String, fileURL: URL? = nil) throws -> TrainingTaskPose? {
    let slots = try loadAll(fileURL: fileURL)
    return slots[environmentID]
  }

  static func save(_ pose: TrainingTaskPose, environmentID: String, fileURL: URL? = nil) throws {
    var slots = (try? loadAll(fileURL: fileURL)) ?? [:]
    slots[environmentID] = pose
    try writeAll(slots, fileURL: fileURL)
  }

  static func remove(environmentID: String, fileURL: URL? = nil) throws {
    var slots = try loadAll(fileURL: fileURL)
    guard slots.removeValue(forKey: environmentID) != nil else { return }
    try writeAll(slots, fileURL: fileURL)
  }

  static func loadAll(fileURL: URL? = nil) throws -> [String: TrainingTaskPose] {
    let dir = try directoryURL(fileURL: fileURL)
    if let migrated = try migrateLegacySinglePoseIfNeeded(directory: dir) {
      return migrated
    }
    let url = dir.appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
    return try JSONDecoder().decode(FilePayload.self, from: data).slotsByEnvironmentID
  }

  private static func writeAll(_ slots: [String: TrainingTaskPose], fileURL: URL? = nil) throws {
    let dir = try directoryURL(fileURL: fileURL)
    let url = dir.appendingPathComponent(fileName)
    let payload = FilePayload(slotsByEnvironmentID: slots)
    let data = try JSONEncoder().encode(payload)
    try data.write(to: url, options: .atomic)
  }

  private static func migrateLegacySinglePoseIfNeeded(directory: URL) throws -> [String: TrainingTaskPose]? {
    let legacyURL = directory.appendingPathComponent(legacyFileName)
    guard let data = try? Data(contentsOf: legacyURL), !data.isEmpty else { return nil }
    let pose = try JSONDecoder().decode(TrainingTaskPose.self, from: data)
    let slots = [TrainingEnvironmentManifest.defaultBundledID: pose]
    try writeAll(slots, fileURL: directory)
    try? FileManager.default.removeItem(at: legacyURL)
    return slots
  }

  private static func directoryURL(fileURL: URL?) throws -> URL {
    if let fileURL {
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
        return fileURL
      }
      return fileURL.deletingLastPathComponent()
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    guard let base else {
      throw NSError(domain: "TrainingTargetSlotStore", code: 1)
    }
    let dir = base.appendingPathComponent("Guardian/training", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
