import AppKit
import SwiftUI

/// Rounded-bezel numeric field with **arrow-key** step (▲/▼) and clamped range. Pair with ``Stepper`` when visible increment buttons are needed.
struct StrictNumberField: NSViewRepresentable {
    @Binding var value: Double
    let step: Double
    let min: Double
    let max: Double
    var onFocusChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, step: step, min: min, max: max, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> ArrowStepTextField {
        let textField = ArrowStepTextField(frame: .zero)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textField.delegate = context.coordinator
        textField.stringValue = context.coordinator.string(from: value)
        textField.onFocusChange = { isFocused in
            context.coordinator.onFocusChange?(isFocused)
        }
        return textField
    }

    func updateNSView(_ nsView: ArrowStepTextField, context: Context) {
        context.coordinator.step = step
        context.coordinator.min = min
        context.coordinator.max = max
        context.coordinator.onFocusChange = onFocusChange
        let expected = context.coordinator.string(from: value)
        if nsView.stringValue != expected {
            nsView.stringValue = expected
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Double>
        var step: Double
        var min: Double
        var max: Double
        var onFocusChange: ((Bool) -> Void)?

        init(value: Binding<Double>, step: Double, min: Double, max: Double, onFocusChange: ((Bool) -> Void)?) {
            self.value = value
            self.step = step
            self.min = min
            self.max = max
            self.onFocusChange = onFocusChange
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            onFocusChange?(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            onFocusChange?(false)
            if let textField = obj.object as? NSTextField {
                textField.stringValue = string(from: value.wrappedValue)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            let sanitized = sanitize(textField.stringValue)
            if textField.stringValue != sanitized {
                textField.stringValue = sanitized
            }
            guard !sanitized.isEmpty, sanitized != ".", let parsed = Double(sanitized) else { return }
            value.wrappedValue = clamped(parsed)
        }

        func adjustFromLiveValue(_ liveText: String, delta: Double) -> Double {
            let sanitized = sanitize(liveText)
            let base = (sanitized.isEmpty || sanitized == ".") ? value.wrappedValue : (Double(sanitized) ?? value.wrappedValue)
            let next = clamped(base + delta)
            value.wrappedValue = next
            return next
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let delta: Double
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                delta = step
            case #selector(NSResponder.moveDown(_:)):
                delta = -step
            default:
                return false
            }

            let next = adjustFromLiveValue(textView.string, delta: delta)
            let formatted = string(from: next)
            textView.string = formatted
            if let field = control as? NSTextField {
                field.stringValue = formatted
            }
            return true
        }

        func clamped(_ number: Double) -> Double {
            Swift.max(min, Swift.min(max, number))
        }

        func sanitize(_ input: String) -> String {
            var result = ""
            var seenDot = false
            for char in input {
                if char >= "0" && char <= "9" {
                    result.append(char)
                } else if char == "." && !seenDot {
                    seenDot = true
                    result.append(char)
                }
            }
            if result.first == "." {
                result = "0" + result
            }
            return result
        }

        func string(from number: Double) -> String {
            if number.rounded() == number {
                return String(Int(number))
            }
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 8
            formatter.decimalSeparator = "."
            return formatter.string(from: NSNumber(value: number)) ?? String(number)
        }
    }
}

final class ArrowStepTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocusChange?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChange?(false)
        }
        return resigned
    }
}
