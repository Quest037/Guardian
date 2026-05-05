import SwiftUI

/// MAVSDK Server and MAVLink ingress — lives under Settings → MAVSDK Server.
struct MavsdkServerSettingsView: View {
    @ObservedObject var fleetLink: FleetLinkService

    @State private var draft: FleetLinkConfiguration = .defaults
    @State private var extraURLsText = ""

    private let bgPanel = Color(red: 0.12, green: 0.12, blue: 0.13)
    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MAVSDK Server")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(
                        "The link server runs only when Server is on in the top bar. Adjust ports and extra addresses below if your network or simulator needs it, or leave the defaults."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                }

                statusRow

                settingsPanel

                logPanel
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgMain)
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
        HStack(spacing: 12) {
            Circle()
                .fill(fleetLink.isRunning ? Color.green : Color.orange.opacity(0.85))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(fleetLink.isRunning ? "mavsdk_server running" : "mavsdk_server stopped")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Use the Server switch in the top bar to start or stop.")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }
            Spacer()
            Button("Save settings") {
                syncExtraURLsFromText()
                fleetLink.applyConfiguration(draft)
            }
            .buttonStyle(.bordered)
            .tint(.gray.opacity(0.4))
            .disabled(fleetLink.isRunning)
        }
        .padding(14)
        .background(bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connection")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

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
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 88, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let err = fleetLink.lastError {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Server log")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Clear") { fleetLink.clearLog() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.gray)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(fleetLink.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 280)
        }
        .padding(16)
        .background(bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.gray)
            content()
        }
    }

    private func syncExtraURLsFromText() {
        draft.additionalMavlinkConnectionURLs = extraURLsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
