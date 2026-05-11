import SwiftUI

// MARK: - Kind

/// Inline banner / callout semantics — soft surface, hairline border, icon tile + title + body (see Theme plugin).
/// Motion: this view is **static**; use ``GuardianMotion`` on a parent if insert/remove should animate (Theme §5).
enum GuardianInlineNoticeKind: Hashable {
    case informational
    case success
    case warning
    case danger
}

// MARK: - View

/// Horizontal **inline notice**: icon tile, **title**, **detail** (body copy), optional **trailing** chrome, optional **bottom** row (e.g. progress) inside one rounded, bordered surface.
struct GuardianInlineNotice<Trailing: View, Bottom: View>: View {
    let kind: GuardianInlineNoticeKind
    let title: String
    let detail: String
    @ViewBuilder private var trailing: () -> Trailing
    @ViewBuilder private var bottom: () -> Bottom

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    init(
        kind: GuardianInlineNoticeKind,
        title: String,
        detail: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder bottom: @escaping () -> Bottom = { EmptyView() }
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.bottom = bottom
    }

    var body: some View {
        let palette = NoticePalette(kind: kind, colorScheme: colorScheme, theme: theme)

        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                noticeIcon(palette: palette)
                    .frame(width: GuardianInlineNoticeLayout.iconColumn, height: GuardianInlineNoticeLayout.iconColumn)

                VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                    Text(title)
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                        .foregroundStyle(palette.titleColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(GuardianTypography.font(.inlineNoticeDetail))
                        .foregroundStyle(palette.messageColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing()
            }

            bottom()
        }
        .padding(.horizontal, GuardianInlineNoticeLayout.horizontalPadding)
        .padding(.vertical, GuardianInlineNoticeLayout.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                theme.backgroundRaised
                palette.tintWash
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: GuardianInlineNoticeLayout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GuardianInlineNoticeLayout.cornerRadius, style: .continuous)
                .strokeBorder(palette.borderColor, lineWidth: 1)
        }
        .guardianDropShadow(GuardianElevation.feedbackChrome)
    }

    @ViewBuilder
    private func noticeIcon(palette: NoticePalette) -> some View {
        switch kind {
        case .informational:
            ZStack {
                Circle().fill(palette.iconDiskFill)
                Image(systemName: "info")
                    .font(GuardianTypography.font(.inlineNoticeIconCompactBold))
                    .foregroundStyle(Color.white)
            }
        case .success:
            ZStack {
                Circle().fill(palette.iconDiskFill)
                Image(systemName: "checkmark")
                    .font(GuardianTypography.font(.inlineNoticeIconCompactBold))
                    .foregroundStyle(Color.white)
            }
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(GuardianTypography.font(.inlineNoticeIconWarning))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, palette.iconDiskFill)
        case .danger:
            ZStack {
                Circle().fill(palette.iconDiskFill)
                Image(systemName: "xmark")
                    .font(GuardianTypography.font(.inlineNoticeIconDangerHeavy))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private struct NoticePalette {
        let titleColor: Color
        let messageColor: Color
        let borderColor: Color
        let tintWash: Color
        let iconDiskFill: Color

        init(kind: GuardianInlineNoticeKind, colorScheme: ColorScheme, theme: GuardianThemePalette) {
            switch kind {
            case .informational:
                titleColor = theme.textPrimary
                messageColor = theme.textSecondary
                borderColor = GuardianSemanticColors.infoForeground.opacity(0.38)
                tintWash = GuardianSemanticColors.infoBackground.opacity(colorScheme == .dark ? 0.55 : 0.85)
                iconDiskFill = GuardianSemanticColors.infoForeground
            case .success:
                titleColor = theme.textPrimary
                messageColor = theme.textSecondary
                borderColor = GuardianSemanticColors.successStroke.opacity(0.42)
                tintWash = GuardianSemanticColors.successBackground.opacity(colorScheme == .dark ? 0.55 : 0.95)
                iconDiskFill = GuardianSemanticColors.successStroke
            case .warning:
                titleColor = theme.textPrimary
                messageColor = theme.textSecondary
                borderColor = GuardianSemanticColors.warningStroke.opacity(0.45)
                tintWash = GuardianSemanticColors.warningBackground.opacity(colorScheme == .dark ? 0.5 : 0.9)
                iconDiskFill = GuardianSemanticColors.warningStroke
            case .danger:
                titleColor = theme.textPrimary
                messageColor = theme.textSecondary
                borderColor = GuardianSemanticColors.dangerStroke.opacity(0.42)
                tintWash = GuardianSemanticColors.dangerBackground.opacity(colorScheme == .dark ? 0.52 : 0.88)
                iconDiskFill = GuardianSemanticColors.dangerStroke
            }
        }
    }
}

extension GuardianInlineNoticeKind {
    /// Maps notice semantics to ``GuardianFeedbackSeverity`` (``.danger`` → ``GuardianFeedbackSeverity/error``).
    var feedbackSeverity: GuardianFeedbackSeverity {
        switch self {
        case .informational: .info
        case .success: .success
        case .warning: .warning
        case .danger: .error
        }
    }
}

private enum GuardianInlineNoticeLayout {
    static let cornerRadius: CGFloat = 10
    static let horizontalPadding: CGFloat = GuardianSpacing.cardBodyInset
    static let verticalPadding: CGFloat = GuardianSpacing.inlineNoticeVertical
    static let iconColumn: CGFloat = 28
}
