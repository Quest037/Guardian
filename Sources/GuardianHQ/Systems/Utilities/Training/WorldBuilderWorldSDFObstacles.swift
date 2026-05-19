import Foundation

/// Reads Guardian obstacle model entries embedded in a training `world.sdf`.
enum WorldBuilderWorldSDFObstacles {
    private static let modelNamePattern = "<model\\s+name=[\"'](guardian_obstacle_[^\"']+)[\"']"

    /// Per-obstacle model names in `world.sdf` (excludes the baked Training aggregate).
    static func obstacleModelNames(inWorldSDF worldURL: URL) -> Set<String> {
        guard let text = try? String(contentsOf: worldURL, encoding: .utf8) else { return [] }
        guard let regex = try? NSRegularExpression(pattern: modelNamePattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var names: Set<String> = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: text) else { return }
            let name = String(text[nameRange])
            guard !TrainingEnvironmentObstacleBaking.isBakedObstacleModelName(name) else { return }
            names.insert(name)
        }
        return names
    }

    static func includesBakedObstacleModel(inWorldSDF worldURL: URL) -> Bool {
        guard let text = try? String(contentsOf: worldURL, encoding: .utf8) else { return false }
        return text.contains("name=\"\(TrainingEnvironmentObstacleBaking.bakedModelName)\"")
            || text.contains("name='\(TrainingEnvironmentObstacleBaking.bakedModelName)'")
    }
}
