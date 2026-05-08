import SwiftUI
import AppKit

struct GuardianThemePalette {
    let backgroundBase: Color
    let backgroundRaised: Color
    let backgroundElevated: Color
    let backgroundActive: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let borderSubtle: Color
    let overlayScrim: Color
}

enum GuardianTheme {
    static func palette(for scheme: ColorScheme) -> GuardianThemePalette {
        switch scheme {
        case .dark:
            return GuardianThemePalette(
                backgroundBase: Color(red: 0.07, green: 0.07, blue: 0.08),
                backgroundRaised: Color(red: 0.12, green: 0.12, blue: 0.13),
                backgroundElevated: Color(red: 0.10, green: 0.10, blue: 0.11),
                backgroundActive: Color(red: 0.20, green: 0.20, blue: 0.21),
                textPrimary: .white,
                textSecondary: .gray,
                textTertiary: .gray.opacity(0.85),
                borderSubtle: Color.white.opacity(0.08),
                overlayScrim: Color.black.opacity(0.45)
            )
        default:
            return GuardianThemePalette(
                backgroundBase: Color(red: 0.95, green: 0.95, blue: 0.96),
                backgroundRaised: Color(red: 0.90, green: 0.90, blue: 0.92),
                backgroundElevated: Color(red: 0.86, green: 0.86, blue: 0.89),
                backgroundActive: Color(red: 0.80, green: 0.82, blue: 0.87),
                textPrimary: Color.black.opacity(0.88),
                textSecondary: Color.black.opacity(0.62),
                textTertiary: Color.black.opacity(0.5),
                borderSubtle: Color.black.opacity(0.12),
                overlayScrim: Color.black.opacity(0.20)
            )
        }
    }
}

enum GuardianDynamicColors {
    static let backgroundBase = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    })
    static let backgroundRaised = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.92, alpha: 1)
    })
    static let backgroundElevated = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
            : NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.89, alpha: 1)
    })
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.82)
    static let borderSubtle = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.12)
    })
}
