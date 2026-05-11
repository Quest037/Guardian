import AppKit
import SwiftUI

// MARK: - Pointing-hand cursor (macOS)

/// Plain ``ButtonStyle`` matching `.plain` interaction plus a **pointing-hand** cursor on hover.
struct GuardianPointerPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    /// Pointing-hand cursor while the pointer is over this control (use on ``Button`` after `.bordered` / `.borderedProminent` / `.borderless` when not using ``GuardianPointerPlainButtonStyle``).
    func guardianPointerOnHover() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
