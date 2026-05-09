import SwiftUI

enum ToastStyle {
    case success
    case info
    case error

    /// Legacy translucent chip tint (avoid for new UI; ephemeral toasts use ``ToastHost`` solid fills).
    var background: Color {
        switch self {
        case .success:
            return GuardianSemanticColors.successBackground
        case .info:
            return GuardianSemanticColors.infoBackground
        case .error:
            return GuardianSemanticColors.dangerBackground
        }
    }

    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

@MainActor
final class ToastCenter: ObservableObject {
    @Published var current: ToastMessage?
    private var dismissTask: DispatchWorkItem?

    func show(_ text: String, style: ToastStyle = .info, duration: TimeInterval = 2.2) {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            current = ToastMessage(text: text, style: style)
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                self.current = nil
            }
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
}

struct ToastHost: ViewModifier {
    @EnvironmentObject private var toastCenter: ToastCenter

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content

            if let toast = toastCenter.current {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: toast.style.icon)
                    Text(toast.text)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(toastEphemeralBackground(for: toast.style))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: 380, alignment: .leading)
                .padding(.leading, 14)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// App-wide ephemeral toasts: more readable than ``ToastStyle/background`` tints, less heavy than MC-R banners.
    private func toastEphemeralBackground(for style: ToastStyle) -> Color {
        switch style {
        case .success:
            return Color(red: 0.11, green: 0.44, blue: 0.24).opacity(0.82)
        case .info:
            return Color(red: 0.14, green: 0.34, blue: 0.62).opacity(0.82)
        case .error:
            return Color(red: 0.52, green: 0.14, blue: 0.18).opacity(0.82)
        }
    }
}

extension View {
    func withToasts() -> some View {
        modifier(ToastHost())
    }
}
