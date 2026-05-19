import Foundation

/// Resolved wingman formation tuning from an imported brain pack `squad_profile`.
struct GuardianBrainSquadProfileTuning: Equatable, Sendable {
    var formation: MissionSquadFormationKind?
    /// Pack spacing tier (tight / normal / loose), not convoy metre offsets.
    var formationPackSpacing: MissionSquadFormationSpacing?
    var convoySpacing: MissionSquadConvoySpacing?
    var brainDisplayName: String?
    var brainVersion: GuardianBrainVersion?
}

/// Parses Training-exported `squad_profile` for MRE wingman / convoy follow.
enum GuardianBrainSquadProfileResolution {
    private struct ConvoyExportPayload: Codable {
        var simCount: Int
        var alongTrackMetersPerOrdinal: Double
        var lateralLaneMeters: Double
        var shapeScaleAlong: Double
        var shapeScaleLateral: Double
    }

    static func tuning(
        for fleetType: FleetVehicleType,
        bindings: [MissionRunBrainBinding],
        fileManager: FileManager = .default
    ) -> GuardianBrainSquadProfileTuning? {
        guard let binding = GuardianBrainRunUtilities.preferredBinding(for: fleetType, bindings: bindings),
              let pack = try? GuardianBrainRunUtilities.loadPack(for: binding, fileManager: fileManager),
              let profile = pack.squadProfile
        else { return nil }
        return tuning(
            from: profile,
            brainDisplayName: binding.displayName,
            brainVersion: binding.brainVersion
        )
    }

    static func tuning(
        from profile: GuardianBrainPackSquadProfile,
        brainDisplayName: String? = nil,
        brainVersion: GuardianBrainVersion? = nil
    ) -> GuardianBrainSquadProfileTuning? {
        let formation = profile.formation.flatMap { MissionSquadFormationKind(rawValue: $0) }
        let payload = profile.convoyOffsetsJSON.flatMap { json -> ConvoyExportPayload? in
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ConvoyExportPayload.self, from: data)
        }
        let formationPackSpacing = payload.map {
            inferredPackSpacing(alongScale: $0.shapeScaleAlong, lateralScale: $0.shapeScaleLateral)
        }
        let convoySpacing: MissionSquadConvoySpacing? = {
            if let payload {
                return MissionSquadConvoySpacing(
                    alongTrackMetersPerOrdinal: payload.alongTrackMetersPerOrdinal,
                    lateralLaneMeters: payload.lateralLaneMeters
                )
            }
            if let slotSpacingM = profile.slotSpacingM {
                return MissionSquadConvoySpacing(
                    alongTrackMetersPerOrdinal: slotSpacingM,
                    lateralLaneMeters: 0
                )
            }
            return nil
        }()
        guard formation != nil || formationPackSpacing != nil || convoySpacing != nil else { return nil }
        return GuardianBrainSquadProfileTuning(
            formation: formation,
            formationPackSpacing: formationPackSpacing,
            convoySpacing: convoySpacing,
            brainDisplayName: brainDisplayName,
            brainVersion: brainVersion
        )
    }

    static func inferredPackSpacing(alongScale: Double, lateralScale: Double) -> MissionSquadFormationSpacing {
        let candidates: [MissionSquadFormationSpacing] = [.tight, .normal, .loose]
        return candidates.min(by: { lhs, rhs in
            distance(alongScale: alongScale, lateralScale: lateralScale, to: lhs)
                < distance(alongScale: alongScale, lateralScale: lateralScale, to: rhs)
        }) ?? .normal
    }

    private static func distance(
        alongScale: Double,
        lateralScale: Double,
        to spacing: MissionSquadFormationSpacing
    ) -> Double {
        let dAlong = alongScale - spacing.alongTrackScale
        let dLat = lateralScale - spacing.lateralScale
        return (dAlong * dAlong) + (dLat * dLat)
    }
}
