import SwiftUI

/// Theme plugin UI: full living catalog of Guardian chrome, tokens, and reusable controls.
///
/// Implementation lives in ``ThemeCatalogContent``; pair new product UI with ``GuardianUIChrome`` helpers.
///
/// ## Theme plugin checklist (Theme §14.2)
///
/// When adding a **new design token** or shared chrome type:
/// 1. Land the API in the design system (or appropriate module) with DocC-friendly comments.
/// 2. Add a **catalog section** (or extend the nearest existing section) in ``ThemeCatalogContent`` — short prose, live control or swatch where practical, and ``ThemeAPICaption`` listing the public symbols.
/// 3. Manually verify **light and dark** appearance for that block; if CI later captures Theme screenshots, add both schemes there.
struct ThemePanelView: View {
    var body: some View {
        ThemeCatalogContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
