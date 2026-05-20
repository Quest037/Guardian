# Vehicle class sizes — footprint tiers per granular class

Goal: add a **size tier** (and concrete **footprint dimensions**) to each granular **vehicle class** (`FleetVehicleType` / roster `vehicleClass`) so the **autonomy brain** (and downstream sim/map consumers) know the physical scale they are controlling — without inventing new class codes.

**Source of truth:** [`Resources/vehicle_size_matrix.md`](Resources/vehicle_size_matrix.md) — min–max bands in **centimetres**, axes **width × length × height**, seven size bands per class, plus the **CSV block** for machine ingest. The app catalogue stores **one cm value per axis** per `(class, tier)`: the **midpoint** of each matrix min–max (computed at ingest / codegen). Ranges stay in the markdown only; runtime JSON and APIs do **not** carry min/max.

**Global tier vocabulary (fixed, seven steps):** `micro` → `mini` → `small` → `medium` → `large` → `xlarge` → `xxlarge`. Every `FleetVehicleType` maps to one matrix section:

| `FleetVehicleType` | Matrix section |
| --- | --- |
| `uavCopter` | UAV-C — Copter |
| `uavFixedWing` | UAV-F — Fixed Wing |
| `uavVTOL` | UAV-F — VTOL |
| `ugvWheeled` | UGV-W — Wheeled |
| `ugvTracked` | UGV-T — Tracked |
| `ugvLegged` | UGV-L — Legged |
| `usv` | USV |
| `uuv` | UUV |

**v1 pilot UI:** **UGV-W** and **UGV-T** first on **mission roster**; catalogue loads **all** classes for brain export, training, formation, and garage.

**Consumers (in order):** brain pack / MRE OFFBOARD → Gazebo vehicle proxies (Training / Formation **`.run`** only) → Leaflet / Cesium → ROS / Nav2 (optional). All use the same three integers.

**Gazebo split (product lock):** Both surfaces use Harmonic, but **World Builder** (``.build`` / ``.preview``) is **world authoring only** — terrain, obstacles, start/goal zones — **no vehicles** in the Builder viewport. **Training** and **Formation** load a built environment in a **``.run``** session and spawn **vehicle proxy blocks** (``GazeboService/spawnVehicleProxy``) sized from the catalogue. Do not add vehicle spawn or footprint-driven vehicle meshes to World Builder.

**Out of scope:** reserve swap tier matching; changing class codes; per-tier min/max in app models; auto-classify from measured assets (matrix classification rule is later).

**Cross-links:** `Resources/vehicle_size_matrix.md`; `README_FULL.md`; `FleetVehicleModel.swift`; `Mission.swift`; `ToDo/TrainingGazeboSimulationToDo.md`; `CesiumJSMapIntegrationReadMe.md`; `README_AUTONOMY.md`.

---

## Product lock

Shipped in code + `README_FULL.md`. Default tier **medium**; nearest-integer cm midpoints at codegen; no min/max in runtime models. Mission roster tier picker on **UGV-W** / **UGV-T**; training + formation tier on all selectable classes.

---

## Phase 3 — Gazebo vehicle proxies (Training / Formation `.run` only)

- [ ] **Training `.run` spawn** — sized proxy blocks + terrain clearance / slope checks using footprint cm (tier from Training controls).
- [ ] **Multi-vehicle `.run`** — squad spacing from largest participant max axis.

*(World Builder may later show a **reference** W×L×H hint when placing zones/obstacles — not a Gazebo vehicle; out of scope until needed.)*

---

## Phase 4 — Map display (2D now, 3D later)

- [ ] **Leaflet** — glyph from W×L×H cm.
- [ ] **MC-R / Live Drive** — assignment footprint from catalogue.
- [ ] **Cesium** — same triple at render boundary.

---

## Phase 5 — MRE & OFFBOARD control

- [ ] **Brain execution** — planner hints use footprint cm.
- [ ] **Manual control** (optional) — tier or footprint buckets.
- [ ] **Squad follow / convoy** — offsets from participant triples.
- [ ] **Operator prompts** (optional) — size-aware copy.

---

## Phase 6 — ROS 2 / Nav2 bridge (optional v1.1)

- [ ] **Bridge config** — `size_tier` + cm triple on vehicle entry.
- [ ] **`vehicle_config.py`** — cm → Nav2 footprint metres.
- [ ] **Fleet dispatch** — pass footprint on sidecar enroll.

---

## Phase 7 — Docs, hygiene, smoke

- [ ] **Theme strings** — Micro … XXLarge + `W×L×H cm` hint in Theme catalogue.
- [ ] **Manual smoke** — brain pack matches catalogue; UGV-W micro vs xxlarge visibly different.
- [ ] **Trim this file** — per `todo-list-hygiene.mdc`.

---

## Open questions

| Topic | Notes |
| --- | --- |
| Midpoint rounding | Nearest integer vs floor (lock in codegen) |
| Per-class tier subset in UI | Hide tiers in picker later? |
| Rotation | Map box axis-aligned vs vehicle heading |
| Mass / inertia | Gazebo: scale with volume or separate field |
| Plugin classes | Plugin manifest rows vs codegen-only |
| Matrix updates | Regenerate catalogue when CSV block changes |

---

## References

| Area | Path |
| --- | --- |
| **Size matrix (SoT)** | `Resources/vehicle_size_matrix.md` |
| Granular class enum | `FleetVehicleModel.swift` |
| Roster template | `Mission.swift` (`RosterDevice`) |
| Tier picker UI | `VehicleSizeTierField.swift` |
| Training picker | `TrainingTaskModels.swift` |
| Brain export | `GuardianBrainPack` / `README_FULL.md` |
| Map glyphs | `GuardianMapVehicleGlyphKind.swift`, `OSMMapView` |
| Sim presets | `SimulationCatalog.swift` |
| ROS class string | `vehicle_config.py`, `Ros2BridgeConfiguration.swift` |

---

## When this file is empty

Migrate retained locks to `README_FULL.md`, delete this file.
