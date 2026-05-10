import SwiftUI

/// Theme plugin UI: full living catalog of Guardian chrome, tokens, and reusable controls.
///
/// Implementation lives in ``ThemeCatalogContent``; pair new product UI with ``GuardianUIChrome`` helpers.
struct ThemePanelView: View {
    var body: some View {
        ThemeCatalogContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
