import Foundation

/// Mission run + catalogue helpers for brain bindings (MCS picker, MC-R chrome, export).
enum GuardianBrainRunUtilities {
    static func trainingVehicleClassRaw(for fleetType: FleetVehicleType) -> String? {
        switch fleetType {
        case .uavCopter: return TrainingVehicleClass.uavCopter.rawValue
        case .ugvWheeled: return TrainingVehicleClass.ugvWheeled.rawValue
        case .ugvTracked: return TrainingVehicleClass.ugvTracked.rawValue
        default: return nil
        }
    }

    static func taskKindDisplayTitle(_ raw: String) -> String {
        TrainingTaskKind(rawValue: raw)?.displayTitle ?? raw
    }

    static func vehicleClassDisplayTitle(_ raw: String) -> String {
        TrainingVehicleClass(rawValue: raw)?.displayTitle ?? raw
    }

    static func bindingCaption(_ binding: MissionRunBrainBinding) -> String {
        "\(binding.displayName) · \(binding.brainVersion.displayLabel)"
    }

    static func preferredBinding(
        for fleetType: FleetVehicleType,
        bindings: [MissionRunBrainBinding]
    ) -> MissionRunBrainBinding? {
        guard let vehicleClassRaw = trainingVehicleClassRaw(for: fleetType) else { return nil }
        return bindings.first { $0.vehicleClassRaw == vehicleClassRaw }
    }

    static func catalogueEntries(
        matching binding: MissionRunBrainBinding,
        fileManager: FileManager = .default
    ) throws -> [GuardianBrainCatalogueEntry] {
        try GuardianBrainCatalogueStore.listEntries(fileManager: fileManager)
            .filter {
                $0.manifest.taskKinds.contains(binding.taskKindRaw)
                    && $0.manifest.vehicleClasses.contains(binding.vehicleClassRaw)
            }
            .sorted {
                if $0.manifest.brainId == $1.manifest.brainId {
                    return $0.manifest.brainVersion > $1.manifest.brainVersion
                }
                return $0.manifest.displayName.localizedCaseInsensitiveCompare($1.manifest.displayName) == .orderedAscending
            }
    }

    static func loadPack(
        for binding: MissionRunBrainBinding,
        fileManager: FileManager = .default
    ) throws -> GuardianBrainPack? {
        let url = try GuardianBrainCatalogueStore.packFileURL(
            brainId: binding.brainId,
            brainVersion: binding.brainVersion,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try GuardianBrainPackCodec.decode(Data(contentsOf: url))
    }

    /// Prepends structured brain metadata to mission log export (JSON block).
    static func structuredBrainExportHeader(
        bindings: [MissionRunBrainBinding],
        fileManager: FileManager = .default
    ) -> String {
        guard !bindings.isEmpty else { return "" }
        struct ExportRow: Codable {
            let task_kind: String
            let vehicle_class: String
            let brain_id: String
            let brain_version: String
            let major_line: String
            let format_version: Int
            let display_name: String
        }
        struct ExportPayload: Codable {
            let brains: [ExportRow]
        }
        let rows: [ExportRow] = bindings.sorted { lhs, rhs in
            if lhs.vehicleClassRaw != rhs.vehicleClassRaw {
                return lhs.vehicleClassRaw < rhs.vehicleClassRaw
            }
            return lhs.taskKindRaw < rhs.taskKindRaw
        }.map { binding in
            let formatVersion = (try? loadPack(for: binding, fileManager: fileManager))?.manifest.formatVersion
                ?? GuardianBrainPackFormat.currentFormatVersion
            return ExportRow(
                task_kind: binding.taskKindRaw,
                vehicle_class: binding.vehicleClassRaw,
                brain_id: binding.brainId.uuidString,
                brain_version: binding.brainVersion.semverString,
                major_line: binding.brainVersion.majorLineCodename,
                format_version: formatVersion,
                display_name: binding.displayName
            )
        }
        guard let data = try? JSONEncoder().encode(ExportPayload(brains: rows)),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return "# Guardian brain bindings\n\(json)\n\n"
    }
}
