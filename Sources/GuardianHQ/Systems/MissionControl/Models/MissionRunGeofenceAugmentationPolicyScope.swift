import Foundation

/// Which run policy bucket holds ``MissionGeofence`` augmentation rows for inline altitude edits.
enum MissionRunGeofenceAugmentationPolicyScope: Hashable, Sendable {
    case missionWide
    case task(UUID)
    case assignment(UUID)
}
