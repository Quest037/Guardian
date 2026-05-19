import Foundation

enum GuardianBrainDispatchFailure: Error, Equatable, Sendable {
    case noBinding
    case packNotFound
    case emptyExecutableContent
}

enum GuardianBrainDispatchStrategy: Equatable, Sendable {
    case segmentPath(binding: MissionRunBrainBinding, formatVersion: Int)
    case plannerPath(binding: MissionRunBrainBinding, formatVersion: Int)
}

/// Resolves which OFFBOARD execution path MRE should use for an imported brain pack (Phase 4).
enum GuardianBrainDispatchResolver {
    static func correlationSource(for binding: MissionRunBrainBinding) -> String {
        "brain:\(binding.brainId.uuidString):v\(binding.brainVersion.semverString)"
    }

    static func resolve(
        fleetVehicleType: FleetVehicleType,
        bindings: [MissionRunBrainBinding],
        taskKindRaw: String? = nil,
        fileManager: FileManager = .default
    ) -> Result<GuardianBrainDispatchStrategy, GuardianBrainDispatchFailure> {
        guard let binding = selectBinding(
            fleetVehicleType: fleetVehicleType,
            bindings: bindings,
            taskKindRaw: taskKindRaw
        ) else {
            return .failure(.noBinding)
        }
        guard let pack = try? GuardianBrainRunUtilities.loadPack(for: binding, fileManager: fileManager) else {
            return .failure(.packNotFound)
        }
        let formatVersion = pack.manifest.formatVersion
        if !pack.skill.segments.isEmpty {
            return .success(.segmentPath(binding: binding, formatVersion: formatVersion))
        }
        if pack.plannerHints != nil {
            return .success(.plannerPath(binding: binding, formatVersion: formatVersion))
        }
        return .failure(.emptyExecutableContent)
    }

    private static func selectBinding(
        fleetVehicleType: FleetVehicleType,
        bindings: [MissionRunBrainBinding],
        taskKindRaw: String?
    ) -> MissionRunBrainBinding? {
        guard let vehicleClassRaw = GuardianBrainRunUtilities.trainingVehicleClassRaw(for: fleetVehicleType) else {
            return nil
        }
        if let taskKindRaw {
            return bindings.first {
                $0.vehicleClassRaw == vehicleClassRaw && $0.taskKindRaw == taskKindRaw
            }
        }
        return bindings.first { $0.vehicleClassRaw == vehicleClassRaw }
    }
}
