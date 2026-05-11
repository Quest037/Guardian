import Charts
import SwiftUI

/// Full design-system catalog for the Theme plugin (Guardian tokens + ``GuardianUIChrome`` + Swift Charts samples).
///
/// **Checklist (Theme §14.2):** each new token or chrome type represented here should include a short usage blurb,
/// controls or swatches where helpful, ``ThemeAPICaption`` API names, and a quick **light + dark** visual pass (CI
/// screenshots optional later). See ``ThemePanelView`` for the same checklist at the plugin entry point.
///
/// Layout depth is intentionally inspired by component documentation sites such as
/// [Star HTML Pro](https://preview.keenthemes.com/html/star-html-pro/docs/?page=index); implementation is native SwiftUI.
struct ThemeCatalogContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var appDrawer: AppDrawer

    @State private var catalogSegment = 0
    @State private var docLayoutTab = 0
    @State private var searchDemoQuery = ""
    @State private var accordionExpanded = true
    @State private var showCatalogPopover = false
    @State private var sampleText = "guardian.local"
    @State private var sampleSecret = "secret"
    @State private var toggleOn = true
    @State private var stepperValue = 2
    @State private var sliderValue = 0.42
    @State private var menuPick = "TCP"
    @State private var showSampleSheet = false

    @State private var fleetTableRows: [ThemeFleetTableRow] = ThemeFleetTableRow.samples
    @State private var catalogInspectorRowPick = 0
    @State private var catalogFocusRingDemo = false

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: GuardianSpacing.stackMajor) {
                heroSection
                layoutTokensSection
                surfaceElevationSection
                shadowTokensSection
                motionTokensSection
                spacingAndRadiusSection
                typographySection
                modalShellSection
                confirmDialogsSection
                overlayScrimAndAppDrawerSection
                windowChromeStackSection
                guardianCardCatalogSection
                semanticColorsSection
                dataVisualizationSection
                badgeMatrixSection
                buttonMatrixSection
                docTabsSection
                formControlsSection
                menusPopoversSection
                disclosureAccordionSection
                listAndDisclosureSection
                shellStatesSection
                accessibilitySection
                inlineNoticesSection
                toastSection
                progressSection
                breadcrumbSection
                tableSection
                iconographySizeGridSection
                iconGridSection
                searchMetricsAndStripSection
                subBarSection
                productionReferenceSection
            }
            .padding(GuardianSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundBase)
        .sheet(isPresented: $showSampleSheet) {
            Modal(
                title: "Sample sheet",
                subtitle: "Uses ``Modal`` only — one ``GuardianModalHeaderSeparator``; no extra header ``Divider`` in the body.",
                headerActions: {
                    HStack(spacing: GuardianSpacing.xs) {
                        GuardianThemedButton(
                            title: "Cancel",
                            accent: .danger,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            action: { showSampleSheet = false }
                        )
                        GuardianPrimaryProminentButton(title: "Done") { showSampleSheet = false }
                    }
                },
                bodyContent: {
                    VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                        Text("Body uses ``GuardianModalLayout/bodyPadding`` from the shell; do not draw another rule line under the title row.")
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                        GuardianInlineNotice(
                            kind: .informational,
                            title: "Tip",
                            detail: "Pair confirm actions with ``GuardianPrimaryProminentButton`` (blue) and dismiss-only cancel with red outline ``GuardianThemedButton`` per workspace rules."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
            .frame(minWidth: 440, minHeight: 260)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Theme & UI chrome")
            Text(
                "Guardian’s UI theme is tokenized: pick a ``GuardianThemeAccent``, a size, a shape, and a surface (solid / light / outline for badges; "
                    + "solid / outline for buttons). Domain names like “mission phase” are **not** part of the theme — they are just one application of these tokens."
            )
            .font(GuardianTypography.font(.denseCaption12Regular))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                Link(
                    "Star HTML Pro docs (reference)",
                    destination: URL(string: "https://preview.keenthemes.com/html/star-html-pro/docs/?page=index")!
                )
                .font(GuardianTypography.font(.inlineNoticeTitle))

                Link(
                    "Badges reference",
                    destination: URL(string: "https://preview.keenthemes.com/html/star-html-pro/docs/?page=base/badges")!
                )
                .font(GuardianTypography.font(.inlineNoticeTitle))
            }

            ThemeAPICaption("Entry: ThemePanelView → ThemeCatalogContent")
        }
    }

    // MARK: - Layout tokens

    private var layoutTokensSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Layout rhythm (example constants)")
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                Text(
                    "Spacing is not part of the color theme, but screens should pull from shared layout enums when they exist — e.g. Mission Control prep uses "
                        + "``MissionRunPrepLayout/setupScrollPaddingH`` / ``setupScrollPaddingV`` (10pt) so dense chrome stays consistent."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: GuardianSpacing.denseGutter) {
                    layoutTokenChip("setupScrollPaddingH", "\(Int(MissionRunPrepLayout.setupScrollPaddingH))pt")
                    layoutTokenChip("setupBlockSpacing", "\(Int(MissionRunPrepLayout.setupBlockSpacing))pt")
                    layoutTokenChip("rosterSlotCornerRadius", "\(Int(MissionRunPrepLayout.rosterSlotCornerRadius))pt")
                }
                Text("This catalog uses 20pt outer padding on the scroll content; match product screens to their owning layout enum, not arbitrary magic numbers.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
            }
            .guardianInsetCard()
            ThemeAPICaption("MissionRunPrepLayout")
        }
    }

    /// Solid accent preview for catalog swatches (matches ``GuardianThemeAccentStyle`` hues).
    private func accentPreviewColor(_ accent: GuardianThemeAccent) -> Color {
        switch accent {
        case .primary: .blue
        case .success: GuardianSemanticColors.successStroke
        case .warning: GuardianSemanticColors.warningStroke
        case .info: GuardianSemanticColors.infoForeground
        case .danger: GuardianSemanticColors.dangerForeground
        case .neutral: theme.textTertiary
        case .secondary: theme.textSecondary
        case .teal: Color(red: 0.12, green: 0.62, blue: 0.58)
        case .purple: GuardianBrand.purple
        case .pink: Color(red: 0.92, green: 0.28, blue: 0.52)
        case .yellow: Color(red: 0.85, green: 0.72, blue: 0.08)
        }
    }

    private func layoutTokenChip(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
            Text(name)
                .font(GuardianTypography.relativeFixed(size: 8, weight: .semibold, design: .monospaced, relativeTo: .caption2))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(2)
            Text(value)
                .font(GuardianTypography.relativeFixed(size: 12, weight: .bold, design: .rounded, relativeTo: .caption))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(GuardianSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Doc-style tabs

    private var docTabsSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Tabs & segmented shells")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text(
                    "Documentation sites (e.g. Keen’s component index) stack a segmented control above swapped content. "
                        + "Use the same pattern for inspector modes; reserve ``TabView`` for true multi-page flows."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Picker("", selection: $docLayoutTab) {
                    Text("Overview").tag(0)
                    Text("Controls").tag(1)
                    Text("Data").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Group {
                    switch docLayoutTab {
                    case 0:
                        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                            Text("Overview pane")
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                            GuardianInlineNotice(
                                kind: .informational,
                                title: "Pattern",
                                detail: "Segmented header + one lazy body keeps scroll performance predictable in wide panels."
                            )
                        }
                    case 1:
                        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                            Toggle("Simulate fleet uplink", isOn: $toggleOn)
                                .controlSize(.small)
                            Stepper("Sample stepper: \(stepperValue)", value: $stepperValue, in: 0...5)
                        }
                    default:
                        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                            Text("Theme accents (swatches)")
                                .font(GuardianTypography.font(.inlineNoticeTitle))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: GuardianSpacing.xs)], alignment: .leading, spacing: GuardianSpacing.xs) {
                                ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                                    VStack(spacing: GuardianSpacing.xxs) {
                                        Circle()
                                            .fill(accentPreviewColor(accent))
                                            .frame(width: 24, height: 24)
                                            .overlay(Circle().strokeBorder(theme.borderSubtle, lineWidth: 1))
                                        Text(accent.label)
                                            .font(GuardianTypography.relativeFixed(size: 8, weight: .medium, design: .monospaced, relativeTo: .caption2))
                                            .foregroundStyle(theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, GuardianSpacing.xxs)
            }
            .guardianInsetCard()
            ThemeAPICaption("Picker · .pickerStyle(.segmented)")
        }
    }

    // MARK: - Menus & popovers

    private var menusPopoversSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Menus, context menus, popovers")
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                ThemeCatalogSubheading("Menu (bordered, small)")
                Menu {
                    Button("Duplicate run") {}
                    Button("Export manifest…") {}
                    Divider()
                    Button("Archive") {}
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .guardianPointerOnHover()

                ThemeCatalogSubheading("Context menu on bordered button")
                Button("Right-click or long-press") {}
                    .buttonStyle(.bordered).guardianPointerOnHover()
                    .tint(.blue)
                    .controlSize(.small)
                    .contextMenu {
                        Button("Copy token") {}
                        Button("Reveal in Finder") {}
                    }

                ThemeCatalogSubheading("Popover (local inspector)")
                Button("Show popover") { showCatalogPopover.toggle() }
                    .buttonStyle(.bordered).guardianPointerOnHover()
                    .controlSize(.small)
                    .popover(isPresented: $showCatalogPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                            Text("Popover body")
                                .font(GuardianTypography.font(.inlineNoticeTitle))
                            Text("Use for lightweight field help; use ``Modal`` or ``AppDrawer`` for heavy flows.")
                                .font(GuardianTypography.font(.denseFootnoteRegular))
                                .foregroundStyle(.secondary)
                                .frame(width: 240)
                        }
                        .padding(GuardianSpacing.sm)
                    }
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Disclosure / accordion

    private var disclosureAccordionSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Accordion (DisclosureGroup)")
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                DisclosureGroup(isExpanded: $accordionExpanded) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text("Nested settings or grouped telemetry fields belong behind a disclosure so the default surface stays calm.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                        GuardianLabeledFormField(label: "Nested field") {
                            TextField("value", text: $sampleText)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, GuardianSpacing.xsTight)
                } label: {
                    Text("Advanced routing")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("DisclosureGroup")
        }
    }

    // MARK: - Search, metrics, elevated strip

    private var searchMetricsAndStripSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Search, KPI tiles, elevated strip")
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                GuardianLabeledFormField(label: "GuardianSearchBarField") {
                    GuardianSearchBarField(text: $searchDemoQuery, placeholder: "Filter vehicles, missions…")
                }
                HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                    GuardianMetricTile(title: "Live", value: "12", caption: "Fleet roster")
                    GuardianMetricTile(title: "Sims", value: "3", caption: "SitL instances")
                    GuardianMetricTile(title: "Alerts", value: "0", caption: "Last 24h")
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("GuardianSearchBarField · GuardianMetricTile")
        }
    }

    // MARK: - Overlay scrim & AppDrawer

    private var overlayScrimAndAppDrawerSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "App drawer (trailing panel)")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text(
                    "App-wide drawers use AppDrawer and View.withAppDrawer() on the window root above the entire RootView "
                        + "(sidebar, top bar, and content-column toasts). This is not the main navigation sidebar in RootView. "
                        + "Do not hand-roll ZStack scrims and transition(.move(edge:)) for the same trailing-panel pattern. "
                        + "When present(title:) supplies a title, the host uses AppDrawerChrome (below); use title: nil only when your content already includes a full custom header."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("Visual replica (matches the live AppDrawer host — not a rounded card)")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textPrimary)

                Text(
                    "Live host: trailing `HStack` + panel `frame(width:)` · `backgroundElevated` on the **whole** panel · leading 1pt `borderSubtle` line · square trailing edge to the window. "
                        + "Preview uses a short strip; widths clamp 260–560 (default 380)."
                )
                .font(GuardianTypography.font(.denseCaption10Regular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

                ThemeAppDrawerHostVisualReplica()
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                        Text("overlayScrim (light)")
                            .font(GuardianTypography.font(.denseCaption10Semibold))
                            .foregroundStyle(theme.textTertiary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(GuardianTheme.palette(for: .light).overlayScrim)
                            .frame(width: 72, height: 44)
                            .overlay(
                                Text("Aa")
                                    .font(GuardianTypography.relativeFixed(size: 11, weight: .bold, relativeTo: .footnote))
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                    }
                    VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                        Text("overlayScrim (dark)")
                            .font(GuardianTypography.font(.denseCaption10Semibold))
                            .foregroundStyle(theme.textTertiary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(GuardianTheme.palette(for: .dark).overlayScrim)
                            .frame(width: 72, height: 44)
                            .overlay(
                                Text("Aa")
                                    .font(GuardianTypography.relativeFixed(size: 11, weight: .bold, relativeTo: .footnote))
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                    }
                }

                GuardianPrimaryProminentButton(title: "Present sample AppDrawer") {
                    appDrawer.present(title: "Sample drawer", preferredWidth: 360, scrimTapDismisses: true) {
                        VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                            Text("This drawer uses the shared overlay host: scrim tap dismisses when enabled.")
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(GuardianTheme.palette(for: colorScheme).textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            GuardianDestructiveProminentButton(title: "Dismiss") {
                                appDrawer.dismiss()
                            }
                        }
                        .padding(GuardianSpacing.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("AppDrawer · AppDrawerChrome · GuardianThemePalette/overlayScrim")
        }
    }

    // MARK: - Window chrome stack (Theme 12)

    private var windowChromeStackSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Window chrome stack (Theme 12.1)")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text(
                    "Modifier order on the window root matches GuardianHQApp: RootView, then withAppDrawer(), then withGuardianConfirmOverlayHost(). "
                        + "Toasts attach inside RootView on the main content column only."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("Back → front (same window)")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textPrimary)

                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    chromeStackRow(depth: "1", label: "RootView — nav rail, top bar, feature content")
                    chromeStackRow(depth: "2", label: "Toasts — content column only (ToastHost)")
                    chromeStackRow(depth: "3", label: "AppDrawer — full-window scrim + trailing panel")
                    chromeStackRow(depth: "4", label: "Blocking confirm — GuardianConfirmOverlayHost over everything")
                }
                .padding(GuardianSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
            }
            .guardianInsetCard()

            GuardianPanelSectionTitle(title: "Split view and inspectors (Theme 12.2)")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text(
                    "The app shell is a fixed-width navigation rail plus flexible content. Add list, detail, or inspector columns inside the content region (NavigationSplitView or HSplitView) instead of widening the rail."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "When tightening windows: collapse optional inspectors before shrinking the primary canvas. "
                        + "Suggested bands — primary canvas at least \(Int(GuardianLayoutPatterns.InspectorRails.recommendedMinimumPrimaryCanvasWidth)) pt when possible; "
                        + "inspector column \(Int(GuardianLayoutPatterns.InspectorRails.recommendedInspectorPreferredWidthRange.lowerBound))–\(Int(GuardianLayoutPatterns.InspectorRails.recommendedInspectorPreferredWidthRange.upperBound)) pt as a starting range."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianLayoutPatterns · GuardianFeedbackSeverity")
        }
    }

    private func chromeStackRow(depth: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
            Text(depth)
                .font(GuardianTypography.font(.telemetryMono11Semibold))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 20, alignment: .leading)
            Text(label)
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textPrimary)
        }
    }

    // MARK: - GuardianCard (Bootstrap-style)

    private var guardianCardCatalogSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "GuardianCard (Bootstrap-style panel)")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                guardianCardCatalogDescription
                guardianCardCatalogBodyOnlyRow
                guardianCardCatalogHeaderBodySample
                guardianCardCatalogBodyFooterSample
                guardianCardCatalogFullStackSample
                guardianCardCatalogMediaBodyRow
                guardianCardCatalogLegacyInsetRow
                ThemeAPICaption(
                    "GuardianCard · GuardianCardConfiguration · GuardianCardBorder · GuardianCardSections · GuardianCardLayout · guardianInsetCard()"
                )
            }
            .guardianInsetCard()
        }
    }

    private var guardianCardCatalogDescription: some View {
        Text(
            "Central card template: optional media (flush top), header, body, and footer; hairlines between slots; ``GuardianThemePalette`` fill + border accents. "
                + "When media sits above another slot, its bottom corners are square so it meets header/body/footer cleanly; media-only cards keep full corner radius. "
                + "Default border is subtle; use GuardianCardBorder.none to omit the outer stroke. "
                + "Set ``GuardianCardConfiguration/bodyPadding`` to 0 for map-style bodies. "
                + "Optional ``fullCardOverlay`` draws above every slot (including the header) inside the same clip and border. "
                + "``guardianInsetCard()`` remains for legacy panels; new work should prefer ``GuardianCard``."
        )
        .font(GuardianTypography.font(.denseCaption12Regular))
        .foregroundStyle(theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var guardianCardCatalogBodyOnlyRow: some View {
        HStack(alignment: .top, spacing: GuardianSpacing.sm) {
            GuardianCard(
                configuration: GuardianCardConfiguration(border: .subtle, bodyPadding: GuardianSpacing.cardBodyInset),
                body: {
                    Text("Body only · default subtle border + padded body.")
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                }
            )
            .frame(maxWidth: .infinity)

            GuardianCard(
                configuration: GuardianCardConfiguration(border: .none, bodyPadding: GuardianSpacing.cardBodyInset),
                body: {
                    Text("Border none — still raised fill; no outer stroke.")
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var guardianCardCatalogHeaderBodySample: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(border: .primary, bodyPadding: GuardianSpacing.sm),
            header: {
                Text("With header strip")
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textPrimary)
            },
            body: {
                Text("Header uses elevated strip; hairline separates header and body.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
            }
        )
    }

    private var guardianCardCatalogBodyFooterSample: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(border: .subtle, bodyPadding: GuardianSpacing.sm),
            body: {
                Text("Body content with default padding.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
            },
            footer: {
                Text("Footer strip · elevated background")
                    .font(GuardianTypography.font(.inlineNoticeDetail))
                    .foregroundStyle(theme.textTertiary)
            }
        )
    }

    private var guardianCardCatalogFullStackSample: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .danger,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.sm
            ),
            sections: [.media, .header, .body, .footer],
            media: {
                LinearGradient(
                    colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 64)
                .overlay {
                    Text("Media slot (full width, flush)")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textPrimary)
                }
            },
            header: {
                Text("Full stack")
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textPrimary)
            },
            body: {
                Text("Media + header + body + footer. Outer border uses semantic danger stroke for this sample.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
            },
            footer: {
                HStack {
                    Text("Footer actions row")
                        .font(GuardianTypography.font(.inlineNoticeDetail))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                    GuardianPrimaryProminentButton(title: "OK") {}
                }
            },
            fullCardOverlay: { EmptyView() }
        )
    }

    private var guardianCardCatalogMediaBodyRow: some View {
        HStack(alignment: .top, spacing: GuardianSpacing.sm) {
            GuardianCard(
                configuration: GuardianCardConfiguration(border: .warning, bodyPadding: 0),
                media: {
                    ZStack {
                        theme.backgroundElevated
                        Text("Media + body · bodyPadding 0 (map-style)")
                            .font(GuardianTypography.font(.inlineNoticeTitle))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .frame(height: 88)
                },
                body: {
                    Text("Body is edge-to-edge under the media hairline — no inner padding.")
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .padding(GuardianSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
            .frame(maxWidth: .infinity)

            GuardianCard(
                configuration: GuardianCardConfiguration(border: .subtle, cornerRadius: GuardianCardLayout.cornerRadius),
                media: {
                    LinearGradient(
                        colors: [Color.teal.opacity(0.45), Color.indigo.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay {
                        Text("Media only · rounded on all sides")
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(GuardianSpacing.xs)
                    }
                    .frame(height: 120)
                }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var guardianCardCatalogLegacyInsetRow: some View {
        HStack(alignment: .top, spacing: GuardianSpacing.sm) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                Text("Legacy inset helper")
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)
                Text("``guardianInsetCard()`` uses ``GuardianThemePalette`` (raised + ``borderSubtle``); prefer ``GuardianCard`` when adding header/footer/media.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCard()
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                Text("Compact inset")
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)
                Text("``guardianInsetCardCompact()``")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCardCompact()
        }
    }

    // MARK: - Surfaces

    private var surfaceElevationSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Surfaces & elevation")
            Text("``GuardianThemePalette`` maps the four-layer stack used across HQ: base window, raised panels, elevated strips, and active/pressed chrome.")
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: GuardianSpacing.denseGutter) {
                ForEach(GuardianSurfaceLevel.allCases, id: \.self) { level in
                    surfaceRow(level.catalogLabel, level.fill(from: theme), theme.textPrimary)
                }
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianSurfaceLevel · GuardianTheme.palette(for:) · guardianInsetCard() uses backgroundRaised + borderSubtle")
        }
    }

    private var shadowTokensSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Elevation shadows")
            Text(
                "``GuardianElevation`` defines drop-shadow recipes. **feedbackChrome** is intentionally identical for ephemeral toasts, bottom prompt banners, and ``GuardianInlineNotice`` so severity reads consistently across channels."
            )
            .font(GuardianTypography.font(.denseCaption12Regular))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                shadowTokenRow(name: "overlayPanel", spec: GuardianElevation.overlayPanel, caption: "Window-level confirm / modal stack")
                shadowTokenRow(name: "inspectorPanel", spec: GuardianElevation.inspectorPanel, caption: "Vehicle Inspector and similar heavy floaters")
                shadowTokenRow(name: "feedbackChrome", spec: GuardianElevation.feedbackChrome, caption: "ToastHost · GuardianBottomPromptBanner · GuardianInlineNotice")
                shadowTokenRow(name: "mapToolbarBezel", spec: GuardianElevation.mapToolbarBezel, caption: "Map WebView toolbar bezel")
                shadowTokenRow(name: "raisedCard", spec: GuardianElevation.raisedCard, caption: "Optional card depth (unused by GuardianCard default)")
                shadowTokenRow(name: "raisedPopover", spec: GuardianElevation.raisedPopover, caption: "Popover / anchored panel")
            }
            .guardianInsetCard()

            ThemeAPICaption("View.guardianDropShadow(_:)")
        }
    }

    private var motionTokensSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Motion (`GuardianMotion`)")
            Text(
                "Durations and preset **ease** animations for window chrome (confirms, drawers, sidebar, toasts, bottom prompts). Springs stay on in-screen mechanics (e.g. Mission workspace sidecars), not global overlays."
            )
            .font(GuardianTypography.font(.denseCaption12Regular))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                motionTokenRow(
                    name: "confirmPulseSeconds",
                    value: String(format: "%.2f", GuardianMotion.confirmPulseSeconds),
                    caption: "GuardianConfirmOverlayHost · easeOut"
                )
                motionTokenRow(
                    name: "feedbackMicroInteractionSeconds",
                    value: String(format: "%.2f", GuardianMotion.feedbackMicroInteractionSeconds),
                    caption: "ToastCenter · GuardianBottomPromptCenter · easeInOut"
                )
                motionTokenRow(
                    name: "chromeDrawerSeconds",
                    value: String(format: "%.2f", GuardianMotion.chromeDrawerSeconds),
                    caption: "AppDrawer · RootView sidebar · Live Drive sidebars"
                )
                motionTokenRow(
                    name: "shellTransitionSeconds",
                    value: String(format: "%.2f", GuardianMotion.shellTransitionSeconds),
                    caption: "GuardianHQApp splash → main"
                )
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianMotion")
        }
    }

    private func motionTokenRow(name: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
                Text(name)
                    .font(GuardianTypography.font(.telemetryMono11Semibold))
                    .foregroundStyle(theme.textSecondary)
                Text("\(value)s")
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            Text(caption)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shadowTokenRow(name: String, spec: GuardianElevation.DropShadow, caption: String) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                Text(name)
                    .font(GuardianTypography.font(.telemetryMono11Semibold))
                    .foregroundStyle(theme.textSecondary)
                Text(caption)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundRaised)
                .frame(width: 76, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
                .guardianDropShadow(spec)
        }
    }

    private func surfaceRow(_ name: String, _ color: Color, _ labelColor: Color) -> some View {
        HStack {
            Text(name)
                .font(GuardianTypography.font(.telemetryMono11Semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: GuardianSpacing.xs)
            Text("Aa")
                .font(GuardianTypography.font(.missionRowKicker12Bold))
                .foregroundStyle(labelColor)
                .padding(.horizontal, GuardianSpacing.denseGutter)
                .padding(.vertical, GuardianSpacing.xsTight)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
        }
    }

    // MARK: - Spacing

    private var spacingAndRadiusSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Spacing & corner radii")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                ThemeCatalogSubheading("GuardianSpacing · 4pt grid + semantics")
                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    ForEach(GuardianSpacingCatalogStep.samples, id: \.name) { row in
                        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
                            Text(row.name)
                                .font(GuardianTypography.font(.telemetryMono11Regular))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 44, alignment: .leading)
                            Text("\(Int(row.value)) pt")
                                .font(GuardianTypography.font(.denseCaption10Semibold))
                                .foregroundStyle(theme.textTertiary)
                                .frame(width: 40, alignment: .trailing)
                            Rectangle()
                                .fill(GuardianBrand.purple.opacity(0.55))
                                .frame(width: row.value, height: 14)
                        }
                    }
                }
                Text(
                    "Semantics: denseGutter (scroll edges), cardBodyInset (matches GuardianCard default body padding), sectionStack (major vertical gaps). Mission Control setup prep uses MissionRunPrepLayout as aliases into these tokens."
                )
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ThemeCatalogSubheading("Common horizontal rhythm (legacy swatch)")
                HStack(spacing: 0) {
                    ForEach([4, 8, 10, 12, 16, 20], id: \.self) { step in
                        VStack(spacing: GuardianSpacing.xxs) {
                            Text("\(step)")
                                .font(GuardianTypography.relativeFixed(size: 9, weight: .bold, design: .monospaced, relativeTo: .caption2))
                                .foregroundStyle(theme.textTertiary)
                            Rectangle()
                                .fill(GuardianBrand.purple.opacity(0.55))
                                .frame(width: CGFloat(step), height: 18)
                        }
                        if step != 20 {
                            Spacer(minLength: GuardianSpacing.xsTight)
                        }
                    }
                }
                ThemeCatalogSubheading("Inset card radius (10pt continuous)")
                HStack(spacing: GuardianSpacing.sm) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 2)
                        .frame(width: 56, height: 40)
                        .overlay(Text("10").font(GuardianTypography.font(.denseCaption10Semibold)).foregroundStyle(theme.textTertiary))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 2)
                        .frame(width: 56, height: 40)
                        .overlay(Text("8").font(GuardianTypography.font(.denseCaption10Semibold)).foregroundStyle(theme.textTertiary))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 2)
                        .frame(width: 56, height: 40)
                        .overlay(Text("5 chip").font(GuardianTypography.font(.telemetryNano9Semibold)).foregroundStyle(theme.textTertiary))
                }
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Typography scale")
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                ThemeCatalogSubheading("Scale · GuardianTypography.Scale")
                ForEach(GuardianTypography.Scale.allCases, id: \.self) { scale in
                    ThemeCatalogTypographyScaleRow(scale: scale)
                }
                ThemeCatalogSubheading("Semantic roles · GuardianTypography.Role")
                Group {
                    Text("Operator body — primary readable copy.")
                        .font(GuardianTypography.font(.operatorBody))
                        .foregroundStyle(theme.textPrimary)
                    Text("Operator caption — secondary dense copy.")
                        .font(GuardianTypography.font(.operatorCaption))
                        .foregroundStyle(theme.textSecondary)
                    Text("Inspector label")
                        .font(GuardianTypography.font(.inspectorLabel))
                        .foregroundStyle(theme.textPrimary)
                    Text("LOG SYS · 0x7F3A · 120.0m")
                        .font(GuardianTypography.font(.logLineMonospaced))
                        .foregroundStyle(theme.textTertiary)
                    Text("Confirm / inline notice detail style")
                        .font(GuardianTypography.font(.confirmBody))
                        .foregroundStyle(theme.textSecondary)
                }
                ThemeAPICaption("GuardianTypography.swift · Dynamic Type via text styles + relative caps; monospaced for codes / telemetry.")
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Semantic colors

    private var semanticColorsSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Semantic accents")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                HStack(spacing: GuardianSpacing.denseGutter) {
                    semanticSwatch("Success", GuardianSemanticColors.successForeground, GuardianSemanticColors.successBackground)
                    semanticSwatch("Warning", GuardianSemanticColors.warningForeground, GuardianSemanticColors.warningBackground)
                    semanticSwatch("Danger", GuardianSemanticColors.dangerForeground, GuardianSemanticColors.dangerBackground)
                    semanticSwatch("Info", GuardianSemanticColors.infoForeground, GuardianSemanticColors.infoBackground)
                }
                Divider().opacity(0.25)
                HStack(spacing: GuardianSpacing.denseGutter) {
                    semanticSwatch("Neutral badge", GuardianSemanticColors.neutralBadgeForeground, GuardianSemanticColors.neutralBadgeBackground)
                    semanticSwatch("Success stroke", GuardianSemanticColors.successStroke, GuardianSemanticColors.successBackground)
                    semanticSwatch("Warning stroke", GuardianSemanticColors.warningStroke, GuardianSemanticColors.warningBackground)
                }
                Divider().opacity(0.25)
                Text("Extended accents (also on ``GuardianThemeAccent``) — use for badges/buttons via the theme, not one-off colors.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: GuardianSpacing.denseGutter) {
                    semanticSwatch("Teal", accentPreviewColor(.teal), accentPreviewColor(.teal).opacity(0.2))
                    semanticSwatch("Purple", accentPreviewColor(.purple), accentPreviewColor(.purple).opacity(0.2))
                    semanticSwatch("Pink", accentPreviewColor(.pink), accentPreviewColor(.pink).opacity(0.2))
                    semanticSwatch("Yellow", accentPreviewColor(.yellow), accentPreviewColor(.yellow).opacity(0.25))
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("GuardianSemanticColors · GuardianThemeAccent")
        }
    }

    // MARK: - Data visualization (Theme 13)

    private var dataVisualizationSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Data visualization (Theme 13)")
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                ThemeCatalogSubheading("Swift Charts (import Charts)")
                Text(
                    "Apply guardianChartTheme(colorScheme:) for plot + axis chrome, then guardianChartSeriesForegroundScale() when using "
                        + "foregroundStyle(by:) with GuardianChartPalette.seriesDomainLabel(at:). Use guardianChartSeriesForegroundScale(colorblindSafe: true) for the alternate ramp."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ThemeCatalogSwiftChartsSample()
                    .frame(maxWidth: .infinity)

                ThemeCatalogSubheading("Chart series ramps (13.1)")
                Text(
                    "GuardianChartPalette.seriesColor(at:colorblindSafe:) matches the same ramps as chartForegroundStyleScale. "
                        + "Pair color with weight, dash, or markers for accessibility; the colorblind-safe ramp is a second fixed set, not a filter."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                dataVizSeriesRampRow(title: "Default ramp", colorblindSafe: false)
                dataVizSeriesRampRow(title: "Colorblind-safe ramp", colorblindSafe: true)

                ThemeCatalogSubheading("Gauge thresholds (13.2)")
                Text(
                    "Good is explicit: GuardianGaugeThresholds.goodBandFill and goodBandStroke. Caution and critical reuse "
                        + "GuardianSemanticColors warning and danger stroke families so limits match banners and notices."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                    dataVizGaugeStrip(label: "In range (good)", fill: GuardianGaugeThresholds.goodBandFill, stroke: GuardianGaugeThresholds.goodBandStroke, fraction: 0.72)
                    dataVizGaugeStrip(label: "Caution band", fill: GuardianGaugeThresholds.cautionFill, stroke: GuardianGaugeThresholds.cautionStroke, fraction: 0.88)
                    dataVizGaugeStrip(label: "Critical band", fill: GuardianGaugeThresholds.criticalFill, stroke: GuardianGaugeThresholds.criticalStroke, fraction: 0.98)
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("GuardianSwiftChartsTheme · GuardianChartPalette · GuardianGaugeThresholds")
        }
    }

    private func dataVizSeriesRampRow(title: String, colorblindSafe: Bool) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(title)
                .font(GuardianTypography.font(.denseCaption10Semibold))
                .foregroundStyle(theme.textTertiary)
            HStack(spacing: GuardianSpacing.sm) {
                ForEach(0..<GuardianChartPalette.seriesRampCount, id: \.self) { index in
                    Circle()
                        .fill(GuardianChartPalette.seriesColor(at: index, colorblindSafe: colorblindSafe))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(theme.borderSubtle, lineWidth: 1)
                        )
                }
            }
        }
    }

    private func dataVizGaugeStrip(label: String, fill: Color, stroke: Color, fraction: CGFloat) -> some View {
        let trackWidth: CGFloat = 280
        return VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text(label)
                .font(GuardianTypography.font(.denseCaption10Semibold))
                .foregroundStyle(theme.textSecondary)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.backgroundElevated)
                    .frame(width: trackWidth, height: 12)
                    .overlay(Capsule().strokeBorder(theme.borderSubtle, lineWidth: 1))
                Capsule()
                    .fill(fill)
                    .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
                    .frame(width: max(8, trackWidth * fraction), height: 12)
            }
            .frame(width: trackWidth, height: 12, alignment: .leading)
        }
    }

    private func semanticSwatch(_ label: String, _ fg: Color, _ bg: Color) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text(label)
                .font(GuardianTypography.font(.denseCaption10Semibold))
                .foregroundStyle(fg)
            RoundedRectangle(cornerRadius: 6)
                .fill(bg)
                .frame(width: 72, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(fg.opacity(0.35), lineWidth: 1)
                )
        }
    }

    // MARK: - Badges

    private var badgeMatrixSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Badges (theme matrix)")
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                Text(
                    "Pick ``GuardianThemeAccent`` × ``GuardianBadgePaint`` (solid / light / outline) × ``GuardianBadgeSize`` (small / medium / large) × "
                        + "``GuardianBadgeShape`` (pill / cornered / square / circle). Same vocabulary as a CSS theme layer."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                Link(
                    "KeenThemes badge reference (inspiration)",
                    destination: URL(string: "https://preview.keenthemes.com/html/star-html-pro/docs/?page=base/badges")!
                )
                .font(GuardianTypography.font(.inlineNoticeTitle))
            }

            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                ThemeCatalogSubheading("Solid · pill · medium · all accents")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: GuardianSpacing.xs)], alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianBadge(text: accent.label, accent: accent, paint: .solid, size: .medium, shape: .pill)
                    }
                }

                ThemeCatalogSubheading("Light · pill · medium")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: GuardianSpacing.xs)], alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianBadge(text: accent.label, accent: accent, paint: .light, size: .medium, shape: .pill)
                    }
                }

                ThemeCatalogSubheading("Outline · cornered · medium")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: GuardianSpacing.xs)], alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianBadge(text: accent.label, accent: accent, paint: .outline, size: .medium, shape: .cornered)
                    }
                }

                ThemeCatalogSubheading("Shapes · primary · solid · medium")
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianBadge(text: "Pill", accent: .primary, paint: .solid, size: .medium, shape: .pill)
                    GuardianBadge(text: "Cornered", accent: .primary, paint: .solid, size: .medium, shape: .cornered)
                    GuardianBadge(text: "Sq", accent: .primary, paint: .solid, size: .medium, shape: .square)
                    GuardianBadge(text: "3", accent: .primary, paint: .solid, size: .medium, shape: .circle)
                }

                ThemeCatalogSubheading("Sizes · success · solid · pill")
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianBadge(text: "SM", accent: .success, paint: .solid, size: .small, shape: .pill)
                    GuardianBadge(text: "MD", accent: .success, paint: .solid, size: .medium, shape: .pill)
                    GuardianBadge(text: "LG", accent: .success, paint: .solid, size: .large, shape: .pill)
                }
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianBadge · GuardianThemeAccent · GuardianBadgePaint · GuardianBadgeSize · GuardianBadgeShape")
        }
    }

    // MARK: - Buttons

    private var buttonMatrixSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Buttons (theme matrix)")
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                Text(
                    "Use ``GuardianThemedButton`` with ``GuardianThemeAccent``, ``GuardianChromeSurface`` (solid / outline), ``GuardianChromeSize``, and ``GuardianChromeShape``. "
                        + "``GuardianPrimaryProminentButton`` / ``GuardianDestructiveProminentButton`` are thin wrappers for the common save / delete cases."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ThemeCatalogSubheading("Shapes · solid · primary · small")
                HStack(spacing: GuardianSpacing.denseGutter) {
                    GuardianThemedButton(title: "Square", accent: .primary, surface: .solid, size: .small, shape: .square, action: {})
                    GuardianThemedButton(title: "Cornered", accent: .primary, surface: .solid, size: .small, shape: .cornered, action: {})
                    GuardianThemedButton(title: "Pill", accent: .primary, surface: .solid, size: .small, shape: .pill, action: {})
                }

                ThemeCatalogSubheading("Sizes · cornered · info · solid")
                HStack(spacing: GuardianSpacing.denseGutter) {
                    GuardianThemedButton(title: "Small", accent: .info, surface: .solid, size: .small, shape: .cornered, action: {})
                    GuardianThemedButton(title: "Medium", accent: .info, surface: .solid, size: .medium, shape: .cornered, action: {})
                    GuardianThemedButton(title: "Large", accent: .info, surface: .solid, size: .large, shape: .cornered, action: {})
                }

                ThemeCatalogSubheading("Accents · solid · cornered · small")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: GuardianSpacing.xs)], alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianThemedButton(
                            title: accent.label,
                            accent: accent,
                            surface: .solid,
                            size: .small,
                            shape: .cornered,
                            action: {}
                        )
                    }
                }

                ThemeCatalogSubheading("Outline · cornered · small (all accents)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: GuardianSpacing.xs)], alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianThemedButton(
                            title: accent.label,
                            accent: accent,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            action: {}
                        )
                    }
                }

                ThemeCatalogSubheading("Button group · GuardianThemedButtonStrip")
                GuardianThemedButtonStrip(
                    accent: .primary,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    items: [
                        ("Cut", {}),
                        ("Copy", {}),
                        ("Paste", {}),
                    ]
                )
                .frame(maxWidth: 360)

                ThemeCatalogSubheading("Solid strip · warning")
                GuardianThemedButtonStrip(
                    accent: .warning,
                    surface: .solid,
                    size: .small,
                    shape: .cornered,
                    items: [
                        ("One", {}),
                        ("Two", {}),
                    ]
                )
                .frame(maxWidth: 280)

                ThemeCatalogSubheading("Disabled · primary solid cornered")
                GuardianThemedButton(title: "Disabled", accent: .primary, surface: .solid, size: .small, shape: .cornered, isEnabled: false, action: {})

                ThemeCatalogSubheading("Workspace shortcuts (save / delete / neutral icon)")
                HStack(spacing: GuardianSpacing.denseGutter) {
                    GuardianPrimaryProminentButton(title: "Save") {}
                    GuardianDestructiveProminentButton(title: "Remove") {}
                    GuardianNeutralBorderedButton(systemImage: "gearshape", help: "Settings") {}
                }

                ThemeCatalogSubheading("Edit before delete (icon row rule)")
                GuardianEditThenDeleteIconRow(onEdit: {}, onDelete: {})
                Text("Edit uses the pencil icon with a blue tint; delete uses the trash icon with a red tint and appears after edit.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianThemedButton · GuardianThemedButtonStrip · GuardianChromeSurface · GuardianChromeSize · GuardianChromeShape")
        }
    }

    // MARK: - Forms

    private var formControlsSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Forms & pickers")
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                GuardianLabeledFormField(
                    label: "Hostname",
                    subtitle: "Optional subtitle sits under the label; use for hints that are not errors.",
                    error: sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Required" : nil
                ) {
                    TextField("hostname", text: $sampleText)
                        .textFieldStyle(.roundedBorder)
                        .guardianFormControlSizing()
                }

                GuardianLabeledFormField(label: "Secret") {
                    SecureField("secret", text: $sampleSecret)
                        .textFieldStyle(.roundedBorder)
                        .guardianFormControlSizing()
                }

                GuardianLabeledFormField(label: "Transport") {
                    Picker("Transport", selection: $menuPick) {
                        Text("TCP").tag("TCP")
                        Text("UDP").tag("UDP")
                        Text("Serial").tag("Serial")
                    }
                    .pickerStyle(.menu)
                    .guardianFormControlSizing()
                }

                GuardianLabeledSegmentedPicker(
                    label: "Segmented filter",
                    subtitle: "``GuardianLabeledSegmentedPicker`` — replaces ad-hoc label + segmented ``Picker`` stacks.",
                    selection: $catalogSegment,
                    options: [("All", 0), ("Live", 1), ("Sim", 2)],
                    maxSegmentedWidth: 360
                )

                Toggle("Enable Guardian Link", isOn: $toggleOn)
                    .controlSize(.small)

                Stepper("Retries: \(stepperValue)", value: $stepperValue, in: 0...5)

                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    Text("Throttle curve")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textSecondary)
                    Slider(value: $sliderValue, in: 0...1)
                }
            }
            .guardianInsetCard()

            ThemeAPICaption(
                "GuardianFormKit · GuardianLabeledFormField · GuardianLabeledSegmentedPicker · View.guardianFormControlSizing() · GuardianSearchBarField"
            )
        }
    }

    // MARK: - Lists

    private var listAndDisclosureSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Lists & disclosure rows")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                ThemeCatalogSubheading("GuardianSettingsRow (icon + value + chevron)")
                VStack(spacing: 0) {
                    GuardianSettingsRow(title: "Vehicle identity", systemImage: "airplane", value: "GXF-2044") {}
                    Divider().opacity(0.2)
                    GuardianSettingsRow(title: "Link bridge", systemImage: "link", value: "MAVLink 2") {}
                    Divider().opacity(0.2)
                    GuardianDisclosureSettingRow(title: "Danger zone", value: nil) {}
                }
                ThemeCatalogSubheading("GuardianSelectableListRow (custom stack)")
                VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                    Text("Use for inspector stacks; native `List(selection:)` + `listRowBackground` for table keyboard focus.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    GuardianSelectableListRow(isSelected: catalogInspectorRowPick == 0, action: { catalogInspectorRowPick = 0 }) {
                        Text("Primary rotorcraft slot")
                            .font(GuardianTypography.font(.disclosureRowTitle))
                            .foregroundStyle(theme.textPrimary)
                    }
                    GuardianSelectableListRow(isSelected: catalogInspectorRowPick == 1, action: { catalogInspectorRowPick = 1 }) {
                        Text("Reserve / wingman")
                            .font(GuardianTypography.font(.disclosureRowTitle))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
                ThemeCatalogSubheading("GuardianMonoLedgerRow (zebra + separators)")
                VStack(alignment: .leading, spacing: 0) {
                    GuardianMonoLedgerRow(caption: "GPS fix", value: "RTK fixed", zebra: false, showTopSeparator: false)
                    GuardianMonoLedgerRow(caption: "Battery", value: "87%", zebra: true)
                    GuardianMonoLedgerRow(caption: "RSSI", value: "-62 dBm", zebra: false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
                ThemeCatalogSubheading("Inset list (AppKit-style)")
                List {
                    Section("Fleet") {
                        Text("Rotorcraft · Live")
                        Text("Fixed-wing · Sim")
                    }
                    Section("Mission") {
                        Text("Survey · Draft")
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
            }
            .guardianInsetCard()

            ThemeAPICaption(
                "GuardianListKit · GuardianSettingsRow · GuardianDisclosureSettingRow · GuardianSelectableListRow · GuardianMonoLedgerRow · List + .listStyle(.inset(alternatesRowBackgrounds:))"
            )
        }
    }

    // MARK: - Shell states (empty / loading / blocking error)

    private var shellStatesSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Empty, loading & blocking errors")
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                ThemeCatalogSubheading("GuardianEmptyState (Vehicles tab reference)")
                GuardianEmptyState(
                    systemImage: "car.side",
                    title: "No Vehicles",
                    detail: "No vehicles currently linked.",
                    primaryTitle: "Add Sim",
                    primaryAction: {},
                    secondaryTitle: "Open Settings",
                    secondaryAction: {}
                )
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )

                ThemeCatalogSubheading("GuardianLoadingState")
                HStack(alignment: .top, spacing: GuardianSpacing.md) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text("Spinner")
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textSecondary)
                        GuardianLoadingState(style: .spinner(caption: "Fetching roster…"))
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .background(theme.backgroundElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text("Skeleton (card body)")
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textSecondary)
                        GuardianLoadingState(style: .skeleton(lineCount: 4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.backgroundElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                ThemeCatalogSubheading("GuardianInlineError vs GuardianInlineNotice.danger")
                GuardianInlineError(
                    title: "Link bridge failed",
                    message: "MAVSDK could not open the UDP socket. Check firewall rules and that no other process bound the port.",
                    retryTitle: "Retry",
                    onRetry: {}
                )
                GuardianInlineNotice(
                    kind: .danger,
                    title: "Danger notice",
                    detail: "Softer callout for recoverable risk; use GuardianInlineError when the pane cannot proceed until acknowledged."
                )
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianShellStates · GuardianEmptyState · GuardianLoadingState · GuardianInlineError")
        }
    }

    // MARK: - Accessibility & keyboard (Theme §9)

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Keyboard, focus & VoiceOver")
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                Text(
                    "Policy lives on ``GuardianChromeInteraction``. Confirms: Escape dismisses; **standard** confirms map Return to the blue button; **danger** confirms do **not** use defaultAction on the red button."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ThemeCatalogSubheading("Icon-only checklist (§9.3)")
                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    checklistRow("accessibilityLabel", "Short role: “Close”, “Vehicle inspector”.")
                    checklistRow("accessibilityHint", "Outcome when ambiguous; keep parallel with help text.")
                    checklistRow("help", "Pointer tooltip on macOS.")
                    checklistRow("§9.4", "Never rely on red/green alone for critical state — pair with symbol + copy.")
                }

                ThemeCatalogSubheading("GuardianFocusRing + guardianKeyboardFocusRing (§9.2)")
                Toggle("Simulate keyboard focus on plain control", isOn: $catalogFocusRingDemo)
                    .controlSize(.small)
                Button {
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(GuardianTypography.font(.windowHeading16Medium))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 36, height: 28)
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .guardianKeyboardFocusRing(show: catalogFocusRingDemo, cornerRadius: 6)
                .help("Example plain icon button with custom focus ring when enabled above.")
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianChromeInteraction · GuardianFocusRing")
        }
    }

    private func checklistRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: GuardianSpacing.sm) {
            Text(title)
                .font(GuardianTypography.font(.telemetryMono11Semibold))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 168, alignment: .leading)
            Text(detail)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Inline notices

    private var inlineNoticesSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Inline notices")
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                GuardianInlineNotice(
                    kind: .informational,
                    title: "Informational",
                    detail: "Use for neutral guidance that should read softer than a blocking alert."
                )
                GuardianInlineNotice(
                    kind: .success,
                    title: "Success",
                    detail: "Confirms completion: pairing succeeded, calibration saved, or export finished."
                )
                GuardianInlineNotice(
                    kind: .warning,
                    title: "Warning",
                    detail: "Surfaces risk before it happens—GPS degraded, battery marginal, or policy override active."
                )
                GuardianInlineNotice(
                    kind: .danger,
                    title: "Danger",
                    detail: "Hard stops: link lost, geofence breach, or destructive action pending confirmation."
                )
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianInlineNotice")
        }
    }

    // MARK: - Toasts

    private var toastSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Ephemeral toasts")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text("Live previews use ``ToastCenter`` (same host as ``View/withToasts()``). Static chips below mirror the solid fills from ``ToastHost``.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: GuardianSpacing.xs) {
                    GuardianPrimaryProminentButton(title: "Show info toast") {
                        toastCenter.show("Telemetry snapshot recorded.", style: .info)
                    }
                    GuardianPrimaryProminentButton(title: "Show success toast") {
                        toastCenter.show("Mission package uploaded.", style: .success)
                    }
                    GuardianThemedButton(
                        title: "Show warning toast",
                        accent: .warning,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: {
                            toastCenter.show("Battery planner skipped one slot.", style: .warning)
                        }
                    )
                    GuardianDestructiveProminentButton(title: "Show error toast") {
                        toastCenter.show("Link heartbeat missed.", style: .error)
                    }
                }

                HStack(alignment: .top, spacing: GuardianSpacing.xs) {
                    toastReplicaChip(text: "Info toast body", style: .info)
                    toastReplicaChip(text: "Success", style: .success)
                    toastReplicaChip(text: "Warning", style: .warning)
                    toastReplicaChip(text: "Error", style: .error)
                }
            }
            .guardianInsetCard()

            ThemeAPICaption("ToastCenter · GuardianFeedbackSeverity (ToastStyle) · ToastHost")
        }
    }

    private func toastReplicaChip(text: String, style: ToastStyle) -> some View {
        HStack(spacing: GuardianSpacing.xsTight) {
            Image(systemName: style.icon)
            Text(text)
                .lineLimit(2)
        }
        .font(GuardianTypography.font(.inlineNoticeTitle))
        .foregroundStyle(.white)
        .padding(.horizontal, GuardianSpacing.sm)
        .padding(.vertical, GuardianSpacing.xs)
        .background(toastReplicaBackground(for: style))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .frame(maxWidth: 200, alignment: .leading)
    }

    private func toastReplicaBackground(for style: ToastStyle) -> Color {
        style.toastEphemeralSolidBackground
    }

    // MARK: - Modal

    private var modalShellSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Modal shell (canonical sheets)")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text(
                    "The shell title uses the typography scale (``.title3.bold()`` in ``GuardianModalHeaderBar``); subtitles use 12pt secondary text. "
                        + "All sheets that use ``Modal`` share the same raised header, **one** ``GuardianModalHeaderSeparator`` (``theme.borderSubtle``, 1pt), and body padding from ``GuardianModalLayout``. "
                        + "Do not add a ``Divider`` or second border flush under the header inside ``bodyContent`` — that creates the inconsistent “some modals have a line, some don’t” look."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("Live chrome preview (same ``Modal`` as real sheets)")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textPrimary)

                Modal(
                    title: "Title",
                    subtitle: "Optional subtitle",
                    headerActions: {
                        HStack(spacing: GuardianSpacing.xs) {
                            GuardianThemedButton(
                                title: "Cancel",
                                accent: .danger,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: {}
                            )
                            GuardianPrimaryProminentButton(title: "Save") {}
                        }
                    },
                    bodyContent: {
                        Text("Body region — padded with ``GuardianModalLayout/bodyPadding`` on ``backgroundBase``.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
                .frame(maxWidth: 520)

                GuardianPrimaryProminentButton(title: "Present full sample modal") {
                    showSampleSheet = true
                }

                ThemeAPICaption("Modal · GuardianModalHeaderBar · GuardianModalHeaderSeparator · GuardianModalLayout")
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Confirm dialogs

    private var confirmDialogsSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Confirm dialogs (GuardianConfirm · GuardianConfirmDanger)")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text(
                    "One continuous surface (same fill for header, body, and footer): icon + optional headline on the first row, supporting copy below, then a hairline and actions. "
                        + "GuardianConfirm: Cancel (red outline) + Confirm (blue). GuardianConfirmDanger: red panel + red border; Cancel neutral outline, Confirm red solid."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("GuardianConfirm — standard")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textPrimary)

                themeCatalogConfirmStandardPreview
                    .frame(maxWidth: 440)

                Text("GuardianConfirmDanger — destructive / deletion")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, GuardianSpacing.xxs)

                themeCatalogConfirmDangerPreview
                    .frame(maxWidth: 440)

                Text("Title omitted — message sits beside the icon")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, GuardianSpacing.xxs)

                themeCatalogConfirmStandardNoTitlePreview
                    .frame(maxWidth: 440)

                ThemeAPICaption("GuardianConfirm · GuardianConfirmDanger · GuardianConfirmLayout")
            }
            .guardianInsetCard()
        }
    }

    private var themeCatalogConfirmStandardPreview: some View {
        GuardianConfirm(
            title: "Leave Mission Control?",
            message: "You have a run in progress. Leaving this screen does not stop vehicles — pause or end the run from Mission Control first if you need a safe stop.",
            cancelTitle: "Stay",
            confirmTitle: "Leave anyway",
            onCancel: {},
            onConfirm: {}
        )
        .overlay {
            RoundedRectangle(cornerRadius: GuardianConfirmLayout.cornerRadius, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        }
    }

    private var themeCatalogConfirmDangerPreview: some View {
        GuardianConfirmDanger(
            title: "Delete this run?",
            message: "This removes the run from Mission Control permanently. The mission template stays in your library; only this run’s history, roster, and log export snapshot are removed.",
            cancelTitle: "Cancel",
            confirmTitle: "Delete run",
            onCancel: {},
            onConfirm: {}
        )
    }

    private var themeCatalogConfirmStandardNoTitlePreview: some View {
        GuardianConfirm(
            title: nil,
            message: "Reloading will discard unsaved edits in this inspector. Continue?",
            cancelTitle: "Cancel",
            confirmTitle: "Reload",
            onCancel: {},
            onConfirm: {}
        )
        .overlay {
            RoundedRectangle(cornerRadius: GuardianConfirmLayout.cornerRadius, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Progress & activity")
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                ProgressView(value: 0.62)
                    .tint(.blue)
                ProgressView()
                    .controlSize(.small)
                Text("Prefer linear determinate progress for downloads and compile steps; indeterminate spinners for “waiting on vehicle”.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Breadcrumb trail")
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                GuardianBreadcrumbTrail(segments: ["Guardian HQ", "Fleet", "Vehicles", "Rotorcraft"])
                ThemeAPICaption("GuardianBreadcrumbTrail")
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Table

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Data table")
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                Table(fleetTableRows) {
                    TableColumn("Vehicle") { row in
                        Text(row.vehicle)
                    }
                    TableColumn("Stack") { row in
                        Text(row.stack)
                    }
                    TableColumn("Link") { row in
                        Text(row.link)
                    }
                    TableColumn("State") { row in
                        GuardianBadge(text: row.state, accent: row.badgeTone, paint: .light, size: .small, shape: .pill)
                    }
                }
                .frame(height: 150)
                Text("Tables pick up the window background; wrap them in ``guardianInsetCard()`` when they need a raised frame.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Icons

    private var iconographySizeGridSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Icon size grid (Theme 11.1)")
            Text(
                "Themed toolbar buttons use GuardianChromeSize.chromeGlyphFont inside controlOuterHeight rows. "
                    + "App sidebar and dense fleet rows use GuardianIconography and GuardianTypography roles — not one-off point sizes."
            )
            .font(GuardianTypography.font(.denseFootnoteRegular))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                ForEach(GuardianChromeSize.allCases, id: \.self) { chrome in
                    HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                            Text("Chrome · \(chromeSizeCatalogTitle(chrome))")
                                .font(GuardianTypography.font(.denseCaption12Medium))
                                .foregroundStyle(theme.textPrimary)
                            Text(chromeSizeCatalogMetricsLine(chrome))
                                .font(GuardianTypography.font(.denseCaption10Regular))
                                .foregroundStyle(theme.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "gearshape.fill")
                            .font(chrome.chromeGlyphFont)
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: chrome.controlOuterHeight, height: chrome.controlOuterHeight)
                            .background(theme.backgroundElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
                            )
                    }
                }

                iconographyCatalogRow(
                    title: "App sidebar · collapsed",
                    subtitle: "16 pt semibold — GuardianIconography.appSidebarSystemGlyph(collapsed: true)",
                    font: GuardianIconography.appSidebarSystemGlyph(collapsed: true)
                )
                iconographyCatalogRow(
                    title: "App sidebar · expanded",
                    subtitle: "14 pt semibold",
                    font: GuardianIconography.appSidebarSystemGlyph(collapsed: false)
                )
                iconographyCatalogRow(
                    title: "Dense row leading",
                    subtitle: "14 pt semibold — fleet cards, panel kickers",
                    font: GuardianIconography.denseRowLeadingGlyph
                )
                iconographyCatalogRow(
                    title: "Hero picker (18 pt)",
                    subtitle: "Mission / sim sidebars",
                    font: GuardianIconography.heroPickerGlyph18
                )
            }
            .guardianInsetCard()

            Text(
                "Theme 11.2 — symbol vocabulary: prefer transport, link, antenna, and map metaphors in Fleet versus "
                    + "mission and timeline glyphs in Mission Control; keep each strip visually quiet. Editorial guidance only — not validated in code."
            )
            .font(GuardianTypography.font(.denseCaption10Regular))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            ThemeAPICaption("GuardianIconography · GuardianChromeSize")
        }
    }

    private func chromeSizeCatalogTitle(_ chrome: GuardianChromeSize) -> String {
        switch chrome {
        case .small: "small"
        case .medium: "medium"
        case .large: "large"
        }
    }

    private func chromeSizeCatalogMetricsLine(_ chrome: GuardianChromeSize) -> String {
        switch chrome {
        case .small: "28 pt row · 12 pt glyph (chromeGlyphFont)"
        case .medium: "32 pt row · 13 pt glyph"
        case .large: "36 pt row · 14 pt glyph"
        }
    }

    private func iconographyCatalogRow(title: String, subtitle: String, font: Font) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                Text(title)
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "airplane")
                .font(font)
                .foregroundStyle(theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(theme.backgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
        }
    }

    private var iconGridSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Icon vocabulary")
            Text("Common SF Symbols at GuardianIconography.catalogSampleGlyph — same cap as GuardianTypography windowHeading16Semibold.")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
            let symbols = [
                "airplane", "helicopter", "map", "location.fill", "antenna.radiowaves.left.and.right",
                "link", "link.badge.plus", "play.fill", "pause.fill", "stop.fill",
                "gearshape", "pencil", "trash", "checkmark.circle.fill", "exclamationmark.triangle.fill",
            ]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: GuardianSpacing.denseGutter)], alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                ForEach(symbols, id: \.self) { name in
                    VStack(spacing: GuardianSpacing.xxs) {
                        Image(systemName: name)
                            .font(GuardianIconography.catalogSampleGlyph)
                            .foregroundStyle(theme.textPrimary)
                        Text(name)
                            .font(GuardianTypography.relativeFixed(size: 8, weight: .medium, design: .monospaced, relativeTo: .caption2))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GuardianSpacing.xs)
                    .background(theme.backgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("GuardianIconography.catalogSampleGlyph")
        }
    }

    // MARK: - Sub-bar

    private var subBarSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Sub-bar strip")
            GuardianElevatedStrip {
                HStack {
                    Spacer(minLength: 0)
                    Text("Live telemetry")
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                        .foregroundStyle(theme.textSecondary)
                    GuardianPrimaryProminentButton(title: "Add Sim") {}
                }
            }
            Text("Prefer ``GuardianElevatedStrip`` for this pattern so Fleet / MC / Theme stay visually aligned.")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
            ThemeAPICaption("GuardianElevatedStrip")
        }
    }

    // MARK: - Production references

    private var productionReferenceSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            GuardianPanelSectionTitle(title: "Examples in shipping UI")
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                Text("Fleet / Mission Control still use specialized views below; new work should prefer ``GuardianBadge`` + ``GuardianThemeAccent`` when the stock matrix fits.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: GuardianSpacing.denseGutter) {
                    FleetLiveSimBadge(isSimulation: false)
                    FleetLiveSimBadge(isSimulation: true)
                    MissionRunStatusBadge(status: .running)
                    MissionRunStatusBadge(status: .setup)
                    MissionRunStatusBadge(status: .recovery)
                    MissionRunStatusBadge(status: .paused)
                    MissionRunStatusBadge(status: .completed)
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("FleetLiveSimBadge · MissionRunStatusBadge")
        }
    }
}

