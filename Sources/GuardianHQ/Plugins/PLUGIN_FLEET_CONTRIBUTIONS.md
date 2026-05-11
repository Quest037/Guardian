# Plugin contributions to the Fleet command & recipe catalogues

GuardianHQ loads **core** fleet commands and recipes from subsystem bootstraps (`FleetCommandsCatalogueBootstrap`, `FleetRecipesCatalogueBootstrap`). Plugins may also contribute **plugin-owned** `command.*` / `recipe.*` entries when they need namespaced fleet behaviour that ships with the integration.

Paladin intentionally keeps **empty** publish and invoke manifest arrays: it orchestrates through **core** recipes and operator surfaces (Vehicle Inspector, Mission Control, LiveDrive, MRE) rather than registering parallel Paladin-branded fleet descriptors. Other plugins that *do* own fleet rows must declare claims and align registrations.

## 1. Manifest (`GuardianPluginManifest`)

Register the plugin in `GuardianPluginBootstrap` with a `GuardianPluginManifest`:

| Field | Meaning |
| --- | --- |
| `publishedCommandNamespaces` | Dotted `command.*` prefixes this plugin may **register** in `FleetCommandsCatalogue`. Each prefix must equal `command.<GuardianPluginID/fleetNamespaceTail>` or extend it with a further `.segment` chain. |
| `publishedRecipeNamespaces` | Same for `recipe.*` under `recipe.<fleetNamespaceTail>`. |
| `invokedCommandNamespaces` | Dotted `command.*` prefixes the plugin’s **plugin-owned recipes** may dispatch via `invokeCommand` steps (and `FleetCommandsCatalogue.invoke(..., invokingPluginID:)` when used). |
| `invokedRecipeNamespaces` | Dotted `recipe.*` prefixes allowed for nested `invokeRecipe` from plugin-owned bodies. |

**Prefix match rule (publish and invoke):** a concrete name is allowed if it equals a listed prefix or begins with that prefix **plus** a dot (so `command.plugin.foo` does not match a claim on `command.plugin.foobar`).

**Empty arrays:** valid. Empty publish lists mean the plugin must not register fleet commands/recipes with a non-`nil` `pluginID`. Empty invoke lists mean any plugin-owned recipe body that calls fleet commands or nested recipes will fail parser validation unless you add matching invoked prefixes.

Validation: `GuardianPluginManifest.namespaceClaimValidationError()`; `GuardianPluginBootstrap` refuses registration when non-`nil`.

## 2. Swift descriptors

- **`FleetCommandDescriptor`**: set `pluginID: GuardianPluginID` only for plugin-owned commands. Core commands use `pluginID: nil`.
- **`FleetRecipeDescriptor`**: set `pluginID` the same way.

`FleetCommandsCatalogue.register` / `FleetRecipesCatalogue.register` reject plugin-owned names that are not covered by the plugin’s **published** prefixes in `GuardianPluginRegistry`.

## 3. JSON recipe bodies

Bodies use the shared DSL (steps, matchers, budgets). Authoring conventions for fleet subsystem JSON live next to the content:

- Calibration: `Sources/GuardianHQ/Systems/Fleet/Subsystems/Calibration/CalibrationBodies/_AUTHORING.md`
- Errors: `Sources/GuardianHQ/Systems/Fleet/Subsystems/Errors/ErrorBodies/_AUTHORING.md`

Load bodies with `FleetRecipeBodyLoader` from a **uniquely named** directory in `Package.swift` (`.copy("YourPluginBodies")`); avoid generic `Bodies` so SwiftPM resource flattening does not collide.

`FleetRecipeBodyParser.validate` runs at catalogue registration time. For **plugin-owned** descriptors, every `invokeCommand` / `invokeRecipe` step must fall under the manifest’s **invoked** prefixes. `FleetRecipeRunner` re-checks at runtime for nested recipes.

## 4. Bootstrap wiring

1. Call `GuardianPluginBootstrap.ensureRegistered()` before fleet bootstraps (already the order in `GuardianHQApp`).
2. Register plugin fleet descriptors after catalogues exist if your registration code needs to look up core dependencies; composition rules still require children to exist first.

## 5. Tests

Add or extend tests under `Tests/GuardianHQTests/` for manifest validation, catalogue rejection of out-of-claim names, and parser violations on plugin bodies. When tests temporarily replace a built-in manifest, restore with `GuardianPluginBootstrap.builtInPaladinManifest()` (or the snapshot captured in `setUp`) in `defer`.

## 6. Further reading

- `README.md` — “Fleet Commands & Recipes architecture”, bootstrap order, extension points.
- `GuardianPluginManifest.swift` — claim validation helpers (`allowsPublishing`, `allowsInvoking`).
