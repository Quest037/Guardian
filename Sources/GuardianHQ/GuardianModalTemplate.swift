import SwiftUI

/// Shared modal shell used across sheets/popovers for consistent visual structure:
/// header (title + optional subtitle left, actions right) + body content.
struct GuardianModalTemplate<BodyContent: View, HeaderActions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let headerActions: () -> HeaderActions
    @ViewBuilder let bodyContent: () -> BodyContent

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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gray.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                headerActions()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .opacity(0.2)

            bodyContent()
                .padding(18)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }
}