// MARK: - App drawer visual replica

/// Mirrors the live ``AppDrawer`` host panel (when `title != nil`): full-height elevated shell + leading hairline — not a standalone rounded card.
private struct ThemeAppDrawerHostVisualReplica: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private let panelWidth: CGFloat = 320
    private let stripHeight: CGFloat = 220

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                theme.backgroundBase
                Text("Main column")
                    .font(GuardianTypography.font(.denseCaption10Medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(GuardianSpacing.xs)
            }
            .frame(minWidth: 48)
            .frame(maxWidth: .infinity)
            .frame(height: stripHeight)

            Group {
                AppDrawerChrome(title: "Sample panel", onClose: {}) {
                    Text(
                        "Same chrome as the running app: header row on backgroundElevated, body on the same full-panel elevated surface (host applies one elevated fill + leading hairline)."
                    )
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(GuardianSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: panelWidth, height: stripHeight, alignment: .top)
            .background(theme.backgroundElevated)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(width: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(
            Rectangle()
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Catalog helpers

private struct GuardianSpacingCatalogStep: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let value: CGFloat

    static let samples: [GuardianSpacingCatalogStep] = [
        GuardianSpacingCatalogStep(name: "xxs", value: GuardianSpacing.xxs),
        GuardianSpacingCatalogStep(name: "xs", value: GuardianSpacing.xs),
        GuardianSpacingCatalogStep(name: "sm", value: GuardianSpacing.sm),
        GuardianSpacingCatalogStep(name: "md", value: GuardianSpacing.md),
        GuardianSpacingCatalogStep(name: "lg", value: GuardianSpacing.lg),
        GuardianSpacingCatalogStep(name: "xl", value: GuardianSpacing.xl),
        GuardianSpacingCatalogStep(name: "xxl", value: GuardianSpacing.xxl),
        GuardianSpacingCatalogStep(name: "denseGutter", value: GuardianSpacing.denseGutter),
        GuardianSpacingCatalogStep(name: "cardBodyInset", value: GuardianSpacing.cardBodyInset),
        GuardianSpacingCatalogStep(name: "sectionStack", value: GuardianSpacing.sectionStack),
    ]
}

private struct ThemeCatalogSubheading: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String) {
        self.title = title
    }

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Text(title)
            .font(GuardianTypography.font(.inlineNoticeTitle))
            .foregroundStyle(theme.textPrimary)
    }
}

private struct ThemeCatalogTypographyScaleRow: View {
    let scale: GuardianTypography.Scale
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        let sample = scale.themeCatalogSample
        Text(sample.line)
            .font(scale.font(weight: sample.weight))
            .foregroundStyle(theme.textPrimary)
    }
}

