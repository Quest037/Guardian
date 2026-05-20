# Gazebo procedural terrain — World Builder (Training app)

Goal: when an operator **creates a new world** in World Builder, they pick **map size** (`floorSize`) and **scene type** (`sceneType`), tune a **small set of scene-specific parameters** in the New World drawer, and save a training environment package whose Gazebo world uses a **deterministic heightmap terrain** (visual + collision). Generation must stay **off the main thread** and feel responsive in the macOS app.

**Supersedes:** `gazebo_procedural_terrain_v1_cursor_prompt.md` (ChatGPT draft — reference only; do not treat size tables or HTTP API as product truth).

**Cross-links:** `ToDo/TrainingGazeboSimulationToDo.md`; `README_FULL.md` → **Gazebo training simulation**; `WorldBuilderView.swift` / `WorldBuilderController.swift`; `TrainingEnvironmentFloorSize.swift`; `TrainingEnvironmentSceneType.swift`; `TrainingEnvironmentAuthoring.swift`; `TrainingEnvironmentWorldSDF.swift`; `GazeboService.swift`.

**Out of scope (v1):** caves, overhangs, mesh terrain, DEM import, manual sculpting UI, runtime terrain deformation, HTTP/REST services, terrain editor in **Edit** drawer (new-world authoring only for param UI).

---

## Product lock (Guardian)

| Topic | Decision |
| --- | --- |
| **Where it lives** | Internal to Guardian Training / HQ (`GuardianAppProduct/includesGazeboSimulation`). No external API. |
| **Vocabulary** | Manifest field **`sceneType`** (camelCase JSON, same as today). Values are terrain preset ids (see below). |
| **Map extent** | **`floorSize`** → `TrainingEnvironmentFloorSize.floorSideM` only. Do **not** use the draft prompt’s `small=1000 / medium=2000 / large=4000` table. Guardian sizes: `micro` 100 m, `small` 1000 m, `medium` ~1414 m, `large` 2000 m. |
| **Geometry** | Single-valued heightmap `z = f(x,y)`; SDFormat `<heightmap>` for **both** visual and collision (same uri, size, pos, sampling). |
| **Determinism** | `terrainSeed` (UInt32) on manifest; same seed + params + floor → same outputs. |
| **Coordinates** | Terrain centered at world origin; x/y ∈ [−side/2, +side/2] m; heightmap row↔y, col↔x (document in metadata). |
| **Package layout** | Under each environment root: `terrain/generated_terrain/` (model + textures + `metadata.json`); `world.sdf` **includes** the model (no duplicate flat box floor when heightmap is present). |
| **Flat path** | `sceneType == flat` keeps today’s open-field box **or** heightmap flat preset — pick one implementation and remove double collision. |
| **Zones** | Start/end zones (World Builder viewport) stay manifest-driven; spawn Z must use terrain height + clearance when procedural terrain is active. |
| **Performance** | Never run generation on `@MainActor` UI thread. Use background work + progress/cancel; cap default resolution per `floorSize`. |

### Scene types (v1 presets)

Ship these `sceneType` values (extend `TrainingEnvironmentSceneType`):

```text
flat
rugged
low_hills
high_hills
mountain
valley
canyon
crater
```

`flat` remains the default for new drafts and for manifests missing `sceneType`.

### Default heightmap resolution (by `floorSize`)

Odd sizes only; override allowed in advanced UI later.

| `floorSize` | Default resolution | Max v1 |
| --- | ---: | ---: |
| `micro` | 257 | 513 |
| `small` | 1025 | 2049 |
| `medium` | 1025 | 2049 |
| `large` | 2049 | 4097 |

### Scene params (manifest)

Add **`terrainParams`**: JSON object (string on manifest or nested `Codable` dictionary) — per-type keys with typed defaults applied at generation time. Add **`terrainSeed`**: optional UInt32; if absent at first generate, assign random and persist.

**New World drawer:** after **Scene type** menu, show **only the fields for the selected type** (sliders/steppers + labels; use `GuardianFormKit` / theme tokens). Hide irrelevant params. Optional **Seed** field (numeric) + **Regenerate** affordance in Build mode (later phase).

**Per-type v1 operator fields (minimum):**

| `sceneType` | Drawer fields (defaults from generator) |
| --- | --- |
| `flat` | (none beyond size) |
| `rugged` | amplitude, roughness |
| `low_hills` | amplitude, hill scale |
| `high_hills` | amplitude, ridge bias |
| `mountain` | peak height, peak count |
| `valley` | depth, width, sinuosity |
| `canyon` | depth, width, sinuosity, rim height |
| `crater` | depth, radius, rim height |

