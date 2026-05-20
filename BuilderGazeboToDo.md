# World Builder — Gazebo scene extensions

Goal: extend **Worlds (Builder)** Gazebo authoring beyond primitives and flat/open-field floor — water surfaces, procedural terrain tied to `sceneType`, and reusable model groups (e.g. tree stands).

**Cross-links:** `TrainingGazeboSimulationToDo.md`; `GazeboTerrainToDo.md` (heightmap / `sceneType` presets); `WorldBuilderView.swift` / `WorldBuilderController.swift`; `GazeboService.swift`; `README_FULL.md` → **Gazebo training simulation**.

**Out of scope here:** vehicle spawn in Builder viewport, Training lab run loop, Formation rehearsal.

---

## Backlog

- [ ] **Water features (lake / river)** — manifest + SDF/gzweb representation for standing water (lakes) and flowing water (rivers); World Builder placement/edit UI; collision/visual policy locked per feature type; persist in environment package.
- [ ] **`sceneType` terrain mesh generator** — procedural heightmap (or mesh) generation driven by manifest `sceneType` + params; background generation, deterministic seed, package layout under `terrain/`; wire New World drawer and Build preview. See `GazeboTerrainToDo.md` for preset/param detail.
- [ ] **Model groups (trees)** — grouped instanced props (e.g. forest patches) as a first-class manifest slice; toolbar placement, bounds, and gzweb sync; baked or referenced models in the saved world.
- [ ] **Road network (polyline paths on map tile)** — Leaflet-style authoring on the open-field tile: sequential click markers, **Done** finishes the current polyline; each road is a typed record (like obstacles) with params, not a freehand brush.
  - **Params (per road or per segment — lock in implementation):** `material` (`dirt`, `asphalt`, …); `width` as lane count (`1` … `4` lanes — four lanes = two lanes each direction; map lane count → physical width in metres, e.g. standard lane width × count).
  - **Auto-join:** endpoints snap/merge within a tolerance; collinear adjacent segments on the same road collapse; T/Y intersections create shared nodes (graph), not floating duplicate vertices — document merge rules and snap radius.
  - **Terrain (required):** roads must **follow procedural terrain height** once `sceneType` meshes ship (valley, canyon, etc. — see **`sceneType` terrain mesh generator** and `GazeboTerrainToDo.md`); vertex `z` sampled from the live heightfield in Builder and rebaked on terrain regen (same seed/params). Flat open-field tile remains the degenerate case (`z ≈ 0`). Not optional “decal on a plane” only.
  - **Viewport:** gzweb overlay while drawing (rubber-band + placed vertices); committed roads as strip mesh / extruded ribbon **draped on terrain** (`MAP_SURFACE_LIFT` policy); material tint or texture per `material`; optional centreline / edge stroke for edit mode.
  - **Edit lifecycle:** select road → move/delete vertices, split, extend from open end; undo last vertex before **Done**; cancel in-progress draw; delete whole road (confirm). Stay inside map-tile XY bounds (same as zones).
  - **Persistence:** manifest slice + `world.sdf` (or included model) export; collision/visual policy per material (visual-only v1 vs driveable surface — decide before SDF bake).
  - **Open decisions:** straight segments only (Leaflet default) vs curved fillets; one-way vs two-way flag separate from lane count; overlap with zones/obstacles; cap count/length; Training path-following / costmap consumption (likely later — capture IDs only in v1).
