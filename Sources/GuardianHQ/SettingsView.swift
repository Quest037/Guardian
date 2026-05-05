import SwiftUI

struct SettingsView: View {
    @Binding var selectedPane: SettingsPane
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var generalSettings: GeneralSettingsStore

    private let bgBar = Color(red: 0.12, green: 0.12, blue: 0.13)
    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Section", selection: $selectedPane) {
                    ForEach(SettingsPane.allCases) { pane in
                        Text(pane.rawValue).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(bgBar)

            Group {
                switch selectedPane {
                case .general:
                    generalPane
                case .mavsdkServer:
                    MavsdkServerSettingsView(fleetLink: fleetLink)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(bgMain)
        }
    }

    private var generalPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("General")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default simulation platform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Picker("Default simulation platform", selection: $generalSettings.defaultSimulationPlatform) {
                        ForEach(SimulationPlatform.allCases) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(
                        "Used for built-in SITL when you spawn a simulated vehicle without choosing a stack. "
                        + "Per-vehicle overrides will be available when Mission Control launches sim instances."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .opacity(0.35)

                Text("App-wide preferences will live here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgMain)
    }
}
