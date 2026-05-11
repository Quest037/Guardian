import AppKit
import SwiftUI

/// MAVSDK Server and MAVLink ingress — lives under Settings → MAVSDK Server.
struct MavsdkServerSettingsView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: FleetLinkConfiguration = .defaults
    @State private var extraURLsText = ""

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.lg) {
                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    Text("MAVSDK Server")
                        .font(GuardianTypography.font(.pluginsPageHero))
                        .foregroundStyle(theme.textPrimary)
                    Text(
                        "The link server runs only when Server is on in the top bar. Adjust ports and extra addresses below if your network or simulator needs it, or leave the defaults."
                    )
                    .font(GuardianTypography.font(.denseSubsection13Regular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                statusRow

                settingsPanel

                logPanel
            }
            .padding(GuardianSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundBase)
        .onAppear {
            draft = fleetLink.configuration
            extraURLsText = fleetLink.configuration.additionalMavlinkConnectionURLs.joined(separator: "\n")
        }
        .onChange(of: fleetLink.configuration) { newValue in
            if !fleetLink.isRunning {
                draft = newValue
                extraURLsText = newValue.additionalMavlinkConnectionURLs.joined(separator: "\n")
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: GuardianSpacing.sm) {
            Circle()
                .fill(fleetLink.isRunning ? Color.green : Color.orange.opacity(0.85))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                Text(fleetLink.isRunning ? "mavsdk_server running" : "mavsdk_server stopped")
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Use the Server switch in the top bar to start or stop.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Button("Save settings") {
                syncExtraURLsFromText()
                fleetLink.applyConfiguration(draft)
            }
            .buttonStyle(.bordered).guardianPointerOnHover()
            .tint(.gray.opacity(0.4))
            .disabled(fleetLink.isRunning)
        }
        .padding(GuardianSpacing.cardBodyInset)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
            Text("Connection")
                .font(GuardianTypography.font(.panelEmphasisTitleBold))
                .foregroundStyle(theme.textPrimary)

            labeledField(title: "gRPC port") {
                TextField("50051", value: $draft.grpcPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
            }

            labeledField(title: "mavsdk_server path (optional)") {
                TextField("Auto / MAVSDK_SERVER / Homebrew", text: $draft.mavsdkServerPath)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField(title: "Primary MAVLink URL") {
                TextField("udpin://0.0.0.0:14550", text: $draft.primaryMavlinkConnectionURL)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField(title: "Extra MAVLink URLs (one per line)") {
                TextEditor(text: $extraURLsText)
                    .font(GuardianTypography.relativeFixed(size: 12, weight: .regular, design: .monospaced, relativeTo: .caption))
                    .frame(minHeight: 88, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(GuardianSpacing.xs)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let err = fleetLink.lastError {
                Text(err)
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(GuardianSpacing.md)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            HStack {
                Text("Server log")
                    .font(GuardianTypography.font(.panelEmphasisTitleBold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Copy") { copyServerLogToPasteboard() }
                    .buttonStyle(.borderless).guardianPointerOnHover()
                    .foregroundStyle(theme.textSecondary)
                    .disabled(fleetLink.logLines.isEmpty)
                    .help("Copy all log lines to the clipboard")
                Button("Clear") { fleetLink.clearLog() }
                    .buttonStyle(.borderless).guardianPointerOnHover()
                    .foregroundStyle(theme.textSecondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                    ForEach(Array(fleetLink.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(GuardianTypography.font(.telemetryMono11Regular))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
            }
            .frame(minHeight: 160, maxHeight: 280)
        }
        .padding(GuardianSpacing.md)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(title)
                .font(GuardianTypography.font(.inlineNoticeTitle))
                .foregroundStyle(theme.textSecondary)
            content()
        }
    }

    private func syncExtraURLsFromText() {
        draft.additionalMavlinkConnectionURLs = extraURLsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func copyServerLogToPasteboard() {
        let text = fleetLink.logLines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        toastCenter.show("Server log copied to clipboard.", style: .success, duration: 2.0)
    }
}
