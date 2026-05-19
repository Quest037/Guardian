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

**v1 pilot UI:** **UGV-W** and **UGV-T** first; catalogue loads **all** classes from the matrix for brain export and future surfaces.

**Example catalogue values (midpoints from matrix, W × L × H cm):**

| Class | Tier | widthCm | lengthCm | heightCm |
| --- | --- | ---: | ---: | ---: |
| UGV-W | medium | 160 | 265 | 125 |
| UGV-T | xlarge | 385 | 775 | 290 |
| UAV-C | micro | 12 | 12 | 6 |

**Consumers (in order):** brain pack / MRE OFFBOARD → Gazebo → Leaflet / Cesium → ROS / Nav2 (optional). All use the same three integers.

**Out of scope:** reserve swap tier matching; changing class codes; per-tier min/max in app models; auto-classify from measured assets (matrix classification rule is later).

**Cross-links:** `Resources/vehicle_size_matrix.md`; `README_FULL.md`; `FleetVehicleModel.swift`; `Mission.swift`; `TrainingGazeboSimulationToDo.md`; `CesiumJSMapIntegrationReadMe.md`; `README_AUTONOMY.md`.

---

## Product lock (decide before Phase 1 ships)

- [ ] **Size is orthogonal to class** — `FleetVehicleType` + `VehicleSizeTier` + `VehicleFootprint`.
- [ ] **Fixed tier vocabulary** — `micro` … `xxlarge`; catalogue rows derived **only** from `vehicle_size_matrix.md`.
- [ ] **Canonical storage = three integers, cm, W × L × H** — `widthCm`, `lengthCm`, `heightCm` only (no min/max fields in Swift, JSON, or brain pack). Values = **round or floor midpoint** `(min + max) / 2` per matrix cell at codegen time; document rounding rule in ingest (recommend **nearest integer cm**).
- [ ] **Default tier = medium** — unset picks → **medium** for that class.
- [ ] **One Codable shape** — tier + footprint cm; no legacy decode.
- [ ] **Reserve swap / pool** — no tier policy; size is for **brain + spatial consumers** only.
- [ ] **Matrix axis semantics** — ingest respects matrix notes (rotor span, wingspan, hull length, etc.) when reading source tables; stored triple is still W×L×H midpoints.

---

## Phase 0 — Model & catalogue

- [ ] **Ingest / codegen** — parse `Resources/vehicle_size_matrix.md` CSV block → emit `VehicleClassSizeCatalogue` with midpoint `widthCm` / `lengthCm` / `heightCm`; tests fail if matrix changes without regenerating.
- [ ] **`VehicleSizeTier`** — seven cases, matrix Size Bands order.
- [ ] **`VehicleFootprint`** — `widthCm`, `lengthCm`, `heightCm`; `Equatable`, `Codable`, `Sendable`.
- [ ] **`VehicleClassSizeCatalogue`** — all `FleetVehicleType` × seven tiers; `footprint(vehicleClass:tier:)`, `defaultTier(for:)` → `.medium`, `footprintMetres(...)`.
- [ ] **Bundle** — generated catalogue (and/or matrix snapshot) in SwiftPM resources for shipped apps.
- [ ] **Tests** — pin midpoints for UGV-W medium (160, 265, 125), UAV-C micro (12, 12, 6), UGV-T xlarge (385, 775, 290); monotonic max axis across tiers per class; unknown class → conservative fallback triple.

---

## Phase 1 — Authoring & settings UI

- [ ] **Mission roster** — `vehicleSizeTier`; tier picker + single footprint hint (e.g. `160 × 265 × 125 cm`); default **medium**.
- [ ] **Training panel** — class + tier; default **medium**; hint from catalogue triple.
- [ ] **Formation playground** — tier on slots for spacing.
- [ ] **Fleet garage** — optional tier when spawn knows it.
- [ ] **General settings** — optional default tier per class (**medium**).

---

## Phase 2 — Persistence & run envelope

- [ ] **`RosterDevice` encode/decode** — `vehicleSizeTier`; absent → **medium**.
- [ ] **Run truth** — `VehicleFootprint` cm copied at bind time.
- [ ] **Brain pack export** — tier + `widthCm` / `lengthCm` / `heightCm` in metadata / `planner_hints` (no ranges).

---

## Phase 3 — Gazebo & SITL spawn

- [ ] **Spawn policy** — catalogue cm → world metres.
- [ ] **SDF / templates** — scale from `(class, tier)` triple.
- [ ] **World Builder** — show W×L×H cm; clearance warning v1.
- [ ] **Multi-vehicle worlds** — squad spacing from largest participant max axis.

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

- [ ] **`README_FULL.md`** — matrix as SoT, midpoint-at-ingest rule, single cm triple, medium default.
- [ ] **Theme strings** — Micro … XXLarge + `W×L×H cm` hint.
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
| Training picker | `TrainingTaskModels.swift` |
| Brain export | `GuardianBrainPack` / `README_FULL.md` |
| Map glyphs | `GuardianMapVehicleGlyphKind.swift`, `OSMMapView` |
| Sim presets | `SimulationCatalog.swift` |
| ROS class string | `vehicle_config.py`, `Ros2BridgeConfiguration.swift` |

---

## When this file is empty

Migrate retained locks to `README_FULL.md`, delete this file.
