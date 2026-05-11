import SwiftUI

// MARK: - Layout

/// Padding and rhythm for ``GuardianConfirm`` / ``GuardianConfirmDanger`` (single flat surface, not card slots).
enum GuardianConfirmLayout {
    static let cornerRadius: CGFloat = 10
    static let contentHorizontalPadding: CGFloat = GuardianSpacing.lg
    static let contentTopPadding: CGFloat = GuardianSpacing.sectionStack
    static let contentBottomPadding: CGFloat = GuardianSpacing.sectionStack
    static let footerHorizontalPadding: CGFloat = GuardianSpacing.md
    static let footerVerticalPadding: CGFloat = GuardianSpacing.sm
    static let iconColumnWidth: CGFloat = 36
}

// MARK: - Kind (internal)

private enum GuardianConfirmChromeKind {
    case standard
    case danger
}

// MARK: - Shared shell

/// Single-surface confirmation: **header** (icon + optional headline on one row), **body** (message), **footer** (actions). Header, body, and footer share the same background; only the footer is separated by a horizontal hairline.
///
/// **Buttons:** ``GuardianConfirm`` uses Cancel (red outline) + Confirm (blue). ``GuardianConfirmDanger`` uses Cancel (neutral outline) + Confirm (red solid) — see ``footerStrip``.
private struct GuardianConfirmShell: View {
    let kind: GuardianConfirmChromeKind
    let title: String?
    let message: String
    let systemImage: String?
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var resolvedSymbol: String {
        if let s = systemImage?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        switch kind {
        case .standard: return "questionmark.circle.fill"
        case .danger: return "trash.fill"
        }
    }

    private var trimmedTitle: String? {
        guard let title else { return nil }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                if let headline = trimmedTitle {
                    HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                        headerIcon
                        Text(headline)
                            .font(GuardianTypography.Scale.title3.font(weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(message)
                        .font(GuardianTypography.font(.confirmBody))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                        headerIcon
                        Text(message)
                            .font(GuardianTypography.font(.confirmBody))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, GuardianConfirmLayout.contentHorizontalPadding)
            .padding(.top, GuardianConfirmLayout.contentTopPadding)
            .padding(.bottom, GuardianConfirmLayout.contentBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)

            footerStrip
        }
        .background {
            if kind == .danger {
                ZStack {
                    theme.backgroundRaised
                    GuardianSemanticColors.dangerBackground.opacity(colorScheme == .dark ? 0.52 : 0.72)
                }
            } else {
                theme.backgroundRaised
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: GuardianConfirmLayout.cornerRadius, style: .continuous))
        .overlay {
            if kind == .danger {
                RoundedRectangle(cornerRadius: GuardianConfirmLayout.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.dangerStroke, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch kind {
        case .standard:
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(GuardianSemanticColors.infoBackground.opacity(colorScheme == .dark ? 0.42 : 0.78))
                Image(systemName: resolvedSymbol)
                    .font(GuardianTypography.font(.confirmHeaderIconStandard))
                    .foregroundStyle(GuardianSemanticColors.infoForeground)
            }
            .frame(width: GuardianConfirmLayout.iconColumnWidth, height: GuardianConfirmLayout.iconColumnWidth)

        case .danger:
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(GuardianSemanticColors.dangerBackground.opacity(colorScheme == .dark ? 0.85 : 0.95))
                Image(systemName: resolvedSymbol)
                    .font(GuardianTypography.font(.confirmHeaderIconDanger))
                    .foregroundStyle(GuardianSemanticColors.dangerForeground)
            }
            .frame(width: GuardianConfirmLayout.iconColumnWidth, height: GuardianConfirmLayout.iconColumnWidth)
        }
    }

    private var footerStrip: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            HStack(spacing: GuardianSpacing.denseGutter) {
                switch kind {
                case .standard:
                    GuardianThemedButton(
                        title: cancelTitle,
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: onCancel
                    )
                    .keyboardShortcut(.cancelAction)
                    Spacer(minLength: GuardianSpacing.xs)
                    GuardianPrimaryProminentButton(title: confirmTitle, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                case .danger:
                    GuardianThemedButton(
                        title: cancelTitle,
                        accent: .neutral,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: onCancel
                    )
                    .keyboardShortcut(.cancelAction)
                    Spacer(minLength: GuardianSpacing.xs)
                    GuardianDestructiveProminentButton(title: confirmTitle, action: onConfirm)
                // Intentionally no `.defaultAction` on destructive confirm — see ``GuardianChromeInteraction`` (Theme §9.1).
                }
            }
            .padding(.horizontal, GuardianConfirmLayout.footerHorizontalPadding)
            .padding(.vertical, GuardianConfirmLayout.footerVerticalPadding)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Public confirms

/// Standard confirmation — one raised surface, icon + title on the first row when a title is supplied; message only beside the icon when `title` is nil. Footer: Cancel (red outline) + Confirm (blue) — app-wide defaults for non-destructive confirms.
struct GuardianConfirm: View {
    private let title: String?
    private let message: String
    private let systemImage: String?
    private let cancelTitle: String
    private let confirmTitle: String
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    init(
        title: String? = nil,
        message: String,
        systemImage: String? = nil,
        cancelTitle: String = "Cancel",
        confirmTitle: String = "Confirm",
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.cancelTitle = cancelTitle
        self.confirmTitle = confirmTitle
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        GuardianConfirmShell(
            kind: .standard,
            title: title,
            message: message,
            systemImage: systemImage,
            cancelTitle: cancelTitle,
            confirmTitle: confirmTitle,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }
}

/// Destructive / deletion confirmation — **red-tinted panel** and **red border** so it reads immediately as “this is about removing something.” Footer actions invert from ``GuardianConfirm``: **back out** is neutral outline (left); **proceed** is red solid (right).
struct GuardianConfirmDanger: View {
    private let title: String?
    private let message: String
    private let systemImage: String?
    private let cancelTitle: String
    private let confirmTitle: String
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    init(
        title: String? = nil,
        message: String,
        systemImage: String? = nil,
        cancelTitle: String = "Cancel",
        confirmTitle: String = "Confirm",
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.cancelTitle = cancelTitle
        self.confirmTitle = confirmTitle
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        GuardianConfirmShell(
            kind: .danger,
            title: title,
            message: message,
            systemImage: systemImage,
            cancelTitle: cancelTitle,
            confirmTitle: confirmTitle,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }
}

