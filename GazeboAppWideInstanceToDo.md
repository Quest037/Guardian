# Gazebo — single app-wide headless instance (world swap, not sim restart)

Goal: **one** long-lived headless `gz sim` + **one** gz-launch websocket bridge (instance **0**, shared port) for all embedded maps in **World Builder** and **Training lab**. Changing environment, floor preset, or panel must **swap world content inside that process**, not start/stop `gz sim` on every map pick. Reduces freezes, port races, and orphan `gz` children after force quit.

**Does not replace:** `TrainingGazeboSimulationToDo.md` (features, PX4-in-world, templates, Formation). **Defers:** portable runtime bundle, procedural terrain (`GazeboTerrainToDo.md`), second concurrent sim for parallel maps.

**Cross-links:** `README_FULL.md` → **Gazebo training simulation**, **Child processes and cold launch**; `TrainingGazeboSimulationToDo.md`; `Sources/GuardianHQ/Infrastructure/Simulation/GazeboService.swift`, `GazeboEntityFactoryClient.swift`, `GuardianGazeboOrphanBlitz.swift`; `WorldBuilderController.swift`, `TrainingPanelController.swift`; `Resources/GazeboWeb/guardian_viewer.html`.

---

## Product lock (target)

| Topic | Decision |
| --- | --- |
| **Sim count** | At most **one** embedded headless `gz sim` while the Training app (or HQ with Gazebo) is running and any Builder/Training viewport may open. Non-embedded `.run` worlds (future Formation split) stay behind explicit policy — v1 embedded path only. |
| **Instance / port** | Keep **instance 0** + `GazeboLaunchRecipe.websocketPort(forInstanceIndex: 0)`; single `GZ_PARTITION` / `GZ_IP=127.0.0.1` partition for sim + bridge. |
| **Map change** | **World handoff** inside the live sim: clear runtime entities, replace static floor / world identity as needed, repopulate from manifest — **not** `stopAllEmbeddedViewportWorldsCompletely()` on every `selectPackage` / Training map pick. |
| **Panels** | Builder (`.build` / `.preview`) and Training (`.run`) **share** the same sim when only one embedded map is active (current UX). Switching sidebar section **hands off** the same process; does not spawn a second embedded sim for the other panel. |
| **Simulate gate** | Training `.run` still requires Simulate on; Builder does not. Handoff must not require Simulate for builder-only preview. |
| **Vehicles in sim** | Builder: obstacles + zones only (no `spawnVehicleProxy`). Training idle: map only; **Run** spawns proxies via existing `buildMap` / `resetMap`. Handoff must strip proxies when leaving Training or loading a builder map. |
| **Failure** | If handoff fails after bounded retries, fall back to **controlled full restart** (today’s path) and log; operator sees one clear error, not a wedged viewport. |

---

## Today (why restarts hurt)

- `GazeboService.spawnWorld` stops **all** embedded worlds (`stopEmbeddedViewportWorlds`) when reuse checks fail.
- `WorldBuilderController.selectPackage` always `stopGazeboSession()` before loading the next package.
- `floorSizeDidChange()` stops the sim to reload `world.sdf`.
- Reuse exists (`canReuseEmbeddedWorld`) but is bypassed on catalogue pick and floor change.
- Runtime API: `/world/<name>/create`, `/remove/blocking`, `set_pose`, `gz model --list` — **no** full-world clear or floor replace.
- `open_field_floor` is **static** in initial `world.sdf`; obstacles are runtime `guardian_obstacle_*`.
- README lock: partial terminate left **merged scenes in gzweb**; orphan blitz ordering can SIGTERM the **new** sim (exit 15) if handoff suppress is wrong.

---

## Architecture — ownership

- [ ] **`GazeboAppWideSession`** (name TBD) — single `@MainActor` coordinator owned by `GazeboService` (or nested type): alive runner PID, Harmonic world name, loaded `environmentID`, `floorSizeLabel`, `worldFilePath`, purpose set (builder vs run), handoff generation / revision.
- [ ] **One `embeddedViewport` state** — bridge world id matches app-wide session; both `WorldBuilderController` and `TrainingPanelController` resolve “the” embedded world through this coordinator, not independent spawn/stop.
- [ ] **`GazeboWorldHandoff`** — pure policy + steps: classify transition (same world file touch, env id change, floor change, panel-only, quit); run ordered swap pipeline or escalate to full restart.
- [ ] **Deprecate per-orchestrator kill-first** — `selectPackage`, Training map change, and `spawnWorld` must call **handoff** first; full stop only on leave-app, Simulate off (run worlds), explicit operator “reload sim”, or handoff failure.

---

## Phase A — Harmonic world-swap spike (prove on dev machine)

Validate APIs on staged Harmonic before UI wiring.

