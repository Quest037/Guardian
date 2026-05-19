import Foundation

/// Training lab snapshot inputs for `planner_hints` on brain export.
struct GuardianBrainPackTrainingPlannerContext: Equatable, Sendable {
    var vehicleClass: TrainingVehicleClass
    var vehicleSizeTier: VehicleSizeTier
    var layout: TrainingTaskLayout
    var segments: [TrainingControlSegment]
    var planPathSource: TrainingNav2PlanPathResponse.Source
    var nav2StackReady: Bool
    var nav2StackStatus: String
    var gazeboEnvironmentId: String?
    var planWaypointCount: Int
}

enum GuardianBrainPackBuilder {
    static func squadProfile(
        formation: MissionSquadFormationKind,
        spacing: MissionSquadFormationSpacing,
        vehicleClass: TrainingVehicleClass,
        simCount: Int
    ) -> GuardianBrainPackSquadProfile {
        let convoySpacing = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .patrol,
            primaryGranularClass: vehicleClass.fleetVehicleType,
            spacing: spacing,
            formation: formation
        )
        struct ConvoyExportPayload: Codable {
            var simCount: Int
            var alongTrackMetersPerOrdinal: Double
            var lateralLaneMeters: Double
            var shapeScaleAlong: Double
            var shapeScaleLateral: Double
        }
        let payload = ConvoyExportPayload(
            simCount: simCount,
            alongTrackMetersPerOrdinal: convoySpacing.alongTrackMetersPerOrdinal,
            lateralLaneMeters: convoySpacing.lateralLaneMeters,
            shapeScaleAlong: spacing.alongTrackScale,
            shapeScaleLateral: spacing.lateralScale
        )
        let convoyJSON = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        return GuardianBrainPackSquadProfile(
            formation: formation.rawValue,
            slotSpacingM: convoySpacing.alongTrackMetersPerOrdinal,
            convoyOffsetsJSON: convoyJSON
        )
    }

    /// Snapshot Nav2 / Aerostack2 lab overlays from the active Training rehearsal (path source, layout, stack status).
    static func plannerHints(from context: GuardianBrainPackTrainingPlannerContext) -> GuardianBrainPackPlannerHints? {
        let planner = GuardianAutonomyPlannerRouting.defaultPlannerKind(for: context.vehicleClass.fleetVehicleType)
        let maxSpeed = inferredMaxSpeedMS(from: context.segments)
        let footprint = VehicleClassSizeCatalogue.footprint(
            vehicleClass: context.vehicleClass.fleetVehicleType,
            tier: context.vehicleSizeTier
        )
        let footprintFields = footprintPlannerFields(tier: context.vehicleSizeTier, footprint: footprint)
        switch planner {
        case .nav2:
            struct Nav2TrainingOverlay: Codable {
                var capturedFrom: String
                var nav2PlanPathSource: String
                var nav2StackReady: Bool
                var nav2StackStatus: String
                var gazeboEnvironmentId: String?
                var startLatitudeDeg: Double
                var startLongitudeDeg: Double
                var goalLatitudeDeg: Double
                var goalLongitudeDeg: Double
                var planWaypointCount: Int
                var plannerToleranceM: Double
                var robotRadiusM: Double
                var inflationRadiusM: Double
            }
            let overlay = Nav2TrainingOverlay(
                capturedFrom: "guardian_training_lab",
                nav2PlanPathSource: context.planPathSource.rawValue,
                nav2StackReady: context.nav2StackReady,
                nav2StackStatus: context.nav2StackStatus,
                gazeboEnvironmentId: context.gazeboEnvironmentId,
                startLatitudeDeg: context.layout.start.latitudeDeg,
                startLongitudeDeg: context.layout.start.longitudeDeg,
                goalLatitudeDeg: context.layout.goal.latitudeDeg,
                goalLongitudeDeg: context.layout.goal.longitudeDeg,
                planWaypointCount: context.planWaypointCount,
                plannerToleranceM: 1.0,
                robotRadiusM: 0.35,
                inflationRadiusM: 0.55
            )
            let json = (try? JSONEncoder().encode(overlay)).flatMap { String(data: $0, encoding: .utf8) }
            return GuardianBrainPackPlannerHints(
                frameId: "map",
                maxSpeedMS: maxSpeed,
                sizeTier: footprintFields.sizeTier,
                widthCm: footprintFields.widthCm,
                lengthCm: footprintFields.lengthCm,
                heightCm: footprintFields.heightCm,
                nav2ParamOverlayJSON: json,
                aerostack2ParamOverlayJSON: nil
            )
        case .aerostack2:
            struct Aerostack2TrainingOverlay: Codable {
                var capturedFrom: String
                var gazeboEnvironmentId: String?
                var startLatitudeDeg: Double
                var startLongitudeDeg: Double
                var goalLatitudeDeg: Double
                var goalLongitudeDeg: Double
            }
            let overlay = Aerostack2TrainingOverlay(
                capturedFrom: "guardian_training_lab",
                gazeboEnvironmentId: context.gazeboEnvironmentId,
                startLatitudeDeg: context.layout.start.latitudeDeg,
                startLongitudeDeg: context.layout.start.longitudeDeg,
                goalLatitudeDeg: context.layout.goal.latitudeDeg,
                goalLongitudeDeg: context.layout.goal.longitudeDeg
            )
            let json = (try? JSONEncoder().encode(overlay)).flatMap { String(data: $0, encoding: .utf8) }
            return GuardianBrainPackPlannerHints(
                frameId: "map",
                maxSpeedMS: maxSpeed,
                sizeTier: footprintFields.sizeTier,
                widthCm: footprintFields.widthCm,
                lengthCm: footprintFields.lengthCm,
                heightCm: footprintFields.heightCm,
                nav2ParamOverlayJSON: nil,
                aerostack2ParamOverlayJSON: json
            )
        case .none:
            return GuardianBrainPackPlannerHints(
                frameId: nil,
                maxSpeedMS: maxSpeed,
                sizeTier: footprintFields.sizeTier,
                widthCm: footprintFields.widthCm,
                lengthCm: footprintFields.lengthCm,
                heightCm: footprintFields.heightCm,
                nav2ParamOverlayJSON: nil,
                aerostack2ParamOverlayJSON: nil
            )
        }
    }

    private static func footprintPlannerFields(
        tier: VehicleSizeTier,
        footprint: VehicleFootprint
    ) -> (sizeTier: String, widthCm: Int, lengthCm: Int, heightCm: Int) {
        (tier.rawValue, footprint.widthCm, footprint.lengthCm, footprint.heightCm)
    }

    static func inferredMaxSpeedMS(from segments: [TrainingControlSegment]) -> Double {
        let speeds = segments.map { Double(abs($0.bodyForwardMS)) }.filter { $0 > 0 }
        return speeds.max() ?? 0.5
    }

    static func makePack(
        from skill: TrainedVehicleSkill,
        brainId: UUID,
        brainVersion: GuardianBrainVersion,
        displayName: String,
        simPlatform: String = "PX4-SITL",
        gazeboEnvironmentId: String? = nil,
        plannerHints: GuardianBrainPackPlannerHints? = nil,
        squadProfile: GuardianBrainPackSquadProfile? = nil
    ) throws -> GuardianBrainPack {
        let manifest = GuardianBrainPackManifest(
            formatVersion: GuardianBrainPackFormat.currentFormatVersion,
            brainId: brainId,
            brainVersion: brainVersion,
            displayName: displayName,
            createdAt: Date(),
            trainingAppBuild: AppMetadata.releaseVersion,
            vehicleClasses: [skill.vehicleClass.rawValue],
            taskKinds: [skill.taskKind.rawValue],
            gazeboEnvironmentId: gazeboEnvironmentId
        )
        let skillSection = GuardianBrainPackSkill(
            segments: skill.segments,
            layout: skill.layout,
            score: skill.score,
            summary: skill.summary
        )
        let provenance = GuardianBrainPackProvenance(
            trialIndex: skill.trialIndex,
            simPlatform: simPlatform,
            worldHash: nil,
            checksumSHA256: ""
        )
        let pack = GuardianBrainPack(
            manifest: manifest,
            skill: skillSection,
            plannerHints: plannerHints,
            squadProfile: squadProfile,
            provenance: provenance
        )
        return try GuardianBrainPackCodec.packWithChecksum(pack)
    }

    static func defaultDisplayName(for skill: TrainedVehicleSkill) -> String {
        "\(skill.taskKind.displayTitle) — \(skill.vehicleClass.displayTitle)"
    }
}