Full param schemas and build math: port from `gazebo_procedural_terrain_v1_cursor_prompt.md` preset sections; tune defaults to Guardian `floorSideM`.

---

## Phase 0 — Manifest & types

- [ ] Extend `TrainingEnvironmentSceneType` with all v1 cases + `displayName` + `parameterSchema` (or companion `TrainingEnvironmentSceneParams`).
- [ ] Add `terrainSeed: UInt32?` and `terrainParams: [String: Double]` (or JSON string) to `TrainingEnvironmentManifest` with decode defaults.
- [ ] Add `terrainResolution: Int?` optional; default via `TrainingEnvironmentFloorSize` table above.
- [ ] Validation in `TrainingEnvironmentAuthoring.validateManifest` for known keys / numeric ranges per scene type.
- [ ] Tests: decode missing `terrainSeed` / `terrainParams`; round-trip encode; invalid param rejection.

---

## Phase 1 — Terrain generator (offline tool)

Implement as a **repo Python package** invoked by the app (same pattern as `scripts/generate_vehicle_class_size_catalogue.py`), not embedded NumPy in Swift.

Suggested layout:

```text
scripts/gazebo_terrain/
  __init__.py
  models.py          # request/artifact/metadata dataclasses
  presets.py         # build_flat, build_canyon, …
  noise.py           # seeded fbm, smooth, rotate, make_grid
  export_heightmap.py # 16-bit PNG
  export_sdf.py        # model.config + model.sdf (SDF version aligned with Harmonic staging)
  terrain_query.py     # height_at, normal_at, slope_at (for tests + metadata verify)
  cli.py               # argparse entry
```

- [ ] CLI: `scripts/gazebo_terrain/cli.py generate --request <json> --out <dir>` → writes `generated_terrain/` tree + returns paths on stdout (JSON line) for Swift to parse.
- [ ] Input JSON: `{ "sceneType", "floorSideM", "seed", "resolution?", "params": {} }` — map `floorSize` → `floorSideM` in Swift before invoke.
- [ ] 16-bit grayscale heightmap; store real `min_z_m`, `max_z_m`, `height_range_m` in `metadata.json` (schema_version 1).
- [ ] Visual/collision heightmap parity in `model.sdf`; omit optional albedo/normal if not generated.
- [ ] Determinism tests (hash heightmap for fixed seed); variation test (different seeds differ).
- [ ] Document Python deps in `README_FULL.md` (numpy, pillow) and a `make terrain-generator-deps` or fold into existing dev setup.

**Non-goals:** HTTP server, long-running daemon.

---

## Phase 2 — Swift bridge (non-blocking)

- [ ] `GazeboTerrainGenerationService` (Utilities / Training): builds request JSON, runs CLI via `Process` on a **background** executor (`Task.detached` or dedicated queue), parses result.
- [ ] Cancellation: kill process if operator dismisses drawer / closes world / starts new generation.
- [ ] `WorldBuilderController`: generation state machine — `idle` / `generating` / `failed` / `ready`; `@Published` progress message + error string for drawer/toast.
- [ ] Trigger generation on **first Save** of new world (and when Save changes `sceneType`, `floorSize`, `terrainSeed`, or `terrainParams` that affect terrain — define dirty flag).
- [ ] Do **not** block Save button indefinitely — either (a) Save queues generation then writes manifest when done, or (b) Save writes manifest immediately and runs generation async before world is openable; pick (a) or (b) in implementation and document in README.
- [ ] Register generated model path for Gazebo (`GZ_SIM_RESOURCE_PATH` / package-relative `model://`) in `GazeboLaunchRecipe` / `GazeboService` when launching that environment.
- [ ] Replace `TrainingEnvironmentAuthoring.writeNewWorldFile` flat-only switch with: call generator for non-flat; compose `world.sdf` that `<include>`s `generated_terrain` + plugins; keep Harmonic-compatible SDF version with staged runtime.

---

## Phase 3 — World Builder drawer UI

- [ ] `WorldBuilderManifestForm`: conditional **Scene parameters** section under Scene type picker (new draft only).
- [ ] Bindings read/write `terrainParams` on draft manifest; reset keys when `sceneType` changes (offer confirm if values were edited).
- [ ] Optional **Seed** field (`terrainSeed`); “Randomize seed” control.
- [ ] Use menu pickers for enums; numeric fields with reasonable min/max per param schema.
- [ ] While `generating`, show inline progress in drawer (not blocking modal); disable Save or show “Generating terrain…” per chosen Save policy.
- [ ] Operator copy: no “coming soon”; disabled controls only when generation in flight or runtime missing.

