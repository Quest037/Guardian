import AppKit
import SwiftUI

/// Loads the mission’s generated JPEG from Application Support; placeholder until generation completes.
struct MissionCardThumbnailView: View {
    let mission: Mission

    private enum DisplayMode {
        case listTile(side: CGFloat, corner: CGFloat)
        case gridBanner(barHeight: CGFloat, thumbSide: CGFloat)
    }

    private let mode: DisplayMode

    init(mission: Mission, fixedLength: CGFloat = 56, cornerRadius: CGFloat = 8) {
        self.mission = mission
        self.mode = .listTile(side: fixedLength, corner: cornerRadius)
    }

    /// Grid: full-width bar with badge background; square artwork centered so the shield reads large without stretching wide.
    init(mission: Mission, gridBannerBarHeight: CGFloat, gridThumbnailSide: CGFloat) {
        self.mission = mission
        self.mode = .gridBanner(barHeight: gridBannerBarHeight, thumbSide: gridThumbnailSide)
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    /// Matches raster JPEG background (#12151c).
    private static let bannerWellColor = Color(red: 0x12 / 255, green: 0x15 / 255, blue: 0x1c / 255)

    var body: some View {
        Group {
            switch mode {
            case .listTile(let side, let corner):
                thumbSquare(corner: corner)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            case .gridBanner(let barHeight, let thumbSide):
                let topBannerRadius = GuardianCardLayout.cornerRadius
                ZStack {
                    // Square bottom so the well meets header/body hairlines flush; outer ``GuardianCard`` clips the shell.
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: topBannerRadius,
                            bottomLeading: 0,
                            bottomTrailing: 0,
                            topTrailing: topBannerRadius
                        ),
                        style: .continuous
                    )
                    .fill(Self.bannerWellColor)
                    thumbSquare(corner: 8)
                        .frame(width: thumbSide, height: thumbSide)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(maxWidth: .infinity)
                .frame(height: barHeight)
                .clipped()
            }
        }
        .task(id: thumbnailTaskID) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private func thumbSquare(corner: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(placeholderFill)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: placeholderGlyphPointSize, weight: .medium))
                        .foregroundStyle(theme.textSecondary.opacity(0.85))
                }
            }
        }
    }

    private var placeholderFill: Color {
        switch mode {
        case .gridBanner:
            return Color.white.opacity(0.06)
        case .listTile:
            return theme.backgroundElevated
        }
    }

    private var placeholderGlyphPointSize: CGFloat {
        switch mode {
        case .listTile:
            return 22
        case .gridBanner(_, let thumbSide):
            return min(30, thumbSide * 0.26)
        }
    }

    private var thumbnailTaskID: String {
        "\(mission.id.uuidString)-\(mission.cardThumbnailVersion)"
    }

    private func loadThumbnail() async {
        let url = MissionCardThumbnailSubsystem.fileURL(forMissionID: mission.id)
        let data: Data? = await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? Data(contentsOf: url)
        }.value
        if let data, let img = NSImage(data: data) {
            image = img
        } else {
            image = nil
        }
    }
}
