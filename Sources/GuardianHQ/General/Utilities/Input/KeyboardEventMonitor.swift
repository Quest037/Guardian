import AppKit
import SwiftUI

/// Local NSEvent monitor for `.keyDown` / `.keyUp` events while a SwiftUI view is on screen.
///
/// `onKeyDown` and `onKeyUp` should return `true` to consume the event (prevents the system
/// "no key handler" beep) or `false` to let it propagate to the responder chain.
///
/// Live Drive keyboard control needs both edges: `keyDown` (with `event.isARepeat` filter)
/// to begin streaming an axis input, `keyUp` to stop. macOS auto-repeats keyDown after the
/// initial repeat delay, so consumers should ignore repeats when tracking held-key state.
struct KeyboardEventMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyDown: (NSEvent) -> Bool
    let onKeyUp: (NSEvent) -> Bool

    init(
        isEnabled: Bool,
        onKeyDown: @escaping (NSEvent) -> Bool,
        onKeyUp: @escaping (NSEvent) -> Bool = { _ in false }
    ) {
        self.isEnabled = isEnabled
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onKeyDown: onKeyDown, onKeyUp: onKeyUp)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.onKeyUp = onKeyUp
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onKeyDown: (NSEvent) -> Bool
        var onKeyUp: (NSEvent) -> Bool
        private var monitor: Any?

        init(
            isEnabled: Bool,
            onKeyDown: @escaping (NSEvent) -> Bool,
            onKeyUp: @escaping (NSEvent) -> Bool
        ) {
            self.isEnabled = isEnabled
            self.onKeyDown = onKeyDown
            self.onKeyUp = onKeyUp
        }

        func attach() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                guard self.isEnabled else { return event }
                let consumed: Bool
                switch event.type {
                case .keyDown:
                    consumed = self.onKeyDown(event)
                case .keyUp:
                    consumed = self.onKeyUp(event)
                default:
                    consumed = false
                }
                return consumed ? nil : event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
