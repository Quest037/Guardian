import Foundation

/// Distinct squad slot colours for the Training lab map (avoid start blue / end green zone tints).
enum TrainingLabSquadFormationPalette {
    private static let hexByIndex = [
        "#f59e0b",
        "#a855f7",
        "#f97316",
        "#e11d48",
        "#d946ef",
        "#0d9488",
        "#ca8a04",
        "#7c3aed",
    ]

    static func colorHex(squadIndex: Int) -> String {
        let palette = hexByIndex
        guard !palette.isEmpty else { return "#f59e0b" }
        return palette[squadIndex % palette.count]
    }
}
