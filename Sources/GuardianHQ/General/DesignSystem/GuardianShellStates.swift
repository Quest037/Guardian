import SwiftUI

// MARK: - Empty state (Theme §8.1)

/// Centered **icon + title + detail** with optional **primary** (blue) and **secondary** (neutral outline) actions — fleet lists, mission drawers, etc.
struct GuardianEmptyState: View {
    let systemImage: String
    let title: String
    var detail: String? = nil
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: GuardianSpacing.cardBodyInset) {
                Image(systemName: systemImage)
                    .font(GuardianTypography.relativeFixed(size: 44, weight: .medium, relativeTo: .largeTitle))
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(GuardianTypography.relativeFixed(size: 20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                if primaryTitle != nil || secondaryTitle != nil {
                    HStack(spacing: GuardianSpacing.sm) {
                        Spacer(minLength: 0)
                        if let secondaryTitle, !secondaryTitle.isEmpty, let secondaryAction {
                            GuardianThemedButton(
                                title: secondaryTitle,
                                accent: .neutral,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: secondaryAction
                            )
                        }
                        if let primaryTitle, !primaryTitle.isEmpty, let primaryAction {
                            GuardianPrimaryProminentButton(title: primaryTitle, action: primaryAction)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, GuardianSpacing.xxs)
                }
            }
            .padding(GuardianSpacing.xxl)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Loading (Theme §8.2)

/// **Spinner** for blocking or in-pane loads; **skeleton** for placeholder bodies (e.g. below a ``GuardianCard`` header while media loads).
enum GuardianLoadingStyle: Equatable {
    case spinner(caption: String?)
    case skeleton(lineCount: Int)
}

struct GuardianLoadingState: View {
    var style: GuardianLoadingStyle = .spinner(caption: nil)

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        switch style {
        case .spinner(let caption):
            VStack(spacing: GuardianSpacing.sm) {
                ProgressView()
                    .controlSize(.regular)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(caption ?? "Loading")
        case .skeleton(let count):
            let lines = max(1, count)
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                ForEach(0..<lines, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.borderSubtle.opacity(colorScheme == .dark ? 0.45 : 0.55))
                        .frame(height: index == 0 ? 12 : 8)
                        .frame(maxWidth: .infinity)
                        .opacity(1.0 - Double(index) * 0.1)
                }
            }
            .padding(GuardianSpacing.sm)
            .accessibilityLabel("Loading placeholder")
        }
    }
}

// MARK: - Inline blocking error (Theme §8.3)

/// **Blocking** error strip — stronger than ``GuardianInlineNotice`` danger (left rail + icon); use when the screen cannot proceed until the operator reads the failure (still not a ``GuardianConfirm``).
struct GuardianInlineError: View {
    let title: String
    let message: String
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: GuardianSpacing.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(GuardianSemanticColors.dangerForeground)
                .frame(width: GuardianSpacing.xxs, height: 44)
                .accessibilityHidden(true)
            Image(systemName: "xmark.octagon.fill")
                .font(GuardianTypography.font(.inlineNoticeIconWarning))
                .foregroundStyle(GuardianSemanticColors.dangerForeground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                Text(title)
                    .font(GuardianTypography.font(.inlineNoticeTitle))
                    .foregroundStyle(theme.textPrimary)
                Text(message)
                    .font(GuardianTypography.font(.inlineNoticeDetail))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let retryTitle, !retryTitle.isEmpty, let onRetry {
                GuardianPrimaryProminentButton(title: retryTitle, action: onRetry)
            }
        }
        .padding(GuardianSpacing.sm)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: GuardianSpacing.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianSpacing.xs, style: .continuous)
                .strokeBorder(GuardianSemanticColors.dangerStroke.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
