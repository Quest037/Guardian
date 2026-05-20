import Foundation

/// Training lab map catalogue selection rules (start/end zone requirement).
enum TrainingEnvironmentSelectionPolicy {
    /// **Temporary:** when `true`, any installed map may load in Training; revert to `false` to require World Builder zones again.
    static let allowsMapsWithoutStartAndEndZones = true

    static func isSelectableForTrainingLab(manifest: TrainingEnvironmentManifest) -> Bool {
        allowsMapsWithoutStartAndEndZones || manifest.hasConfiguredStartAndEndZones
    }

    static func isSelectableForTrainingLab(package: TrainingEnvironmentPackage) -> Bool {
        isSelectableForTrainingLab(manifest: package.manifest)
    }

    static func isSelectableForTrainingLab(environmentID: String, packages: [TrainingEnvironmentPackage]) -> Bool {
        if let pkg = packages.first(where: { $0.id == environmentID }) {
            return isSelectableForTrainingLab(package: pkg)
        }
        guard let manifest = TrainingEnvironmentCatalogue.package(id: environmentID)?.manifest else {
            return false
        }
        return isSelectableForTrainingLab(manifest: manifest)
    }
}
