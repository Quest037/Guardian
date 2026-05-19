# Training panel redesign — unified lab surface

Goal: replace the split **Vehicle** / **Formation** training tabs with one **Training** surface that scales from a single vehicle → multiple vehicles → multiple squads, on a chosen built world. **World Builder** stays separate (world authoring only; no vehicles in Builder Gazebo). This panel loads a **built** environment into a **`.run`** Gazebo session and spawns SITL + sized proxies from squad rosters.

**Shipped shell:** `TrainingLabPanelView` in `FormationsPlaygroundView.swift` — idle 70/30 rail, running full-width + `AppDrawer` hosts; shared panel bodies per tab.

**Status (2026-05-19):** Phase 1–3 core items shipped. Open: Training requirements UI (Training tab).

**Cross-links:** `TrainingGazeboSimulationToDo.md`; `AppTrainingMissionSplitToDo.md`; `VehicleClassSizeToDo.md`; `WorldBuilderView.swift`.

---

## Product lock (read first)

- [x] **One Training panel** — no Vehicle vs Formation mode switch; one controller graph with optional multi-squad scope (`TrainingLabPanelView` + `TrainingLabRosterController`).
- [x] **Idle: tabbed side rail** — Gazebo viewport **~70%** + trailing rail **~30%** (`TrainingLabLayout.viewportWidthFraction`). Tabs: **Map**, **Vehicles**, **Training**, **Logs**.
- [x] **Running: full-width viewport** — side rail hidden; sub-bar drawer icons open the same panel views in `AppDrawer` (**400** pt, same tab order).
- [x] **Map first** — Vehicles drawer disabled until map selected + viewport ready; idle rail shows gate copy if Vehicles selected with no map.
- [x] **Map select in rail** — card tap → `selectEnvironmentAndLoadGazeboWorld`; re-tap selected card is a no-op (`handleTap` + controller early return).
- [x] **Built maps only** — `hasConfiguredStartAndEndZones`; incomplete maps at 50% opacity + toast; selection clamped on load.
- [x] **Run / Stop** — **Run** when idle + map + all roster slots link-ready + preflight passed; **Stop** (`stop.fill`, danger outline) ends teach/follow; map + roster stay.
- [x] **No editing while running** — `labControlsLocked` on map / vehicles panels.
- [x] **Logs** — 4th tab and 4th drawer (`TrainingLabPanelTab.logs` → `AppSection.logs.systemImage`).

---

## Phase 1 — Shell & shared panels

### Layout & shell

- [x] **`TrainingLabModels`** — `TrainingLabPanelTab`, layout constants.
- [x] **`TrainingLabPanelView`** — sub-bar, idle rail, running drawers, Run/Stop; `RootView` wired.
- [x] **`TrainingLabMapPanelContent`** — environment cards; select → load `.run` world.
- [x] Shared `trainingLabPanelContent(for:)` — map / vehicles / training / logs.
- [x] **Embedded Gazebo 3D in main column** — `.run` uses headless sim + websocket + `GazeboWebViewportView` (same policy as World Builder).
- [x] **Viewport stability** — adding vehicles does not respawn/reload the world; stable web view identity per world id.
- [x] **Sub-bar camera presets** — oblique (`view.3d`) and top-down (`view.2d`) when Gazebo viewport live; fixed orbit zoom limits in `guardian_viewer.html`.
- [x] **`resetMap()` stub** — called on idle map change before reload (`TrainingPanelController`); full reposition/clear deferred (`TrainingGazeboSimulationToDo.md` Phase 4).

### Sub-bar

- [x] Map title when environment selected.
- [x] Drawer triggers when **session running**; map-before-vehicles gate (selected + viewport ready).
- [x] Run / Stop mutual exclusion; Run gated on full roster preflight.

### Panel bodies

