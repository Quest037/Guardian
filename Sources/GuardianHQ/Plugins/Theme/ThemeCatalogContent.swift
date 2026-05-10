import SwiftUI

/// Full design-system catalog for the Theme plugin (Guardian tokens + ``GuardianUIChrome``).
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

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                heroSection
                layoutTokensSection
                surfaceElevationSection
                spacingAndRadiusSection
                typographySection
                modalShellSection
                overlayScrimAndAppDrawerSection
                guardianCardCatalogSection
                semanticColorsSection
                badgeMatrixSection
                buttonMatrixSection
                docTabsSection
                formControlsSection
                menusPopoversSection
                disclosureAccordionSection
                listAndDisclosureSection
                inlineNoticesSection
                toastSection
                progressSection
                breadcrumbSection
                tableSection
                iconGridSection
                searchMetricsAndStripSection
                subBarSection
                productionReferenceSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundBase)
        .sheet(isPresented: $showSampleSheet) {
            Modal(
                title: "Sample sheet",
                subtitle: "Uses ``Modal`` only — one ``GuardianModalHeaderSeparator``; no extra header ``Divider`` in the body.",
                headerActions: {
                    HStack(spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Body uses ``GuardianModalLayout/bodyPadding`` from the shell; do not draw another rule line under the title row.")
                            .font(.system(size: 12))
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
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Theme & UI chrome")
            Text(
                "Guardian’s UI theme is tokenized: pick a ``GuardianThemeAccent``, a size, a shape, and a surface (solid / light / outline for badges; "
                    + "solid / outline for buttons). Domain names like “mission phase” are **not** part of the theme — they are just one application of these tokens."
            )
            .font(.system(size: 12))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                Link(
                    "Star HTML Pro docs (reference)",
                    destination: URL(string: "https://preview.keenthemes.com/html/star-html-pro/docs/?page=index")!
                )
                .font(.system(size: 12, weight: .semibold))

                Link(
                    "Badges reference",
                    destination: URL(string: "https://preview.keenthemes.com/html/star-html-pro/docs/?page=base/badges")!
                )
                .font(.system(size: 12, weight: .semibold))
            }

            ThemeAPICaption("Entry: ThemePanelView → ThemeCatalogContent")
        }
    }

    // MARK: - Layout tokens

    private var layoutTokensSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Layout rhythm (example constants)")
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Spacing is not part of the color theme, but screens should pull from shared layout enums when they exist — e.g. Mission Control prep uses "
                        + "``MissionRunPrepLayout/setupScrollPaddingH`` / ``setupScrollPaddingV`` (10pt) so dense chrome stays consistent."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    layoutTokenChip("setupScrollPaddingH", "\(Int(MissionRunPrepLayout.setupScrollPaddingH))pt")
                    layoutTokenChip("setupBlockSpacing", "\(Int(MissionRunPrepLayout.setupBlockSpacing))pt")
                    layoutTokenChip("rosterSlotCornerRadius", "\(Int(MissionRunPrepLayout.rosterSlotCornerRadius))pt")
                }
                Text("This catalog uses 20pt outer padding on the scroll content; match product screens to their owning layout enum, not arbitrary magic numbers.")
                    .font(.system(size: 11))
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
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(2)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Doc-style tabs

    private var docTabsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Tabs & segmented shells")
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Documentation sites (e.g. Keen’s component index) stack a segmented control above swapped content. "
                        + "Use the same pattern for inspector modes; reserve ``TabView`` for true multi-page flows."
                )
                .font(.system(size: 12))
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Overview pane")
                                .font(.system(size: 13, weight: .semibold))
                            GuardianInlineNotice(
                                kind: .informational,
                                title: "Pattern",
                                detail: "Segmented header + one lazy body keeps scroll performance predictable in wide panels."
                            )
                        }
                    case 1:
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Simulate fleet uplink", isOn: $toggleOn)
                                .controlSize(.small)
                            Stepper("Sample stepper: \(stepperValue)", value: $stepperValue, in: 0...5)
                        }
                    default:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Theme accents (swatches)")
                                .font(.system(size: 12, weight: .semibold))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(accentPreviewColor(accent))
                                            .frame(width: 24, height: 24)
                                            .overlay(Circle().strokeBorder(theme.borderSubtle, lineWidth: 1))
                                        Text(accent.label)
                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                            .foregroundStyle(theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .guardianInsetCard()
            ThemeAPICaption("Picker · .pickerStyle(.segmented)")
        }
    }

    // MARK: - Menus & popovers

    private var menusPopoversSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Menus, context menus, popovers")
            VStack(alignment: .leading, spacing: 14) {
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

                ThemeCatalogSubheading("Context menu on bordered button")
                Button("Right-click or long-press") {}
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .controlSize(.small)
                    .contextMenu {
                        Button("Copy token") {}
                        Button("Reveal in Finder") {}
                    }

                ThemeCatalogSubheading("Popover (local inspector)")
                Button("Show popover") { showCatalogPopover.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $showCatalogPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Popover body")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Use for lightweight field help; use ``Modal`` or ``AppDrawer`` for heavy flows.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 240)
                        }
                        .padding(12)
                    }
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Disclosure / accordion

    private var disclosureAccordionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Accordion (DisclosureGroup)")
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup(isExpanded: $accordionExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nested settings or grouped telemetry fields belong behind a disclosure so the default surface stays calm.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                        GuardianLabeledFormField(label: "Nested field") {
                            TextField("value", text: $sampleText)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Advanced routing")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("DisclosureGroup")
        }
    }

    // MARK: - Search, metrics, elevated strip

    private var searchMetricsAndStripSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Search, KPI tiles, elevated strip")
            VStack(alignment: .leading, spacing: 14) {
                GuardianLabeledFormField(label: "GuardianSearchBarField") {
                    GuardianSearchBarField(text: $searchDemoQuery, placeholder: "Filter vehicles, missions…")
                }
                HStack(alignment: .top, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "App drawer (trailing panel)")
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "App-wide **drawers** use ``AppDrawer`` + ``View/withAppDrawer()`` on the window root (above toasts). "
                        + "This is not the main navigation **sidebar** in ``RootView``. "
                        + "Do not hand-roll `ZStack` scrims + `transition(.move(edge:))` for trailing panels. "
                        + "When ``present(title:…)`` supplies a title, the host uses ``AppDrawerChrome`` (below); use ``title: nil`` only when your content already includes a full custom header."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("Visual replica (matches the live AppDrawer host — not a rounded card)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Text(
                    "Live host: trailing `HStack` + panel `frame(width:)` · `backgroundElevated` on the **whole** panel · leading 1pt `borderSubtle` line · square trailing edge to the window. "
                        + "Preview uses a short strip; widths clamp 260–560 (default 380)."
                )
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

                ThemeAppDrawerHostVisualReplica()
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("overlayScrim (light)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(GuardianTheme.palette(for: .light).overlayScrim)
                            .frame(width: 72, height: 44)
                            .overlay(
                                Text("Aa")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("overlayScrim (dark)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(GuardianTheme.palette(for: .dark).overlayScrim)
                            .frame(width: 72, height: 44)
                            .overlay(
                                Text("Aa")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                    }
                }

                GuardianPrimaryProminentButton(title: "Present sample AppDrawer") {
                    appDrawer.present(title: "Sample drawer", preferredWidth: 360, scrimTapDismisses: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("This drawer uses the shared overlay host: scrim tap dismisses when enabled.")
                                .font(.system(size: 12))
                                .foregroundStyle(GuardianTheme.palette(for: colorScheme).textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            GuardianDestructiveProminentButton(title: "Dismiss") {
                                appDrawer.dismiss()
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .guardianInsetCard()
            ThemeAPICaption("AppDrawer · AppDrawerChrome · GuardianThemePalette/overlayScrim")
        }
    }

    // MARK: - GuardianCard (Bootstrap-style)

    private var guardianCardCatalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "GuardianCard (Bootstrap-style panel)")
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Central card template: optional media (flush top), header, body, and footer; hairlines between slots; ``GuardianThemePalette`` fill + border accents. "
                        + "When media sits above another slot, its bottom corners are square so it meets header/body/footer cleanly; media-only cards keep full corner radius. "
                        + "Default border is subtle; use GuardianCardBorder.none to omit the outer stroke. "
                        + "Set ``GuardianCardConfiguration/bodyPadding`` to 0 for map-style bodies. "
                        + "``guardianInsetCard()`` remains for legacy panels; new work should prefer ``GuardianCard``."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 12) {
                    GuardianCard(
                        configuration: GuardianCardConfiguration(border: .subtle, bodyPadding: 14),
                        body: {
                            Text("Body only · default subtle border + padded body.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                        }
                    )
                    .frame(maxWidth: .infinity)

                    GuardianCard(
                        configuration: GuardianCardConfiguration(border: .none, bodyPadding: 14),
                        body: {
                            Text("Border none — still raised fill; no outer stroke.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                        }
                    )
                    .frame(maxWidth: .infinity)
                }

                GuardianCard(
                    configuration: GuardianCardConfiguration(border: .primary, bodyPadding: 12),
                    header: {
                        Text("With header strip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    },
                    body: {
                        Text("Header uses elevated strip; hairline separates header and body.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    }
                )

                GuardianCard(
                    configuration: GuardianCardConfiguration(border: .subtle, bodyPadding: 12),
                    body: {
                        Text("Body content with default padding.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    },
                    footer: {
                        Text("Footer strip · elevated background")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                )

                GuardianCard(
                    configuration: GuardianCardConfiguration(
                        border: .danger,
                        cornerRadius: GuardianCardLayout.cornerRadius,
                        bodyPadding: 12
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
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                        }
                    },
                    header: {
                        Text("Full stack")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    },
                    body: {
                        Text("Media + header + body + footer. Outer border uses semantic danger stroke for this sample.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    },
                    footer: {
                        HStack {
                            Text("Footer actions row")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textTertiary)
                            Spacer()
                            GuardianPrimaryProminentButton(title: "OK") {}
                        }
                    }
                )

                HStack(alignment: .top, spacing: 12) {
                    GuardianCard(
                        configuration: GuardianCardConfiguration(border: .warning, bodyPadding: 0),
                        media: {
                            ZStack {
                                theme.backgroundElevated
                                Text("Media + body · bodyPadding 0 (map-style)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .frame(height: 88)
                        },
                        body: {
                            Text("Body is edge-to-edge under the media hairline — no inner padding.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                                .padding(12)
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
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(8)
                            }
                            .frame(height: 120)
                        }
                    )
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legacy inset helper")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("``guardianInsetCard()`` uses ``GuardianDynamicColors`` + fixed hairline; migrate panels to ``GuardianCard`` when touching them.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .guardianInsetCard()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Compact inset")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("``guardianInsetCardCompact()``")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .guardianInsetCardCompact()
                }

                ThemeAPICaption(
                    "GuardianCard · GuardianCardConfiguration · GuardianCardBorder · GuardianCardSections · GuardianCardLayout · guardianInsetCard()"
                )
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Surfaces

    private var surfaceElevationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Surfaces & elevation")
            Text("``GuardianThemePalette`` maps the four-layer stack used across HQ: base window, raised panels, elevated strips, and active/pressed chrome.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                surfaceRow("backgroundBase", theme.backgroundBase, theme.textPrimary)
                surfaceRow("backgroundRaised", theme.backgroundRaised, theme.textPrimary)
                surfaceRow("backgroundElevated", theme.backgroundElevated, theme.textPrimary)
                surfaceRow("backgroundActive", theme.backgroundActive, theme.textPrimary)
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianTheme.palette(for:) · View/guardianInsetCard() uses backgroundRaised + borderSubtle")
        }
    }

    private func surfaceRow(_ name: String, _ color: Color, _ labelColor: Color) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 8)
            Text("Aa")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(labelColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Spacing & corner radii")
            VStack(alignment: .leading, spacing: 12) {
                ThemeCatalogSubheading("Common horizontal rhythm")
                HStack(spacing: 0) {
                    ForEach([4, 8, 10, 12, 16, 20], id: \.self) { step in
                        VStack(spacing: 4) {
                            Text("\(step)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                            Rectangle()
                                .fill(GuardianBrand.purple.opacity(0.55))
                                .frame(width: CGFloat(step), height: 18)
                        }
                        if step != 20 {
                            Spacer(minLength: 6)
                        }
                    }
                }
                ThemeCatalogSubheading("Inset card radius (10pt continuous)")
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 2)
                        .frame(width: 56, height: 40)
                        .overlay(Text("10").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textTertiary))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 2)
                        .frame(width: 56, height: 40)
                        .overlay(Text("8").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textTertiary))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.borderSubtle, lineWidth: 2)
                        .frame(width: 56, height: 40)
                        .overlay(Text("5 chip").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textTertiary))
                }
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Typography scale")
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    Text("Large title").font(.largeTitle.weight(.bold)).foregroundStyle(theme.textPrimary)
                    Text("Title 2").font(.title2.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    Text("Title 3").font(.title3.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    Text("Headline").font(.headline).foregroundStyle(theme.textPrimary)
                    Text("Body — default readable copy.").font(.body).foregroundStyle(theme.textPrimary)
                    Text("Callout for emphasized body.").font(.callout).foregroundStyle(theme.textSecondary)
                    Text("Subheadline").font(.subheadline).foregroundStyle(theme.textSecondary)
                    Text("Footnote for dense tables.").font(.footnote).foregroundStyle(theme.textSecondary)
                    Text("Caption 2").font(.caption2).foregroundStyle(theme.textTertiary)
                    Text("MONO 11 · 0x7F3A")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Semantic colors

    private var semanticColorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Semantic accents")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    semanticSwatch("Success", GuardianSemanticColors.successForeground, GuardianSemanticColors.successBackground)
                    semanticSwatch("Warning", GuardianSemanticColors.warningForeground, GuardianSemanticColors.warningBackground)
                    semanticSwatch("Danger", GuardianSemanticColors.dangerForeground, GuardianSemanticColors.dangerBackground)
                    semanticSwatch("Info", GuardianSemanticColors.infoForeground, GuardianSemanticColors.infoBackground)
                }
                Divider().opacity(0.25)
                HStack(spacing: 10) {
                    semanticSwatch("Neutral badge", GuardianSemanticColors.neutralBadgeForeground, GuardianSemanticColors.neutralBadgeBackground)
                    semanticSwatch("Success stroke", GuardianSemanticColors.successStroke, GuardianSemanticColors.successBackground)
                    semanticSwatch("Warning stroke", GuardianSemanticColors.warningStroke, GuardianSemanticColors.warningBackground)
                }
                Divider().opacity(0.25)
                Text("Extended accents (also on ``GuardianThemeAccent``) — use for badges/buttons via the theme, not one-off colors.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: 10) {
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

    private func semanticSwatch(_ label: String, _ fg: Color, _ bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
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
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Badges (theme matrix)")
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "Pick ``GuardianThemeAccent`` × ``GuardianBadgePaint`` (solid / light / outline) × ``GuardianBadgeSize`` (small / medium / large) × "
                        + "``GuardianBadgeShape`` (pill / cornered / square / circle). Same vocabulary as a CSS theme layer."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                Link(
                    "KeenThemes badge reference (inspiration)",
                    destination: URL(string: "https://preview.keenthemes.com/html/star-html-pro/docs/?page=base/badges")!
                )
                .font(.system(size: 12, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 16) {
                ThemeCatalogSubheading("Solid · pill · medium · all accents")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianBadge(text: accent.label, accent: accent, paint: .solid, size: .medium, shape: .pill)
                    }
                }

                ThemeCatalogSubheading("Light · pill · medium")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianBadge(text: accent.label, accent: accent, paint: .light, size: .medium, shape: .pill)
                    }
                }

                ThemeCatalogSubheading("Outline · cornered · medium")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(GuardianThemeAccent.allCases, id: \.self) { accent in
                        GuardianBadge(text: accent.label, accent: accent, paint: .outline, size: .medium, shape: .cornered)
                    }
                }

                ThemeCatalogSubheading("Shapes · primary · solid · medium")
                HStack(spacing: 8) {
                    GuardianBadge(text: "Pill", accent: .primary, paint: .solid, size: .medium, shape: .pill)
                    GuardianBadge(text: "Cornered", accent: .primary, paint: .solid, size: .medium, shape: .cornered)
                    GuardianBadge(text: "Sq", accent: .primary, paint: .solid, size: .medium, shape: .square)
                    GuardianBadge(text: "3", accent: .primary, paint: .solid, size: .medium, shape: .circle)
                }

                ThemeCatalogSubheading("Sizes · success · solid · pill")
                HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Buttons (theme matrix)")
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "Use ``GuardianThemedButton`` with ``GuardianThemeAccent``, ``GuardianChromeSurface`` (solid / outline), ``GuardianChromeSize``, and ``GuardianChromeShape``. "
                        + "``GuardianPrimaryProminentButton`` / ``GuardianDestructiveProminentButton`` are thin wrappers for the common save / delete cases."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ThemeCatalogSubheading("Shapes · solid · primary · small")
                HStack(spacing: 10) {
                    GuardianThemedButton(title: "Square", accent: .primary, surface: .solid, size: .small, shape: .square, action: {})
                    GuardianThemedButton(title: "Cornered", accent: .primary, surface: .solid, size: .small, shape: .cornered, action: {})
                    GuardianThemedButton(title: "Pill", accent: .primary, surface: .solid, size: .small, shape: .pill, action: {})
                }

                ThemeCatalogSubheading("Sizes · cornered · info · solid")
                HStack(spacing: 10) {
                    GuardianThemedButton(title: "Small", accent: .info, surface: .solid, size: .small, shape: .cornered, action: {})
                    GuardianThemedButton(title: "Medium", accent: .info, surface: .solid, size: .medium, shape: .cornered, action: {})
                    GuardianThemedButton(title: "Large", accent: .info, surface: .solid, size: .large, shape: .cornered, action: {})
                }

                ThemeCatalogSubheading("Accents · solid · cornered · small")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
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
                HStack(spacing: 10) {
                    GuardianPrimaryProminentButton(title: "Save") {}
                    GuardianDestructiveProminentButton(title: "Remove") {}
                    GuardianNeutralBorderedButton(systemImage: "gearshape", help: "Settings") {}
                }

                ThemeCatalogSubheading("Edit before delete (icon row rule)")
                GuardianEditThenDeleteIconRow(onEdit: {}, onDelete: {})
                Text("Edit uses the pencil icon with a blue tint; delete uses the trash icon with a red tint and appears after edit.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCard()

            ThemeAPICaption("GuardianThemedButton · GuardianThemedButtonStrip · GuardianChromeSurface · GuardianChromeSize · GuardianChromeShape")
        }
    }

    // MARK: - Forms

    private var formControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Forms & pickers")
            VStack(alignment: .leading, spacing: 14) {
                GuardianLabeledFormField(label: "Hostname") {
                    TextField("hostname", text: $sampleText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }

                GuardianLabeledFormField(label: "Secret") {
                    SecureField("secret", text: $sampleSecret)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }

                GuardianLabeledFormField(label: "Transport") {
                    Picker("Transport", selection: $menuPick) {
                        Text("TCP").tag("TCP")
                        Text("UDP").tag("UDP")
                        Text("Serial").tag("Serial")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                GuardianLabeledFormField(label: "Segmented filter (Picker)") {
                    Picker("", selection: $catalogSegment) {
                        Text("All").tag(0)
                        Text("Live").tag(1)
                        Text("Sim").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                Toggle("Enable Guardian Link", isOn: $toggleOn)
                    .controlSize(.small)

                Stepper("Retries: \(stepperValue)", value: $stepperValue, in: 0...5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Throttle curve")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Slider(value: $sliderValue, in: 0...1)
                }
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Lists

    private var listAndDisclosureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Lists & disclosure rows")
            VStack(alignment: .leading, spacing: 12) {
                ThemeCatalogSubheading("GuardianDisclosureSettingRow inside inset card")
                VStack(spacing: 0) {
                    GuardianDisclosureSettingRow(title: "Vehicle identity", value: "GXF-2044") {}
                    Divider().opacity(0.2)
                    GuardianDisclosureSettingRow(title: "Calibration anchors", value: "12 defined") {}
                    Divider().opacity(0.2)
                    GuardianDisclosureSettingRow(title: "Danger zone", value: nil) {}
                }
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

            ThemeAPICaption("GuardianDisclosureSettingRow · List + .listStyle(.inset(alternatesRowBackgrounds:))")
        }
    }

    // MARK: - Inline notices

    private var inlineNoticesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Inline notices")
            VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Ephemeral toasts")
            VStack(alignment: .leading, spacing: 12) {
                Text("Live previews use ``ToastCenter`` (same host as ``View/withToasts()``). Static chips below mirror the solid fills from ``ToastHost``.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    GuardianPrimaryProminentButton(title: "Show info toast") {
                        toastCenter.show("Telemetry snapshot recorded.", style: .info)
                    }
                    GuardianPrimaryProminentButton(title: "Show success toast") {
                        toastCenter.show("Mission package uploaded.", style: .success)
                    }
                    GuardianDestructiveProminentButton(title: "Show error toast") {
                        toastCenter.show("Link heartbeat missed.", style: .error)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    toastReplicaChip(text: "Info toast body", style: .info)
                    toastReplicaChip(text: "Success", style: .success)
                    toastReplicaChip(text: "Error", style: .error)
                }
            }
            .guardianInsetCard()

            ThemeAPICaption("ToastCenter · ToastStyle · ToastHost")
        }
    }

    private func toastReplicaChip(text: String, style: ToastStyle) -> some View {
        HStack(spacing: 6) {
            Image(systemName: style.icon)
            Text(text)
                .lineLimit(2)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(toastReplicaBackground(for: style))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .frame(maxWidth: 200, alignment: .leading)
    }

    private func toastReplicaBackground(for style: ToastStyle) -> Color {
        switch style {
        case .success:
            return Color(red: 0.11, green: 0.44, blue: 0.24).opacity(0.82)
        case .info:
            return Color(red: 0.14, green: 0.34, blue: 0.62).opacity(0.82)
        case .error:
            return Color(red: 0.52, green: 0.14, blue: 0.18).opacity(0.82)
        }
    }

    // MARK: - Modal

    private var modalShellSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Modal shell (canonical sheets)")
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "The shell title uses the typography scale (``.title3.bold()`` in ``GuardianModalHeaderBar``); subtitles use 12pt secondary text. "
                        + "All sheets that use ``Modal`` share the same raised header, **one** ``GuardianModalHeaderSeparator`` (``theme.borderSubtle``, 1pt), and body padding from ``GuardianModalLayout``. "
                        + "Do not add a ``Divider`` or second border flush under the header inside ``bodyContent`` — that creates the inconsistent “some modals have a line, some don’t” look."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("Live chrome preview (same ``Modal`` as real sheets)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Modal(
                    title: "Title",
                    subtitle: "Optional subtitle",
                    headerActions: {
                        HStack(spacing: 8) {
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
                            .font(.system(size: 11))
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

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Progress & activity")
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: 0.62)
                    .tint(.blue)
                ProgressView()
                    .controlSize(.small)
                Text("Prefer linear determinate progress for downloads and compile steps; indeterminate spinners for “waiting on vehicle”.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Breadcrumb trail")
            VStack(alignment: .leading, spacing: 8) {
                GuardianBreadcrumbTrail(segments: ["Guardian HQ", "Fleet", "Vehicles", "Rotorcraft"])
                ThemeAPICaption("GuardianBreadcrumbTrail")
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Table

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Data table")
            VStack(alignment: .leading, spacing: 8) {
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
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Icons

    private var iconGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Icon vocabulary")
            let symbols = [
                "airplane", "helicopter", "map", "location.fill", "antenna.radiowaves.left.and.right",
                "link", "link.badge.plus", "play.fill", "pause.fill", "stop.fill",
                "gearshape", "pencil", "trash", "checkmark.circle.fill", "exclamationmark.triangle.fill",
            ]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(symbols, id: \.self) { name in
                    VStack(spacing: 4) {
                        Image(systemName: name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(name)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.backgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .guardianInsetCard()
        }
    }

    // MARK: - Sub-bar

    private var subBarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Sub-bar strip")
            GuardianElevatedStrip {
                HStack {
                    Spacer(minLength: 0)
                    Text("Live telemetry")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    GuardianPrimaryProminentButton(title: "Add Sim") {}
                }
            }
            Text("Prefer ``GuardianElevatedStrip`` for this pattern so Fleet / MC / Theme stay visually aligned.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
            ThemeAPICaption("GuardianElevatedStrip")
        }
    }

    // MARK: - Production references

    private var productionReferenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuardianPanelSectionTitle(title: "Examples in shipping UI")
            VStack(alignment: .leading, spacing: 10) {
                Text("Fleet / Mission Control still use specialized views below; new work should prefer ``GuardianBadge`` + ``GuardianThemeAccent`` when the stock matrix fits.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(8)
            }
            .frame(minWidth: 48)
            .frame(maxWidth: .infinity)
            .frame(height: stripHeight)

            Group {
                AppDrawerChrome(title: "Sample panel", onClose: {}) {
                    Text(
                        "Same chrome as the running app: header row on backgroundElevated, body on the same full-panel elevated surface (host applies one elevated fill + leading hairline)."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
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

private struct ThemeCatalogSubheading: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String) {
        self.title = title
    }

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
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
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.textTertiary)
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
