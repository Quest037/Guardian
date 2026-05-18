import Foundation

/// Which Guardian surface spawned a built-in SITL process.
enum SitlSpawnOwner: String, Codable, Equatable, Sendable {
    case vehicles
    case formationsPlayground
    case trainingVehicle
}

extension Array where Element == SitlRunningInstance {
    func aliveInstances(owner: SitlSpawnOwner) -> [SitlRunningInstance] {
        filter { $0.isAlive && $0.spawnOwner == owner }
    }
}
