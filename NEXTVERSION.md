# Next version

Deferred product and engineering ideas for a future release. Entries are appended here when the operator says **(save for next version)** in chat (see `.cursor/rules/next-version-capture.mdc`).

---

<!-- New entries: append below, one block per capture. Newest last. -->

## 2026-05-11 — Commands & Recipes deferred catalogue / bus ideas

- **Idea:** Park the old **Deferred / Out of Scope** list from `CommandsRecipesToDo.md`: `subscribe` verb for streaming catalogue responses; cross-system bus extensions (`command.mc.*`, `command.plugin.*` outside Fleet); **partial-success** recipe outcomes; **recursive composition** beyond the locked one-level-each-side cap; a **richer plugin permission model** than manifest namespace claims alone; **auto-discovered recipe dependency graph** for plugins. Separately, explore an **MRE planner** morph toward a deeper **recipe-executor** architecture (planner-level composition / scheduling) — distinct from the **MissionRunEnvironment executor → catalogue** forward-port, which is the **current** build track in `CommandsRecipesToDo.md` → *MRE recipe executor*.
- **Context:** `CommandsRecipesToDo.md` now tracks **Stage E (Vehicle Inspector wizard)** and **MRE recipe executor** only; these items were moved here so the tracker stays execution-focused.
- **Notes:** Mission `subscribe` / stream verbs remain under `TODO.md` → **FleetCommands** where applicable.

## 2026-05-10 — Per-step cancel-cleanup hooks in recipes

- **Idea:** Add an **optional, per-step** cancel-cleanup field on `.invokeCommand` and `.invokeRecipe` steps in the recipe DSL, alongside the existing recipe-level `FleetRecipeDescriptor.cancelRecipe`. Authors should be able to declare step-local cleanup, recipe-level cleanup, both, or neither — it must remain optional in every shape.
- **Context:** `Sources/GuardianHQ/Systems/Fleet/Subsystems/RecipesCatalogue/` — `FleetRecipeStep.swift` (new optional field per case), `FleetRecipeBodyParser.swift` (validate the new field + reject composite or cleanup-of-cleanup targets), `FleetRecipeRunner.swift` (per-step cleanup runs before recipe-level cleanup when both are declared). README "Layer 1 runner" section documents the current single-cleanup behaviour and is the right place to extend.
- **Notes:** Resolution rule when both declared: per-step cleanup first, then recipe-level. Parser must apply the same atomic-only / no-self-reference constraints used today for `cancelRecipe`. No DSL or runtime work in v1 — v1 ships only the recipe-level field.

## 2026-05-11 — MC Grid live-overview view with universal prompt panel

- **Idea:** Add a new variant of MC Grid that acts as an **active live-mission overview** — shows all running missions with updating stats and hosts a contextless `GuardianPromptPanel` instance. Because this view has no single-mission context, the prompt panel serves as an unbounded open panel that the Stage D `OperatorPromptRouter` can target for **any** live prompt rather than filtering by operator focus.
- **Context:** `Sources/GuardianHQ/Systems/MissionControl/Views/` — new view alongside the existing MC Grid. Pairs with the Stage D `OperatorPromptRouter` panel-routing logic; the router treats this view's panel as a wildcard target equivalent to "any live mission's prompts welcome here". MCR / LiveDrive panels remain filtered to their own run/vehicle context.
- **Notes:** Generic `GuardianPromptPanel` template (the Stage D base UI) must already exist; this view just supplies the panel slot and tells the router its policy. Save until Stage D ships and the panel template is stable.

## 2026-05-11 — Button hover colouring by default

- **Idea:** Ship **default hover colouring** for app buttons — slightly darker on hover in light mode and slightly lighter in dark mode — implemented once in shared design-system paths (extend the existing `.onHover` in `GuardianPointerPlainButtonStyle` / `guardianPointerOnHover()`, and/or `GuardianThemedButton`) so call sites do not need per-file hover wiring.
- **Context:** `Sources/GuardianHQ/General/DesignSystem/GuardianButtonCursor.swift`, `GuardianUIChrome.swift` (`GuardianThemedButton`, `GuardianThemedButtonStrip`). Prior discussion: system `.bordered` / `.borderedProminent` already have Apple hover; custom token-aligned hover may still want migration of those controls over time.
- **Notes:** Prefer a single hover handler (cursor + visual together) to avoid stacked `.onHover`. Validate `brightness` / opacity on flat themed fills vs. busy labels; tune so it does not fight semantic colours (primary / danger).

