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
    /// `FleetMissionVehicleToken.storageKey` when bound to the Vehicles list; `nil` if unassigned or legacy text-only.
    var attachedFleetVehicleToken: String?

    init(
        id: UUID = UUID(),
        pathId: UUID? = nil,
        rosterDeviceId: UUID,
        slotName: String,
        attachedDevice: String = "",
        attachedFleetVehicleToken: String? = nil
    ) {
        self.id = id
        self.pathId = pathId
        self.rosterDeviceId = rosterDeviceId
        self.slotName = slotName
        self.attachedDevice = attachedDevice
        self.attachedFleetVehicleToken = attachedFleetVehicleToken
    }

    enum CodingKeys: String, CodingKey {
        case id, pathId, rosterDeviceId, slotName, attachedDevice, attachedFleetVehicleToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        pathId = try c.decodeIfPresent(UUID.self, forKey: .pathId)
        rosterDeviceId = try c.decode(UUID.self, forKey: .rosterDeviceId)
        slotName = try c.decode(String.self, forKey: .slotName)
        attachedDevice = try c.decodeIfPresent(String.self, forKey: .attachedDevice) ?? ""
        attachedFleetVehicleToken = try c.decodeIfPresent(String.self, forKey: .attachedFleetVehicleToken)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(pathId, forKey: .pathId)
        try c.encode(rosterDeviceId, forKey: .rosterDeviceId)
        try c.encode(slotName, forKey: .slotName)
        try c.encode(attachedDevice, forKey: .attachedDevice)
        try c.encodeIfPresent(attachedFleetVehicleToken, forKey: .attachedFleetVehicleToken)
    }

    /// Roster slot is ready to start when tied to a fleet vehicle or legacy free-text device.
    var hasFleetOrLegacyAssignment: Bool {
        if let t = attachedFleetVehicleToken, !t.isEmpty { return true }
        return !attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    var completedAt: Date?
    /// When true, the run finishes the current cycle gracefully, then stops (no further loop / continuous scheduling).
    var pendingGracefulCycleStop: Bool

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
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        pendingGracefulCycleStop: Bool = false
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
        self.completedAt = completedAt
        self.pendingGracefulCycleStop = pendingGracefulCycleStop
    }

    enum CodingKeys: String, CodingKey {
        case id, missionId, missionName, status, scheduleMode, oneOffStartAt, loopIntervalMinutes
        case assignments, createdAt, startedAt, completedAt, pendingGracefulCycleStop
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        missionId = try c.decode(UUID.self, forKey: .missionId)
        missionName = try c.decode(String.self, forKey: .missionName)
        status = try c.decode(MissionRunStatus.self, forKey: .status)
        scheduleMode = try c.decode(MissionRunScheduleMode.self, forKey: .scheduleMode)
        oneOffStartAt = try c.decode(Date.self, forKey: .oneOffStartAt)
        loopIntervalMinutes = try c.decode(Int.self, forKey: .loopIntervalMinutes)
        assignments = try c.decode([MissionRunAssignment].self, forKey: .assignments)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        pendingGracefulCycleStop = try c.decodeIfPresent(Bool.self, forKey: .pendingGracefulCycleStop) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(missionId, forKey: .missionId)
        try c.encode(missionName, forKey: .missionName)
        try c.encode(status, forKey: .status)
        try c.encode(scheduleMode, forKey: .scheduleMode)
        try c.encode(oneOffStartAt, forKey: .oneOffStartAt)
        try c.encode(loopIntervalMinutes, forKey: .loopIntervalMinutes)
        try c.encode(assignments, forKey: .assignments)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(pendingGracefulCycleStop, forKey: .pendingGracefulCycleStop)
    }
}
