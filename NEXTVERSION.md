# Next version

Deferred product and engineering ideas for a future release. Entries are appended here when the operator says **(save for next version)** in chat (see `.cursor/rules/next-version-capture.mdc`).

---

<!-- New entries: append below, one block per capture. Newest last. -->

## 2026-05-10 — Per-step cancel-cleanup hooks in recipes

- **Idea:** Add an **optional, per-step** cancel-cleanup field on `.invokeCommand` and `.invokeRecipe` steps in the recipe DSL, alongside the existing recipe-level `FleetRecipeDescriptor.cancelRecipe`. Authors should be able to declare step-local cleanup, recipe-level cleanup, both, or neither — it must remain optional in every shape.
- **Context:** `Sources/GuardianHQ/Systems/Fleet/Subsystems/RecipesCatalogue/` — `FleetRecipeStep.swift` (new optional field per case), `FleetRecipeBodyParser.swift` (validate the new field + reject composite or cleanup-of-cleanup targets), `FleetRecipeRunner.swift` (per-step cleanup runs before recipe-level cleanup when both are declared). README "Layer 1 runner" section documents the current single-cleanup behaviour and is the right place to extend.
- **Notes:** Resolution rule when both declared: per-step cleanup first, then recipe-level. Parser must apply the same atomic-only / no-self-reference constraints used today for `cancelRecipe`. No DSL or runtime work in v1 — v1 ships only the recipe-level field.