- [ ] Document services on a live headless sim: `gz service -l` (or project script) for `/world/<name>/remove`, `/create`, `/control`, scene topic.
- [ ] **List + remove** all models except policy allowlist (see Phase B) — confirm `open_field_floor` remove + recreate works without killing `gz sim`.
- [ ] **Recreate floor** — after `TrainingEnvironmentWorldComposer.writeWorld`, spawn floor from temp SDF via `EntityFactory` (same pattern as obstacles) or approved `WorldControl` reset — pin which approach in README.
- [ ] **World name change** — switching `guardian_<id>`: confirm whether one process can switch Harmonic world name or requires remove-all + load new world file at process start (if latter, spike documents minimum restart scope: sim stays up but world plugin reload is impossible → narrow restart to bridge-only vs full sim).
- [ ] **gzweb** — after entity swap without sim exit: scene publish + websocket still valid; no merged duplicate `open_field_floor`; `guardian_viewer.html` dimension HUD and zone overlays resync (`mapHalfExtentM`, `maxZoneRadiusM`).
- [ ] Capture spike outcome in README **Gazebo training simulation** (locked handoff method).

---

## Phase B — Runtime clear / repopulate pipeline

Implement in `GazeboEntityFactoryClient` + `GazeboService` extension.

- [ ] **`listWorldModelNames`** — already exists; add optional filter by prefix / type.
- [ ] **`clearRuntimeWorldContent(worldName:instanceIndex:keepModelNames:)`** — remove all models not in allowlist: always keep nothing except after floor strategy decided; runtime removes: `guardian_obstacle_*`, `guardian_veh_sysid_*`, any phantom prefixes from repair.
- [ ] **`replaceOpenFieldFloor`** — remove `open_field_floor` if present; create from freshly written floor SDF snippet matching `TrainingEnvironmentFloorSize` and manifest colours; verify collision top at z = 0.
- [ ] **`applyManifestToLiveWorld`** — after clear + floor: sync obstacles from manifest (`syncManifestObstaclesToLiveSim` logic); Training proxies only when caller is `.run` + `buildMap`.
- [ ] **Timeouts / concurrency** — handoff runs off hot UI path where possible; single serial handoff queue on `GazeboService` (no overlapping handoffs from Builder + Training).
- [ ] **Revision token** — bump on handoff complete; viewport bridges ignore stale `applyState` ticks.

---

## Phase C — Panel and navigation contracts

### App-wide

- [ ] **Lazy sim start** — first embedded open still does not spawn at app launch; first handoff or `ensureEmbeddedSimRunning` starts the one process.
- [ ] **Sidebar tab change** (Worlds ↔ Training) — if both need a map: **same env + floor** → no-op; **different** → world handoff (not stop sim). If Training has no map selected, Builder keeps session or pauses viewport per product rule (document).
- [ ] **Leave panel** — World Builder `leavePanel` / Training teardown: decide **keep sim warm** vs stop (product: prefer **keep warm** for fast return; stop on app background/quit only).
- [ ] **Simulate off** — still stops `.run` **content** (proxies, SITL coupling) but policy choice: stop proxies only vs full handoff to empty — document.

### World Builder

- [ ] Remove unconditional `stopGazeboSession()` from `selectPackageAndPrepareViewport`; replace with `requestWorldHandoff(to: package)`.
- [ ] `floorSizeDidChange()` — persist `world.sdf`, then **floor replace** in live sim, not sim kill.
- [ ] Preview ↔ build mode — keep **no respawn** (`applyBuilderSessionModeWithoutRespawn`); only UI gates.
- [ ] Obstacle edit during handoff — block editor or queue mutations until handoff completes.
- [ ] Draft / new world — handoff after `writeWorld` to temp or package path.

### Training lab

- [ ] Map picker — `TrainingPanelController` map change uses handoff, not `stopAllEmbeddedViewportWorldsCompletely()` then spawn.
- [ ] **`resetMap` / `buildMap`** — unchanged semantics; ensure handoff clears proxies before builder map load.
- [ ] Roster SITL — independent of sim process; no extra `gz sim` per vehicle.

### Viewport (both panels)

- [ ] One `GazeboWebViewportView` per visible panel — same `websocketPort`; only one panel visible at a time in v1 (if both mounted, second is detached/paused — document WKWebView behavior).
- [ ] On handoff: soft reload viewer URL or `setZoneEditorState` / obstacle push after `embeddedViewport` reaches `.live` again.
- [ ] Reconcile world id: keep `reconcileActiveBuilderWorldIfNeeded` / Training analogue aligned with app-wide session id.

---

## Phase D — Orphan processes and teardown

