# Training app — Gazebo worlds, World Builder, and simulate tabs

Goal: **Guardian Training** is an autonomy lab with three cooperating surfaces:

1. **Worlds (Builder)** — author, validate, and save training environments (Gazebo scenes + anchors). **No vehicles** in the Builder Gazebo viewport — world geometry only.
2. **Training (Vehicle)** — pick a saved **built** environment, run skill teaching (``.run`` Gazebo world + PX4 SITL + sized vehicle proxy blocks).
3. **Formation** — rehearse squads in a chosen environment (same **``.run``** + vehicle proxies as Training).

**Today:** **Worlds** + World Builder with embedded 3D viewport (headless `gz sim -s` + websocket + `gzweb` in-panel). **Training lab** loads the same embedded stack for `.run` when a map is chosen (`TrainingLabPanelView`). Portable Gazebo bundle deferred.

**Cross-links:** `README_FULL.md` → **Gazebo training simulation**; `AppTrainingMissionSplitToDo.md`.

---

## Phase 3b — World Builder viewport (shipped)

- Embedded panel: `GazeboWebViewportView` + offline `dist/gzweb.bundle.mjs` (`make gzweb-viewer` to regenerate).
- Preview / Build use server-only sim + Harmonic websocket bridge (not a separate Gazebo window).
- **Dev prerequisite (macOS Homebrew):** `brew install libwebsockets && brew reinstall gz-launch7` then `make gazebo-runtime` — without `libgz-launch-websocket-server.dylib`, `gz launch` cannot serve gzweb (sim server still runs).

---

## Phase 4 — Training: vehicle in environment

- [x] **Embedded 3D viewport** — same stack as World Builder in Training lab (`GazeboSessionLaunchPolicy` + `TrainingLabPanelView`).
- [ ] **`resetMap()`** — reposition vehicles in Gazebo, clear episode artifacts on idle map change (stub wired from map select).
- [ ] **PX4 pose in Gazebo** — align SITL spawn with environment `defaultSpawn` (bridge / model pose).
- [ ] **Teaching loop** — metrics from sim truth (not map geodesic alone).
- [ ] **Target slot in world** — edit goal in Gazebo or inspector when map is hidden.

---

## Phase 4b — Training templates (save & re-run)

Let operators **save the current lab setup as a named template** and **load it later** to re-run the same training without binding a map to a single skill or scenario.

**Persist (v1 shape — extend as the lab gains fields):**

| Slice | Contents |
| --- | --- |
| **Map reference** | `TrainingEnvironmentManifest` id (or stable catalogue key) — **reference only**; the same map can be reused across many templates and skills. |
| **Vehicle roster** | Squads (ids/labels), entries (vehicle class, size tier, slot roles), per-squad formation policy (start/end formation + spacing). |
| **Training requirements** | Task kind, forbidden axes, teaching options, brain-export prefs — whatever the **Training** rail controls today. |
| **Future fields** | Waypoints, goal slots, geofences, episode limits, etc. — template schema should version or use optional keys so new lab fields slot in without migration theatre. |

**Product rules:**

- Saving a template does **not** claim exclusive ownership of a map or environment file.
- Loading a template restores lab state (map ref + roster + requirements); operator may change map or vehicles before **Run**.
- Templates live in Training app storage (catalogue file or `TrainingTemplateStore` — pick one store on implementation; not embedded in the world manifest).

**UI (deferred detail):** Save / Load / Duplicate / Delete from Training rail or sub-bar overflow; confirm on delete (`GuardianConfirmDanger`).

**Cross-links:** `TrainingUnifiedPanelToDo.md` (unified lab); `VehicleClassSizeToDo.md` (tier in roster); session persistence item in Phase 2 there.

---

## Phase 5 — Formation: squad in one world

- [ ] Catalogue + squad offsets; multi-vehicle `.run` world; 3D viewport; leave-tab contract.

### Squad formation slots in map start/end zones

Place each squad’s **start** and **end** formation slot groups inside the world’s authored **start** and **end** zones (from `manifest.json` / World Builder zone editor), not as free-floating map pins unrelated to the environment.

- [ ] **Start zone** — squad start formation slot group is authored/placed within the map start zone disc (respect zone center, radius, shape).
- [ ] **End zone** — squad end formation slot group within the map end zone (same rules).
- [ ] **Drag + rotate (Training Formation map parity)** — reuse the interaction model the old **Training Formation** Leaflet map used: drag the **formation group center** within the zone; drag a **heading** handle to rotate the slot layout. Implementation anchor: `GuardianFormationSlotGroupMapEdit` + `onFormationSlotGroupCenterMoved` / `onFormationSlotGroupHeadingMoved` (`FormationsPlaygroundView` / `OSMMapView`); port equivalent affordances to the **Gazebo** lab viewport when Formation/Training runs on the embedded 3D map.
- [ ] **Policy-driven slot layout** — when the operator changes a squad’s **start/end formation policy** in the **settings drawer** (`TrainingLabSquad.formationPolicy` — formation shape + spacing), recompute and refresh the displayed slot positions/heading for that squad in the matching zone without requiring a manual re-place. Same policy → same geometry as `FormationsPlaygroundController` formation preview / `buildFormationSlotTargetMarkers` today.

**Cross-links:** `TrainingUnifiedPanelToDo.md` (squad settings drawer, Run wiring); `WorldBuilderView` / zone manifest (`startZoneConfigured`, `endZoneConfigured`); `TrainingPanelController.buildTargetSlotMapEdit()` (existing slot-group edit helper).

---

## Phase 6 — Multiple connected squads

- [ ] Squad identity; world strategy; switcher; collision groups; scale warnings.

---

## Phase 3c — Procedural terrain (World Builder)

- [ ] **Tracker:** `GazeboTerrainToDo.md` — heightmap presets, manifest `sceneType` + `terrainParams`, async Python generator, New World drawer params, `TerrainQuery`, Gazebo include path.

---

## Phase 7 — Nav2, costmaps, autonomy

- [ ] Costmap from Gazebo; planner goals; formation terrain; health chips (slope map export — see `GazeboTerrainToDo.md` Phase 7).

---

## Phase 8 — Polish

- [ ] Remove Leaflet when 3D default; Theme catalog; manual smoke; trim `TODO.md`.
- [ ] **Portable GazeboRuntime** — relocatable bundle (no Homebrew on operator machine).

---

## Open questions (before Phase 4 viewport)

| Topic | Notes |
| --- | --- |
| Viewport tech | Metal vs `WKWebView` / gz-web |
| Geodetic bridge | ENU vs WGS84 for Nav2 handoff |
| UAV worlds | v1 UGV-focused |
| Physics rate | real-time vs accelerated |

---

## References

| Area | Path |
| --- | --- |
| World Builder | `WorldBuilderView.swift`, `WorldBuilderController.swift` |
| Environments | `TrainingEnvironmentCatalogue.swift` |
| Gazebo | `GazeboService.swift`, `GazeboSessionPurpose.swift` |

---

## When this file is empty

Migrate locks to `README_FULL.md`, delete this file.
