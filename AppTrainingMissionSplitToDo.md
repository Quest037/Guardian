# Training app + Mission app split — autonomy brain export

Goal: ship **two macOS apps from one codebase** — **Guardian Training** (lab) and **Guardian Mission** (operations) — so Training can bundle **Gazebo**, heavy sim assets, and skill/formation rehearsal without bloating the field app. Training **promotes and exports versioned autonomy brains**; Mission **imports** a brain and **MRE** uses it as the **default OFFBOARD control policy** for vehicles, with **Nav2** (UGV/USV) and **Aerostack2** (UAV) handling squad-level motion in **Mission Control Running (MC-R)**.

**Today:** Two executables + shared `GuardianHQ` library. Training exports **Guardian Brain Pack** (`.guardianbrain`); Mission imports + MCS per-run bindings; MC-R brain chrome; log export metadata; **MRE segment dispatch** for non-convoy primaries via `MissionRunBrainExecutionSubsystem`. Convoy tasks and planner-only packs still use MAVLink / ROS paths. ROS sidecar stubs: `README_AUTONOMY.md`.

**Related trackers:** `TrainingGazeboSimulationToDo.md` (3D worlds in Training app); `CesiumJSMapIntegrationReadMe.md` (MC-R / Live Drive maps stay ops-focused); `TODO.md` → **Training**, **Vehicles System** (autonomy).

**Shipped (see `README_FULL.md`):** SwiftPM split (`GuardianMission` / `GuardianTraining` / `GuardianHQ`), per-app branding, brain pack schema v1, Training export, Mission import catalogue in Settings.

---

## Product lock (read first)

- [ ] **Two apps, one repo** — extract **`GuardianCore`** library (interim: shared **`GuardianHQ`** library + thin executables). Shipped locks (brain export, OFFBOARD dispatch, squad planner v1, semver + codenames, Mission sim vs Training worlds) live in `README_FULL.md`.

---

## Guardian Brain Pack — remaining

*(none — planner hints capture shipped; MRE planner execution remains Phase 5 / corners cut.)*

---

## Phase 1 — SwiftPM split (remaining)

- [ ] **`GuardianCore` target** — rename/split shared library from `GuardianHQ`.
- [ ] **Resources per target (SwiftPM)** — split `GazeboRuntime` / `TrainingEnvironments` into a Training-only resource target (Mission `.app` packaging already strips them — see `package-macos-app.sh`).
- [ ] **Shared tests** — `GuardianCoreTests` when library splits.

---

## Phase 2 — Training app (lab product)

*Gazebo / environments: `TrainingGazeboSimulationToDo.md` (other workstream — do not duplicate here.)*

---

## Phase 5 — MC-R squad management (Nav2 + Aerostack2)

*(none — single-world Mission sim + brain≠world transfer lock documented in `README_FULL.md`.)*

---

## Phase 6 — Cutover, deprecation, hygiene

- [ ] **Update `TODO.md`** — further trim when tracker retires.
- [ ] **Manual smoke** — Training: promote + export v1/v2; Mission: import both, pin v2, run MC-R SIM with OFFBOARD brain; squad Nav2 formation on 2× UGV.

---

## Dependencies between trackers

```
Phase 1 (finish Core + resources)     Phase 2 (Training + Gazebo)  ← TrainingGazeboSimulationToDo.md
    ↓
Phase 3 (Mission catalogue + MCS binding)
    ↓
Phase 4 (MRE OFFBOARD brain)  →  Phase 5 (Nav2 / Aerostack2 squads)
    ↓
Phase 6 (cutover)
```

---

## Open questions

| Topic | Notes |
| --- | --- |
| Pack signing | Trust model for imported brains (org signature vs unsigned lab) |
| Mid-run brain switch | Allowed in MCS only, never MC-R, or never |
| One brain per task vs per vehicle | MCS UI implications |
| Aerostack2 maturity | UAV brain may be segment-only until AS2 execution ships |
| Paladin | Reads brain version from run envelope for “learn” backlog (`TODO.md` MRE Learn) |

---

## References

| Area | Path |
| --- | --- |
| Brain pack | `Sources/GuardianHQ/Systems/Utilities/BrainPack/` |
| Training skill model | `Sources/GuardianHQ/Systems/Utilities/Training/TrainingTaskModels.swift` |
| MRE | `Sources/GuardianHQ/Systems/MissionControl/` |
| Package layout | `Package.swift` |
| Gazebo in Training | `TrainingGazeboSimulationToDo.md` |

---

## Corners cut / follow-up (tracked)

- [ ] **Planner-only packs** — v1: open-loop segments from layout + path (Nav2 plan when bridge is up); ROS `navigate_to_pose` action client not wired.
- [ ] **Brain segment → MRE cycle** — unit test covers `missionCycleFinished` dispatch; verify bounded / one-off tasks end correctly in SIM smoke.
- [ ] **MCS bindings vs mission tasks** — per-row mission task binding not implemented; MCS copy documents pin keying (task kind + vehicle class).

---

## When this file is empty

Migrate locked decisions to `README_FULL.md`, delete this file, and leave a one-line pointer in `TODO.md` only if optional work remains.