- [ ] **Handoff suppress** — extend `GuardianGazeboOrphanBlitz.suppressDuringEmbeddedMapHandoff()` to cover **in-process** world swap (no process exit); blitz must not run mid-handoff.
- [ ] **Teardown blitz** — run only on: app quit, handoff failure full restart, explicit “reset simulation”; **not** on every map pick.
- [ ] **Cold launch blitz** — unchanged: still clears force-quit orphans before first sim start.
- [ ] **`noteLiveSpawn`** — register same runner PID across handoffs; only update registry on true new `gz sim` exec.
- [ ] **Port cleanup** — `GuardianTcpPortUtilities.terminateListeners` only when websocket bridge actually restarts, not on entity-only swap.
- [ ] **`waitForEmbeddedViewportTeardown`** — shorten or skip when sim stays alive (bridge-only refresh path).
- [ ] **Exit 15 regression test** — manual smoke: rapid map switch Builder → Training → Builder; no new sim killed by async blitz.

---

## Phase E — `spawnWorld` / reuse refactor

- [ ] Replace `stopEmbeddedViewportWorlds()` prelude with: if no app-wide sim → start once; else → `GazeboWorldHandoff.apply(target:)`.
- [ ] Narrow `canReuseEmbeddedWorld` into handoff “no-op” tier (identical path, env, floor, world name).
- [ ] `GazeboRunningWorld` rows — collapse to **one** embedded row or map handoff metadata on app-wide session (avoid stale multi-row `worlds[]` for embedded).
- [ ] `firstAliveRunWorldID` / `firstAliveBuilderWorldID` — merge into single `activeEmbeddedSessionID`.
- [ ] **Concurrency cap** — embedded does not consume two slots; cap applies only if second non-embedded sim is added later.

---

## Phase F — Tests and smoke

- [ ] Unit tests: handoff classification (same env, floor change, env change); overlap with existing zone/obstacle tests unaffected.
- [ ] **`GazeboWorldHandoffTests`** (or extend `GuardianHQTests`) — mock entity client sequence: clear → floor → obstacles count.
- [ ] Manual smoke checklist (Training app):
  - Open micro map Builder → place obstacles → switch package mini → floor visible, no duplicate floor mesh.
  - Builder → Training same map → Run proxies → Stop → back Builder, no proxies left.
  - Builder → Training different map without force quit; Activity Monitor: **one** `gz sim` tree.
  - Force quit → relaunch → cold blitz → open map → single sim.
  - Rapid map picker spam: no freeze, no orphan port 9002 listener pile-up.
- [ ] Debug overlay: log handoff phase lines (`WorldBuilderMapDebugLog` / simulation strip).

---

## Phase G — Docs and migration

- [ ] Update `README_FULL.md` **Session purposes** / map switch bullet when Phase B ships (world handoff primary; full stop = fallback).
- [ ] Update `AGENTS.md` Gazebo bullet to reference this tracker.
- [ ] Link from `TrainingGazeboSimulationToDo.md` (architecture section).
- [ ] When complete: migrate locks to README, delete this file per todo hygiene.

---

## Open questions (resolve in Phase A spike)

| Topic | Notes |
| --- | --- |
| Harmonic multi-world in one server | Can world **name** change without restarting `gz sim`, or only file path at launch? |
| `WorldControl` reset | Does `reset: { all: true }` replace static models from disk or only dynamic state? |
| Keep sim on app section change | Warm idle sim vs battery — operator-visible? |
| Formation tab later | Second embedded viewport + same sim vs instance 1 — defer until Formation 3D ships. |
| Procedural terrain | `GazeboTerrainToDo.md` includes heightmap in SDF — handoff must replace terrain model + floor, not only `open_field_floor`. |
| Mission app | No Gazebo — unchanged. |

---

## References

| Area | Path |
| --- | --- |
| Spawn / stop / reuse | `GazeboService.swift`, `GazeboSessionPurpose.swift`, `GazeboLaunchRecipe.swift` |
| Entity API | `GazeboEntityFactoryClient.swift`, `GazeboWorldBuilderObstacleVisuals.swift` |
| Orphans | `GuardianGazeboOrphanBlitz.swift`, `GuardianGazeboSpawnRegistry.swift` |
| Builder orchestration | `WorldBuilderController.swift` (`selectPackage`, `floorSizeDidChange`, `ensureBuilderGazeboRunning`) |
| Training orchestration | `TrainingPanelController.swift`, `FormationsPlaygroundView.swift` / `TrainingLabPanelView` |
| Viewport | `GazeboWebViewportView.swift`, `GazeboWebViewportZoneBridge.swift`, `guardian_viewer.html` |
| World compose | `TrainingEnvironmentWorldComposer.swift`, `TrainingEnvironmentWorldSDF.swift` |
| Readiness | `GazeboEmbeddedViewportReadiness.swift`, `GazeboSimSceneReadinessTracker` |

---

## When this file is empty

Migrate retained decisions to `README_FULL.md` → **Gazebo app-wide instance (world handoff)**, then delete this file.
