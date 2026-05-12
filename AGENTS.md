# Agent notes (Guardian)

This repo keeps product and AI guardrails in **`.cursor/rules/`**. When editing GuardianHQ (especially SwiftUI):

- **Plugin-owned fleet catalogue rows:** ``Sources/GuardianHQ/Plugins/PLUGIN_FLEET_CONTRIBUTIONS.md`` (manifest claims, JSON bodies, bootstrap).
- **Mission Control floating reserve pool (run envelope):** ``README.md`` → **Floating reserve pool (Mission Control run)**; deferred automation in ``NEXTVERSION.md`` → **Floating reserve pool — deferred phases** (2026-05-12).
- **Mission Control reserve swap-in (live active ↔ reserve):** backlog for arm/mission/reposition/commit pipeline, fixed `.reserve` + floating pool, triggers, and class matching — ``MissionRosterReservesToDo.md``.

- **Theme & tokens:** `.cursor/rules/guardian-theme-tokens.mdc` — use `GuardianTheme.palette`, `GuardianSemanticColors`, `GuardianSpacing`, `GuardianTypography`, and related design-system types when they exist instead of inventing parallel styling.
- **Shared utilities:** `.cursor/rules/global-utilities-placement.mdc` — reusable helpers for multiple systems/plugins go under `Sources/GuardianHQ/Systems/Utilities/` and the `Utilities` / `GlobalUtilities` namespace.
- **Buttons:** `.cursor/rules/button-semantic-colors.mdc`
- **Drawers:** `.cursor/rules/app-drawer.mdc`
- **Modals / confirms:** `.cursor/rules/modal-central-template.mdc`, `.cursor/rules/guardian-confirm-dialogs.mdc`
- **Build / version / missions / tests:** See the other rules in `.cursor/rules/` as relevant.
- **Operator copy:** `.cursor/rules/no-future-version-user-copy.mdc` — no “future build” / “coming soon” teases in UI; describe the current product only.

**Theme reference:** use the in-app **Theme** plugin (`ThemePanelView` / `ThemeCatalogContent`) as the living catalog; rules live in `guardian-theme-tokens.mdc` above.