---

## Phase 4 — `TerrainQuery` in Swift

Load `terrain/metadata.json` + heightmap from package root for app-side queries (spawn, validation) without Gazebo.

- [ ] `TerrainQuery` type in `Sources/GuardianHQ/Systems/Utilities/Training/` — bilinear `heightAt(xM:yM:)`, `normalAt`, `slopeDegAt`, `minSafeAltitude(minAGLM:)`.
- [ ] Unit tests with a **small** checked-in golden heightmap (micro flat or fixed rugged) to avoid huge fixtures.
- [ ] Wire zone placement / default spawn Z: when terrain metadata exists, set pose `zM = heightAt + clearance` (UGV default clearance TBD, document in README).

---

## Phase 5 — Gazebo integration & preview

- [ ] World package validator: require `terrain/generated_terrain/model.sdf` when `sceneType != flat` (or when metadata present).
- [ ] Preview/Build launch: ensure resource path includes package `terrain/` parent so `model://generated_terrain` resolves.
- [ ] Remove legacy white box floor from `world.sdf` when heightmap model is included (avoid double collision).
- [ ] Manual smoke: micro + canyon on dev machine (`make gazebo-runtime`); UGV collision not falling through; viewport loads.

---

## Phase 6 — Training / spawn consumers (after Builder works)

- [ ] `TrainingGazeboRunOrchestrator` / SITL spawn: terrain-aware spawn Z from `TerrainQuery` at `defaultSpawn` xy.
- [ ] Reject **Training `.run`** spawn when slope > vehicle profile (use `VehicleClassSize` / tier later; v1 fixed max slope constant for UGV). World Builder does not spawn vehicles.
- [ ] UAV: validate mission / waypoint AGL vs `minSafeAltitude` before dispatch (Training panel — stretch if needed for v1 Builder-only ship).

---

## Phase 7 — Nav2 / ROS (deferred)

Track under `ToDo/TrainingGazeboSimulationToDo.md` Phase 7; depends on terrain metadata.

- [ ] Export slope-derived static occupancy PGM + YAML from `TerrainQuery` for Nav2 (optional v1.5).
- [ ] Optional ROS service for height query on fleet sidecar (not required for Builder ship).

---

## Acceptance criteria (v1 done)

1. New World drawer: size + scene type + scene-specific params + optional seed.
2. Save produces a valid user package with `manifest.json`, `world.sdf`, and `terrain/generated_terrain/*` for every scene type.
3. Generation runs off the main thread; UI stays interactive; errors surface in drawer/toast.
4. Gazebo Preview/Build loads terrain; UGV collides with ground (heightmap collision).
5. Same `terrainSeed` + params + `floorSize` → identical heightmap bytes (determinism test).
6. `TerrainQuery` matches metadata normalization within test tolerance.
7. Bundled `guardian-open-field` remains `flat` (update manifest with `sceneType` + optional seed only if needed).

---

## Implementation notes

- **SDF version:** Match staged Harmonic (`TrainingEnvironmentWorldSDF` today uses 1.9 world wrapper; heightmap **model** may use 1.12 per prompt — verify against `GazeboRuntime` before locking).
- **Heightmap limits:** Canyons/cliffs are smoothed (no overhangs); document in operator help for canyon/crater types.
- **Regenerate in Build mode:** Nice-to-have after first ship; use same async service + invalidate embedded viewport session.
- **Edit drawer:** Still no start/goal fields; scene params editing for saved worlds is a later enhancement (duplicate-as-new workflow ok for v1).

---

## References

| Item | Path |
| --- | --- |
| Draft spec (reference) | `gazebo_procedural_terrain_v1_cursor_prompt.md` |
| World Builder UI | `Sources/GuardianHQ/Systems/Training/Views/WorldBuilderView.swift` |
| Controller | `Sources/GuardianHQ/Systems/Training/WorldBuilderController.swift` |
| Manifest | `Sources/GuardianHQ/Systems/Utilities/Training/TrainingEnvironmentModels.swift` |
| Floor sizes | `TrainingEnvironmentFloorSize.swift` |
| Scene types (today) | `TrainingEnvironmentSceneType.swift` |
| World SDF (today) | `TrainingEnvironmentWorldSDF.swift` |
| Zones | `WorldBuilderZoneModels.swift` |

---

## When this file is empty

Migrate locks to `README_FULL.md` (Gazebo section), delete this file.
