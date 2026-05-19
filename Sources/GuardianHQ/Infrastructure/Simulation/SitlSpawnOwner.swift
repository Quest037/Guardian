import Foundation

/// Which Guardian surface spawned a built-in SITL process.
enum SitlSpawnOwner: String, Codable, Equatable, Sendable {
    case vehicles
    /// Training lab roster (unified panel — map, squads, teach, formation follow).
    case trainingRoster
}

extension Array where Element == SitlRunningInstance {
    func aliveInstances(owner: SitlSpawnOwner) -> [SitlRunningInstance] {
        filter { $0.isAlive && $0.spawnOwner == owner }
    }
}
