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

    /// Gazebo proxy material tint — matches formation slot rings in the embedded viewport.
    static func gazeboMaterialRGBA(squadIndex: Int) -> GazeboUniversalClassVisualStyle.RGBA {
        rgba(fromHex: colorHex(squadIndex: squadIndex))
            ?? GazeboUniversalClassVisualStyle.rgba(for: .unknown)
    }

    /// Parses `#RRGGBB` or `RRGGBB` (case-insensitive).
    static func rgba(fromHex hex: String) -> GazeboUniversalClassVisualStyle.RGBA? {
        var body = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if body.hasPrefix("#") { body.removeFirst() }
        guard body.count == 6, let value = UInt32(body, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return GazeboUniversalClassVisualStyle.RGBA(r: r, g: g, b: b, a: 1.0)
    }
}
