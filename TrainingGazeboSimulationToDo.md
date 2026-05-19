# Training app — Gazebo worlds, World Builder, and simulate tabs

Goal: **Guardian Training** is an autonomy lab with three cooperating surfaces:

1. **Worlds (Builder)** — author, validate, and save training environments (Gazebo scenes + anchors).
2. **Training (Vehicle)** — pick a saved environment, run skill teaching (Gazebo + PX4 SITL).
3. **Formation** — rehearse squads in a chosen environment.

**Today:** **Worlds** + World Builder with embedded 3D viewport (headless `gz sim -s` + websocket + `gzweb` in-panel). Training spawns `.run` world + SITL; Training/Formation 3D panels deferred. Portable Gazebo bundle deferred.

**Cross-links:** `README_FULL.md` → **Gazebo training simulation**; `AppTrainingMissionSplitToDo.md`.

---

## Phase 3b — World Builder viewport (shipped)

- Embedded panel: `GazeboWebViewportView` + offline `dist/gzweb.bundle.mjs` (`make gzweb-viewer` to regenerate).
- Preview / Build use server-only sim + Harmonic websocket bridge (not a separate Gazebo window).
- **Dev prerequisite (macOS Homebrew):** `brew install libwebsockets && brew reinstall gz-launch7` then `make gazebo-runtime` — without `libgz-launch-websocket-server.dylib`, `gz launch` cannot serve gzweb (sim server still runs).

---

## Phase 4 — Training: vehicle in environment

- [ ] **Embedded 3D viewport** — same stack as World Builder in Training panel.
- [ ] **PX4 pose in Gazebo** — align SITL spawn with environment `defaultSpawn` (bridge / model pose).
- [ ] **Teaching loop** — metrics from sim truth (not map geodesic alone).
- [ ] **Target slot in world** — edit goal in Gazebo or inspector when map is hidden.

---

## Phase 5 — Formation: squad in one world

- [ ] Catalogue + squad offsets; multi-vehicle `.run` world; 3D viewport; leave-tab contract.

---

## Phase 6 — Multiple connected squads

- [ ] Squad identity; world strategy; switcher; collision groups; scale warnings.

---

## Phase 7 — Nav2, costmaps, autonomy

- [ ] Costmap from Gazebo; planner goals; formation terrain; health chips.

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
