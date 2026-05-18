import AppKit
import SwiftUI

// MARK: - Modal / overlay teardown (macOS)

/// Resets AppKit cursor + key-window focus after blocking chrome (confirms, etc.) disappears.
enum GuardianPresentationChromeTeardown {
    @MainActor
    static func run() {
        NSCursor.arrow.set()
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        guard let contentView = window.contentView else { return }
        if window.firstResponder !== contentView {
            window.makeFirstResponder(contentView)
        }
    }
}

// MARK: - Pointing-hand cursor (macOS)

/// Balanced push/pop for hover cursors; pops on ``onDisappear`` when the view vanishes while still hovered (e.g. confirm dismiss).
private struct GuardianPointerHoverCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

/// Plain ``ButtonStyle`` matching `.plain` interaction plus a **pointing-hand** cursor on hover.
struct GuardianPointerPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(GuardianPointerHoverCursorModifier())
    }
}

extension View {
    /// Pointing-hand cursor while the pointer is over this control (use on ``Button`` after `.bordered` / `.borderedProminent` / `.borderless` when not using ``GuardianPointerPlainButtonStyle``).
    func guardianPointerOnHover() -> some View {
        modifier(GuardianPointerHoverCursorModifier())
    }
}
