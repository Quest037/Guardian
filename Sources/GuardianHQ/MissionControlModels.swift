import Foundation

enum MissionRunStatus: String, Codable, CaseIterable, Identifiable {
    case setup
    case running
    case paused
    case completed

    var id: String { rawValue }
}

enum MissionRunScheduleMode: String, Codable, CaseIterable, Identifiable {
    case oneOff = "One-Off"
    case loop = "Loop"
    case continuous = "Continuous"

    var id: String { rawValue }
}

struct MissionRunAssignment: Identifiable, Codable, Equatable {
    let id: UUID
    /// Path this slot belongs to; `nil` for legacy runs created before path grouping.
    var pathId: UUID?
    var rosterDeviceId: UUID
    var slotName: String
    var attachedDevice: String

    init(
        id: UUID = UUID(),
        pathId: UUID? = nil,
        rosterDeviceId: UUID,
        slotName: String,
        attachedDevice: String = ""
    ) {
        self.id = id
        self.pathId = pathId
        self.rosterDeviceId = rosterDeviceId
        self.slotName = slotName
        self.attachedDevice = attachedDevice
    }

    enum CodingKeys: String, CodingKey {
        case id, pathId, rosterDeviceId, slotName, attachedDevice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        pathId = try c.decodeIfPresent(UUID.self, forKey: .pathId)
        rosterDeviceId = try c.decode(UUID.self, forKey: .rosterDeviceId)
        slotName = try c.decode(String.self, forKey: .slotName)
        attachedDevice = try c.decodeIfPresent(String.self, forKey: .attachedDevice) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(pathId, forKey: .pathId)
        try c.encode(rosterDeviceId, forKey: .rosterDeviceId)
        try c.encode(slotName, forKey: .slotName)
        try c.encode(attachedDevice, forKey: .attachedDevice)
    }
}

struct MissionRun: Identifiable, Codable, Equatable {
    let id: UUID
    var missionId: UUID
    var missionName: String
    var status: MissionRunStatus
    var scheduleMode: MissionRunScheduleMode
    var oneOffStartAt: Date
    var loopIntervalMinutes: Int
    var assignments: [MissionRunAssignment]
    let createdAt: Date
    var startedAt: Date?

    init(
        id: UUID = UUID(),
        missionId: UUID,
        missionName: String,
        status: MissionRunStatus = .setup,
        scheduleMode: MissionRunScheduleMode = .oneOff,
        oneOffStartAt: Date = Date(),
        loopIntervalMinutes: Int = 15,
        assignments: [MissionRunAssignment] = [],
        createdAt: Date = Date(),
        startedAt: Date? = nil
    ) {
        self.id = id
        self.missionId = missionId
        self.missionName = missionName
        self.status = status
        self.scheduleMode = scheduleMode
        self.oneOffStartAt = oneOffStartAt
        self.loopIntervalMinutes = loopIntervalMinutes
        self.assignments = assignments
        self.createdAt = createdAt
        self.startedAt = startedAt
    }
}
