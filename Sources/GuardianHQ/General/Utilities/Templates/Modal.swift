import SwiftUI

// MARK: - Layout tokens (single source — do not copy into screens)

/// Padding and rhythm for ``Modal``. Use these from the Theme plugin docs and new sheets; do not invent parallel header/body metrics.
enum GuardianModalLayout {
    static let headerHorizontalPadding: CGFloat = GuardianSpacing.lg
    static let headerTopPadding: CGFloat = GuardianSpacing.md
    static let headerBottomPadding: CGFloat = GuardianSpacing.sm
    static let bodyPadding: CGFloat = GuardianSpacing.md
}

// MARK: - Header chrome

/// Mandatory hairline between the raised modal header and the body. **Always** shown by ``Modal``; do not add a second ``Divider`` directly under the header in ``bodyContent``.
struct GuardianModalHeaderSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Rectangle()
            .fill(theme.borderSubtle)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// Title row + raised strip (without the separator). Used by ``Modal`` and in-panel previews so header chrome cannot drift.
struct GuardianModalHeaderBar<HeaderActions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let headerActions: () -> HeaderActions

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: GuardianSpacing.xs)
            headerActions()
        }
        .padding(.horizontal, GuardianModalLayout.headerHorizontalPadding)
        .padding(.top, GuardianModalLayout.headerTopPadding)
        .padding(.bottom, GuardianModalLayout.headerBottomPadding)
        .frame(maxWidth: .infinity)
        .background(theme.backgroundRaised)
    }
}

// MARK: - Modal shell

/// Shared modal shell used across sheets and popovers.
///
/// **Chrome is owned here only:** ``GuardianModalHeaderBar`` (raised strip), exactly one ``GuardianModalHeaderSeparator``, then padded body on ``GuardianThemePalette/backgroundBase``.
/// Do not add competing top borders or ``Divider``s immediately under the header inside ``bodyContent`` — use internal spacing only.
struct Modal<BodyContent: View, HeaderActions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let headerActions: () -> HeaderActions
    @ViewBuilder let bodyContent: () -> BodyContent
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder headerActions: @escaping () -> HeaderActions,
        @ViewBuilder bodyContent: @escaping () -> BodyContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerActions = headerActions
        self.bodyContent = bodyContent
    }

    var body: some View {
        VStack(spacing: 0) {
            GuardianModalHeaderBar(title: title, subtitle: subtitle, headerActions: headerActions)
            GuardianModalHeaderSeparator()

            bodyContent()
                .padding(GuardianModalLayout.bodyPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(theme.backgroundBase)
        .clipShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
        .guardianDropShadow(GuardianElevation.inspectorPanel)
    }
}
