import SwiftUI

extension OperatorPromptDisplaySource {

    /// Card **fill** for bottom-strip / drawer / persistent operator-prompt chrome. Mission Control / MRE use a core constant; assistants use **plugin-supplied** hex only (see ``OperatorPromptDisplaySource/assistant``).
    func resolvedOperatorPromptCardFillColor(severityForAssistantHexFallback: GuardianFeedbackSeverity) -> Color {
        switch self {
        case .missionControl, .mre:
            if let (r, g, b) = OperatorPromptHexRGB.rgbUInt8Components(
                hex6: OperatorPromptChrome.missionRunStackPromptCardBackgroundHex6
            ) {
                return Color(
                    red: Double(r) / 255.0,
                    green: Double(g) / 255.0,
                    blue: Double(b) / 255.0
                )
            }
            return severityForAssistantHexFallback.bottomPromptBannerBackground

        case .assistant(_, _, let pluginHex):
            if let norm = OperatorPromptHexRGB.normalizedRGBHex6(pluginHex),
               let (r, g, b) = OperatorPromptHexRGB.rgbUInt8Components(hex6: norm) {
                return Color(
                    red: Double(r) / 255.0,
                    green: Double(g) / 255.0,
                    blue: Double(b) / 255.0
                )
            }
            return severityForAssistantHexFallback.bottomPromptBannerBackground
        }
    }

    /// When `true`, MC-R / Live Drive cards should use **dark** primary text (pastel issuer fill). When `false`, keep high-contrast **white** copy on severity banner fills.
    var usesPastelIssuerOperatorPromptCardFill: Bool {
        switch self {
        case .missionControl, .mre:
            return true
        case .assistant(_, _, let pluginHex):
            return OperatorPromptHexRGB.normalizedRGBHex6(pluginHex) != nil
        }
    }
}
