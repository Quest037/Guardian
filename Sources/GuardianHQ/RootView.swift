import SwiftUI

struct RootView: View {
    @Binding var selection: AppSection
    @StateObject private var missionStore = MissionStore()

    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)
    private let bgRail = Color(red: 0.12, green: 0.12, blue: 0.13)
    private let bgTop = Color(red: 0.14, green: 0.14, blue: 0.15)
    private let bgActive = Color(red: 0.20, green: 0.20, blue: 0.21)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .background(bgRail)

            VStack(spacing: 0) {
                topBar
                    .frame(height: 52)
                    .background(bgTop)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(bgMain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgMain)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Guardian")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack {
                        Text(section.rawValue)
                            .font(.system(size: 14, weight: section == selection ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(section == selection ? bgActive : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
            }

            Spacer()
        }
    }

    private var topBar: some View {
        HStack {
            Text(selection.rawValue)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Spacer()
            Text("Dark Mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.gray)
                .padding(.trailing, 16)
        }
    }

    private var content: some View {
        Group {
            switch selection {
            case .dashboard:
                DashboardView(missionStore: missionStore)
            case .missions:
                MissionsView(store: missionStore)
            default:
                Color.clear
            }
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var missionStore: MissionStore

    private var totalMissionRuns: Int {
        0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    dashboardStatCard(
                        title: "Missions",
                        value: "\(missionStore.missions.count)",
                        subtitle: "Templates available"
                    )
                    dashboardStatCard(
                        title: "Mission Runs",
                        value: "\(totalMissionRuns)",
                        subtitle: "Active in control"
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dashboardStatCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
