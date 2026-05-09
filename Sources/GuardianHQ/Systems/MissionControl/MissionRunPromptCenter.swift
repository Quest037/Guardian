import SwiftUI

/// Visual style for **Mission Run** (MC-R) bottom prompts only — not app-wide toasts.
enum MissionRunPromptStyle: Equatable {
    case success
    case info
    case warning
    case error

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "flag.checkered"
        case .error: return "xmark.circle.fill"
        }
    }

    /// Solid banner fills (readable on any sheet background); stronger than ephemeral app toasts.
    var bannerBackground: Color {
        switch self {
        case .success:
            return Color(red: 0.09, green: 0.46, blue: 0.24)
        case .info:
            return Color(red: 0.12, green: 0.35, blue: 0.68)
        case .warning:
            return Color(red: 0.52, green: 0.38, blue: 0.08)
        case .error:
            return Color(red: 0.58, green: 0.14, blue: 0.17)
        }
    }
}

struct MissionRunDismissiblePrompt: Identifiable, Equatable {
    enum Buttons: Equatable {
        case singleDismiss
        case pair(confirm: String, dismiss: String)
    }

    let id: UUID
    let text: String
    let style: MissionRunPromptStyle
    let buttons: Buttons

    init(text: String, style: MissionRunPromptStyle, buttons: Buttons = .singleDismiss) {
        self.id = UUID()
        self.text = text
        self.style = style
        self.buttons = buttons
    }
}

/// Bottom prompts for an open Mission Run (MC-R) sheet only. Independent from ``ToastCenter``.
@MainActor
final class MissionRunPromptCenter: ObservableObject {
    @Published private(set) var activePrompt: MissionRunDismissiblePrompt?
    private var onDismissCallback: (() -> Void)?
    private var onConfirmCallback: (() -> Void)?

    func present(_ text: String, style: MissionRunPromptStyle = .info, onDismiss: (() -> Void)? = nil) {
        onDismissCallback = onDismiss
        onConfirmCallback = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            activePrompt = MissionRunDismissiblePrompt(text: text, style: style, buttons: .singleDismiss)
        }
    }

    /// Two actions (e.g. **Keep running** vs **Dismiss**). `onDismiss` runs only for the dismiss control.
    func presentChoice(
        _ text: String,
        style: MissionRunPromptStyle = .warning,
        confirmTitle: String,
        dismissTitle: String,
        onConfirm: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        onDismissCallback = onDismiss
        onConfirmCallback = onConfirm
        withAnimation(.easeInOut(duration: 0.18)) {
            activePrompt = MissionRunDismissiblePrompt(
                text: text,
                style: style,
                buttons: .pair(confirm: confirmTitle, dismiss: dismissTitle)
            )
        }
    }

    func dismiss() {
        let dismissCb = onDismissCallback
        onDismissCallback = nil
        onConfirmCallback = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            activePrompt = nil
        }
        dismissCb?()
    }

    func confirmPrimary() {
        let confirmCb = onConfirmCallback
        onDismissCallback = nil
        onConfirmCallback = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            activePrompt = nil
        }
        confirmCb?()
    }
}

/// Full width of the MC-R host, pinned to the bottom edge (inside the run detail view only).
struct MissionRunPromptBanner: View {
    @ObservedObject var center: MissionRunPromptCenter

    var body: some View {
        Group {
            if let prompt = center.activePrompt {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: prompt.style.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(prompt.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    switch prompt.buttons {
                    case .singleDismiss:
                        Button("Dismiss") {
                            center.dismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.white)
                    case let .pair(confirm, dismiss):
                        HStack(spacing: 8) {
                            Button(dismiss) {
                                center.dismiss()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.white)
                            Button(confirm) {
                                center.confirmPrimary()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(prompt.style.bannerBackground)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.white.opacity(0.2)),
                    alignment: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