private struct ThemeAPICaption: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(GuardianTypography.relativeFixed(size: 10, weight: .medium, design: .monospaced, relativeTo: .caption2))
            .foregroundStyle(theme.textTertiary)
    }
}

private extension GuardianTypography.Scale {
    struct ThemeCatalogSample: Sendable {
        let line: String
        let weight: Font.Weight
    }

    var themeCatalogSample: ThemeCatalogSample {
        switch self {
        case .largeTitle: ThemeCatalogSample(line: "Large title", weight: .bold)
        case .title: ThemeCatalogSample(line: "Title", weight: .semibold)
        case .title2: ThemeCatalogSample(line: "Title 2", weight: .semibold)
        case .title3: ThemeCatalogSample(line: "Title 3", weight: .semibold)
        case .headline: ThemeCatalogSample(line: "Headline", weight: .semibold)
        case .body: ThemeCatalogSample(line: "Body — default readable copy.", weight: .regular)
        case .callout: ThemeCatalogSample(line: "Callout for emphasized body.", weight: .regular)
        case .subheadline: ThemeCatalogSample(line: "Subheadline", weight: .regular)
        case .footnote: ThemeCatalogSample(line: "Footnote for dense tables.", weight: .regular)
        case .caption: ThemeCatalogSample(line: "Caption", weight: .regular)
        case .caption2: ThemeCatalogSample(line: "Caption 2", weight: .regular)
        }
    }
}

