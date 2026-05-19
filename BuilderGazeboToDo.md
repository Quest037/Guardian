# World Builder — Gazebo scene extensions

Goal: extend **Worlds (Builder)** Gazebo authoring beyond primitives and flat/open-field floor — water surfaces, procedural terrain tied to `sceneType`, and reusable model groups (e.g. tree stands).

**Cross-links:** `TrainingGazeboSimulationToDo.md`; `GazeboTerrainToDo.md` (heightmap / `sceneType` presets); `WorldBuilderView.swift` / `WorldBuilderController.swift`; `GazeboService.swift`; `README_FULL.md` → **Gazebo training simulation**.

**Out of scope here:** vehicle spawn in Builder viewport, Training lab run loop, Formation rehearsal.

---

## Backlog

- [ ] **Water features (lake / river)** — manifest + SDF/gzweb representation for standing water (lakes) and flowing water (rivers); World Builder placement/edit UI; collision/visual policy locked per feature type; persist in environment package.
- [ ] **`sceneType` terrain mesh generator** — procedural heightmap (or mesh) generation driven by manifest `sceneType` + params; background generation, deterministic seed, package layout under `terrain/`; wire New World drawer and Build preview. See `GazeboTerrainToDo.md` for preset/param detail.
- [ ] **Model groups (trees)** — grouped instanced props (e.g. forest patches) as a first-class manifest slice; toolbar placement, bounds, and gzweb sync; baked or referenced models in the saved world.
