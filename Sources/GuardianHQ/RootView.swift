import SwiftUI

struct RootView: View {
    @Binding var selection: AppSection

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
                    .padding(24)
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
                    Text(section.rawValue)
                        .font(.system(size: 14, weight: section == selection ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(section == selection ? bgActive : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
            }

            Spacer()
        }
    }

    private var topBar: some View {
        HStack {
            Text("Guardian HQ")
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
        VStack(alignment: .leading, spacing: 12) {
            Text(selection.rawValue)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
            Text(selection.subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.gray)
        }
    }
}