// MARK: - Swift Charts catalog sample

private struct ThemeCatalogSwiftChartsSample: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Chart(ThemeCatalogChartSampleData.points) { row in
            LineMark(
                x: .value("Sample", row.x),
                y: .value("Value", row.y)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(by: .value("Series", row.seriesLabel))
        }
        .chartLegend(position: .top, spacing: GuardianSpacing.sm)
        .frame(height: 176)
        .guardianChartTheme(colorScheme: colorScheme)
        .guardianChartSeriesForegroundScale(colorblindSafe: false)
    }
}

private enum ThemeCatalogChartSampleData {
    struct Row: Identifiable {
        let seriesLabel: String
        let x: Int
        let y: Double
        var id: String { "\(seriesLabel)-\(x)" }
    }

    static let points: [Row] = makePoints()

    private static func makePoints() -> [Row] {
        var out: [Row] = []
        for s in 0..<3 {
            let label = GuardianChartPalette.seriesDomainLabel(at: s)
            for x in 0..<16 {
                let y = sin(Double(x) * 0.38) * 2.4 + Double(s) * 0.9 + Double(x) * 0.04
                out.append(Row(seriesLabel: label, x: x, y: y))
            }
        }
        return out
    }
}

private struct ThemeFleetTableRow: Identifiable {
    let id = UUID()
    let vehicle: String
    let stack: String
    let link: String
    let state: String
    let badgeTone: GuardianThemeAccent

    static let samples: [ThemeFleetTableRow] = [
        ThemeFleetTableRow(vehicle: "Nimbus 4", stack: "PX4", link: "UDP :14550", state: "Live", badgeTone: .success),
        ThemeFleetTableRow(vehicle: "Vector S", stack: "ArduPilot", link: "TCP", state: "Sim", badgeTone: .warning),
        ThemeFleetTableRow(vehicle: "Halo Q", stack: "PX4", link: "Serial", state: "Idle", badgeTone: .neutral),
    ]
}

private extension GuardianThemeAccent {
    var label: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .success: "Success"
        case .warning: "Warning"
        case .info: "Info"
        case .danger: "Danger"
        case .neutral: "Neutral"
        case .teal: "Teal"
        case .purple: "Purple"
        case .pink: "Pink"
        case .yellow: "Yellow"
        }
    }
}
