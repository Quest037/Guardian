import SwiftUI

enum ToastStyle {
    case success
    case info
    case error

    var background: Color {
        switch self {
        case .success:
            return Color.green.opacity(0.22)
        case .info:
            return Color.blue.opacity(0.22)
        case .error:
            return Color.red.opacity(0.24)
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
        ZStack(alignment: .bottomTrailing) {
            content

            if let toast = toastCenter.current {
                HStack(spacing: 8) {
                    Image(systemName: toast.style.icon)
                    Text(toast.text)
                        .lineLimit(2)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(toast.style.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.trailing, 18)
                .padding(.bottom, 16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

extension View {
    func withToasts() -> some View {
        modifier(ToastHost())
    }
}
