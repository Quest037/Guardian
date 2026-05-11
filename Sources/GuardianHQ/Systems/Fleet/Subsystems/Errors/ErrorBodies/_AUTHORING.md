# Errors recipe bodies

Per-recipe JSON files parsed by `FleetRecipeBodyParser` and loaded via
`FleetRecipeBodyLoader` from the subsystem's `registerAll()`. See README
"Layer 1 subsystems" for the hybrid contract; this directory holds the
**body half**.

The directory is named `ErrorBodies` rather than just `Bodies` because SPM
flattens `.copy(<dir>)` resources to the bundle root — each subsystem needs
a uniquely-named bodies directory.

## File naming

Each file is named after the recipe it implements:

```
ErrorBodies/<recipe.name>.json
```

Examples:

- `recipe.fleet.errors.fix.calibrationrequired.json`

The loader resolves the file by `recipeName.rawValue`, so the filename and
the recipe's registered name must match exactly.

## Body shape

See `Calibration/CalibrationBodies/_AUTHORING.md` for the full `FleetRecipeBody`
JSON shape — the body schema is identical across subsystems. Error-fix recipes
typically lean more heavily on `invokeRecipe` steps (composing the matching
`recipe.fleet.calibrate.*` children) than calibration recipes do.

## Validation

The loader only **decodes** the JSON. Structural validation happens inside
`FleetRecipesCatalogue.register(...)` when the parent descriptor is registered.
Bodies that fail validation cause registration to be refused and the failure
is logged.

## Content shipped so far

The subsystem ships a single recipe today; it doubles as the first composite
(invokeRecipe-bearing) recipe in the whole catalogue, so it also serves as the
worked example of the recipe-of-recipe composition path.

- `recipe.fleet.errors.fix.calibrationrequired.json` — 600s budget; four
  sequential `invokeRecipe` steps:
  `cal-compass` → `cal-accel` → `cal-gyro` → `verify-armprobe`. Every
  intermediate step matches `success → continueToNextStep` and falls through
  any other outcome to `fail` with a descriptive detail; the verify step's
  `success → succeed` ends the recipe. The `containsRecipes` field is filled
  in (compass, accelerometer, gyro, armprobe) so the catalogue's registration
  check enforces 1-level composition depth in both directions — children
  must be registered and atomic. cancelRecipe is `recipe.fleet.calibrate.cancel`
  because the dominant cancel point is mid-calibration; asking the autopilot
  to abort an in-progress cal is the right cleanup for the bulk of the
  recipe's run time.

The subdirectory name is exposed as
`FleetErrorRecipeRegistrations.bodiesSubdirectoryName` so production callers
and tests reference the same string.
