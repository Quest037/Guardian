import SwiftUI

extension View {
    func uniformIconButton(width: CGFloat = 36, height: CGFloat = 30) -> some View {
        frame(width: width, height: height, alignment: .center)
    }
}

extension Image {
    func appIconGlyph() -> some View {
        font(GuardianTypography.font(.sectionHeadingSemibold))
            .frame(width: 16, height: 16, alignment: .center)
            .contentShape(Rectangle())
    }
}
