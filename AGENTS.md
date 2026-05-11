# Agent notes (Guardian)

This repo keeps product and AI guardrails in **`.cursor/rules/`**. When editing GuardianHQ (especially SwiftUI):

- **Theme & tokens:** `.cursor/rules/guardian-theme-tokens.mdc` — use `GuardianTheme.palette`, `GuardianSemanticColors`, `GuardianSpacing`, `GuardianTypography`, and related design-system types when they exist instead of inventing parallel styling.
- **Shared utilities:** `.cursor/rules/global-utilities-placement.mdc` — reusable helpers for multiple systems/plugins go under `Sources/GuardianHQ/Systems/Utilities/` and the `Utilities` / `GlobalUtilities` namespace.
- **Buttons:** `.cursor/rules/button-semantic-colors.mdc`
- **Drawers:** `.cursor/rules/app-drawer.mdc`
- **Modals / confirms:** `.cursor/rules/modal-central-template.mdc`, `.cursor/rules/guardian-confirm-dialogs.mdc`
- **Build / version / missions / tests:** See the other rules in `.cursor/rules/` as relevant.

**Theme reference:** use the in-app **Theme** plugin (`ThemePanelView` / `ThemeCatalogContent`) as the living catalog; rules live in `guardian-theme-tokens.mdc` above.