- [x] **Map** — catalogue cards; incomplete-world gate.
- [x] **Vehicles** — `TrainingLabVehiclesPanelContent`: squads, drag-and-drop, MCS-style cards, add-vehicle drawer, trash remove, squad settings drawer (formation policy on `TrainingLabSquad.id`).
- [x] **Training** — empty shell; requirements UI deferred (skip for now).
- [x] **Logs** — merged training + formation lines.
- [x] **Run wiring** — `applyFormationPolicyForRun` uses the **designated learning squad** `formationPolicy` before `applyFormationControl`.
- [ ] **Training requirements UI** — task, forbidden axes, skill / brain export (rebuild when UX is defined).

### Session

- [x] **`stopSessionAndReset()`** — cancel teach + `stopActiveFormationSession()`.
- [x] **`startSession()`** — learning squad with wingmen → formation follow; single-vehicle learning squad → `startAutonomousTeaching()` (other squads may remain on roster).
- [x] **Spawn path** — `TrainingLabRosterController` + `spawnTrainingLabSimulator` (`owner: .trainingRoster`); background link/preflight.

---

## Phase 2 — Controller merge & retirement

- [x] **`TrainingLabController`** — façade over `TrainingPanelController` (teaching) + `FormationsPlaygroundController` (formation); single `@StateObject` on `TrainingLabPanelView`.
- [x] Delete unused `TrainingPanelMode` in `TrainingTaskModels.swift`.
- [x] Remove dead **`controlsTab`** / legacy formation side-panel UI in `FormationsPlaygroundView.swift`.
- [x] **Map selection persistence** — `TrainingEnvironmentSelectionStore` (per task + vehicle class).
- [x] **Roster persistence** — `TrainingLabRosterStore` (squads + per-squad `taskKind` + `formationPolicy` + `learningSquadID`; draft entries without live SITL).
- [x] **Unified SITL owner tag** — `.trainingRoster` (replaces `.trainingVehicle` / `.formationsPlayground` for the lab).

### Naming (pack spacing)

- [x] **`MissionSquadFormationShape` → `MissionSquadFormationSpacing`** — tight / normal / loose; mission fields `squadFormationSpacing`; playground `spacing` property; brain pack `formation` + convoy JSON scales.

---

## Phase 3 — Viewport & polish

- [x] Embedded `GazeboWebViewportView` for Training `.run` (covered in Phase 1).
- [x] **Theme catalog block** — Theme plugin → **Training lab (unified panel)** (`ThemeCatalogContent` + sub-bar replica).
- [x] **Keyboard shortcuts** — `TrainingLabKeyboardShortcuts`: Return → Run; Escape → Stop (running, no drawer); ⌘1–⌘4 → rail/drawer tabs.
- [x] **Learning squad** — always a squad (may be one vehicle). Sub-bar **Learning** picker when multiple squads (default **Alpha**). Per-squad **task** in squad settings; teach/promote follows designated squad; formation run when that squad has wingmen.

---

## Out of scope

- World Builder terrain (`GazeboTerrainToDo.md`).
- Mission app rosters.
- Multi-world concurrent squads.
- **Training templates** — `TrainingGazeboSimulationToDo.md` → Phase 4b.

---

## References

| Area | Path |
| --- | --- |
| Shell | `Sources/GuardianHQ/Systems/Formations/Views/FormationsPlaygroundView.swift` (`TrainingLabPanelView`) |
| Lab controller | `Sources/GuardianHQ/Systems/Training/TrainingLabController.swift` |
| Map panel | `Sources/GuardianHQ/Systems/Training/Views/TrainingLabMapPanelContent.swift` |
| Vehicles panel | `Sources/GuardianHQ/Systems/Training/Views/TrainingLabVehiclesPanelContent.swift` |
| Squad settings | `Sources/GuardianHQ/Systems/Training/Views/TrainingLabSquadSettingsDrawerContent.swift` |
| Roster | `TrainingLabRosterController.swift`, `TrainingLabRosterStore.swift`, `TrainingLabRosterModels.swift` |
| Teaching / formation | `TrainingPanelController.swift`, `FormationsPlaygroundController.swift` |

---

## When this file is empty

Migrate locks to `README_FULL.md`, delete this file.
