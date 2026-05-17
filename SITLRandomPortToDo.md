# SITL random MAVLink port & system ID — implementation checklist

Actionable tracker for **per-spawn UDP ingress ports** (and optionally **MAVLink system IDs**) so wipe → respawn does not reuse the same localhost MAVLink endpoints and `sysid:n` keys as the previous sim session. Stale telemetry after bulk SIM spawn, mission SIM cleanup, or Devices stop/replace is often **orphan SITL/MAVProxy** plus **deterministic port/sysid reuse**, not literal IP collision.

Related: **`GuardianSitlFleetLinkReconnectPolicy`** + **`GuardianUdpPortUtilities`** (reconnect waits for UDP bindable); **`GuardianSitlOrphanBlitz`** (cold launch only today); **`README_FULL.md`** → Mission Run SIM clean up; **`AGENTS.md`** simulation / fleet link notes.

---

## Problem (today)

| Layer | Current behavior | Failure mode |
|-------|------------------|--------------|
| **ArduPilot MAVProxy out** | `14550 + 10 × stackInstanceIndex` (MAVProxy default from `sim_vehicle.py -I`) | New sim on instance `0` → same **14550** as last session |
| **PX4 offboard (MAVSDK)** | `14540 + instance` (`px4-rc.mavlink`) | Same when index recycled |
| **PX4 GCS UDP** | `18570 + instance` | Bind probe in `reserveNextAvailablePx4Instance` only |
| **MAVLink system ID** | `stackInstanceIndex + 1` → fleet stream **`sysid:n`** | Old + new traffic both “sysid 1” if orphans or UDP bleed |
| **Instance index** | `reserveNextSimulationInstance()` picks **lowest free** 0…255 | After wipe, usually **0, 1, 2…** again |
| **gRPC (mavsdk_server)** | Dynamic `allocateGrpcPort()` per session | **Not** the stale-telemetry source |

Guardian listens as `udpin://0.0.0.0:<port>` via `FleetLinkService.registerSimulatedVehicle`. **`SitlRunningInstance`** stores only `stackInstanceIndex`, not the MAVSDK ingress port or allocated sysid.

---

## Locked product decisions (decide before coding)

- [ ] **Port band:** Reserve a documented UDP range for Guardian SITL ingress only (e.g. **42000–42999** or **15000–15999**). Document in `README_FULL.md` when shipped; avoid well-known ports (14550, 18570) for *new* random allocations.
- [ ] **System ID policy:** Either **(A)** random free MAVLink sysid in `1…254` per spawn, tracked in `SitlService`, or **(B)** keep `instance + 1` but never reuse instance without kill + port wait. **Recommend (A)** for wipe/respawn; instance index can stay for ArduPilot `-I` / PX4 `-i` process separation only.
- [ ] **Fleet stream key:** Keep public **`sysid:n`** where `n` = allocated MAVLink system ID (minimal UI churn), or introduce internal `sitl:<uuid>` with display mapping (larger change — defer unless needed).
- [ ] **Phased delivery:** **v1 ArduPilot** (custom MAVProxy `--out` + random port + stored sysid) before **v2 PX4** (requires mavlink startup overrides in bundled PX4 rootfs / env).
- [ ] **Deterministic fallback:** Env `GUARDIAN_SITL_LEGACY_PORTS=1` restores formula ports for bisecting upstream sim issues (default off once random ships).

---

## Dependency order

1. **Port allocator utility** (pure Swift + tests) — bind probe, band, in-use set from live instances.
2. **`SitlRunningInstance` + spawn path** — persist `mavlinkIngressPort`, `mavlinkSystemID`; wire register/unregister/reconnect/stop.
3. **ArduPilot launch** — pass MAVProxy output matching allocated port (verify against bundled `sim_vehicle.py` / MAVProxy).
4. **Wipe / orphan hygiene** — in-session blitz or stop-all waits (complements random ports).
5. **PX4** — mavlink port overrides per instance (or monotonic non-reused instance until PX4 done).
6. **README + AGENTS** — operator-facing “how sim networking works” one paragraph.

---

## Phase 0 — Discovery & spike

- [ ] **ArduPilot:** Confirm `sim_vehicle.py` / MAVProxy flags to set **UDP out** to `127.0.0.1:<allocatedPort>` (e.g. `--out=udp:127.0.0.1:PORT` or documented equivalent). Record exact argv in this file when known.
- [ ] **ArduPilot SYSID:** Confirm how to set MAVLink system id for SITL (`--sysid`, param file, or instance default). Target: allocated id matches `registerSimulatedVehicle(systemID:)`.
- [ ] **PX4:** Trace bundled `px4-rc.mavlink` (and SIH instance layout) for offboard + GCS port env vars or per-instance rootfs copy. List minimum change for random offboard port without breaking `14540 + instance` invariant comment in `SitlLaunchRecipe`.
- [ ] **Reproduce stale telemetry:** Manual script — spawn N sims, wipe (mission cleanup or stop all), respawn N; capture whether orphan `pgrep` / `lsof` on old ports explains bleed vs pure port reuse.

---

## Phase 1 — Allocator & model (Guardian-only)

- [ ] **`GuardianSitlMavlinkEndpointAllocator`** (or under `Systems/Utilities/` + `Utilities` namespace): `reserveMavlinkIngressPort(occupied: Set<Int>) -> Int?`, `reserveMavlinkSystemID(occupied: Set<Int>) -> Int?`; use existing **`GuardianUdpPortUtilities`** / `SitlService.isUdpPortBindable` pattern.
- [ ] **Extend `SitlRunningInstance`:** `mavlinkIngressPort: Int`, `mavlinkSystemID: Int` (or rename for clarity vs stack index).
- [ ] **`SitlService` spawn:** Allocate port + sysid before `registerSimulatedVehicle`; pass stored values to `stop` / `unregisterSimulatedVehicle` / `sitlSessionID(forGuardianVehicleID:)` (lookup by **sysid**, not `stackInstanceIndex` alone).
- [ ] **`reconnectFleetLink`:** Use **stored** `mavlinkIngressPort` + `mavlinkSystemID`, not `SitlLaunchRecipe.*Port(instance:)`.
- [ ] **`activeSystemIDs()`:** Derive from stored `mavlinkSystemID`, not `stackInstanceIndex + 1`.
- [ ] **Tests:** `GuardianSitlMavlinkEndpointAllocatorTests` — band bounds, excludes occupied, bind probe mocked or loopback-only; update seeds `seedMissionRunTestSitlRunningInstance` to accept port/sysid.

---

## Phase 2 — ArduPilot integration (v1 ship target)

- [ ] **`SitlLaunchRecipe.arduPilotSpec`:** Accept `mavlinkIngressPort` (+ optional `mavlinkSystemID`); append MAVProxy / sim_vehicle args so SITL emits to allocated port.
- [ ] **Runtime dir:** Keep `--use-dir instance-<stackInstanceIndex>` or switch to session UUID subdir (avoid param dir clashes independent of port).
- [ ] **`spawnArduPilot`:** Allocate endpoints → build spec → `registerSimulatedVehicle(systemID:allocated, mavlinkConnectionURL:udpin://0.0.0.0:port)` → log port + sysid + session UUID in simulation log.
- [ ] **Deprecate call sites** that assume `ardupilotMavproxyOutPort(instance:)` for live sessions; keep formula as **legacy fallback** only when env set.
- [ ] **SIM smoke:** Single ArduPilot spawn → link → stop → respawn → confirm new port in log and no cross-talk on map/hub lat-lon.

---

## Phase 3 — PX4 integration (v2)

- [ ] **Design:** Per-instance env (`GUARDIAN_PX4_OFFBOARD_PORT` etc.) injected in `SitlLaunchRecipe.px4Spec` / startup script, **or** monotonic instance index never reused until app quit (interim mitigation).
- [ ] **Bundled rootfs:** If patching `px4-rc.mavlink`, version the patch in repo docs; do not assume developer checkout paths only.
- [ ] **`spawnPX4`:** Same allocate → register → store path as ArduPilot; GCS port bind check uses **allocated** gcs port if split from offboard.
- [ ] **SIM smoke:** Two PX4 instances + wipe + respawn.

---

## Phase 4 — Wipe, cleanup & orphans (parallel recommended)

- [ ] **Mission run SIM cleanup / `stopAll`:** After last sim stopped, optional **`waitForUdpInboundPortBindable`** on recently used ports (short timeout) before next bulk spawn.
- [ ] **In-session orphan blitz:** Optional `GuardianSitlOrphanBlitz` entry when `instances` becomes empty (not only cold launch); gate with env `GUARDIAN_SKIP_SITL_ORPHAN_BLITZ`.
- [ ] **`clearStaleVehicleStateWhenNoSitlAlive`:** Verify hub + `sysid:n` models cleared; no code path rehydrates from old port.
- [ ] **Bulk MCS spawn:** Document whether stagger/wait-for-link should use **new** port settle (cross-link `MissionControlMcsBulkSimSpawnUtilities` / `FormationsPlaygroundController` stagger).

---

## Phase 5 — Fleet link & operator surfaces

- [ ] **`FleetLinkService.registerSimulatedVehicle` / `stopSession`:** No change to gRPC allocation; ensure `simulatedFleetVehicleIDs` and MC-R channels drop on unregister when sysid changes between spawns.
- [ ] **Reconnect UI** (Devices grid, Vehicle Inspector): Still valid; must use stored port after Phase 1.
- [ ] **Logs:** Structured template keys if port/sysid allocation fails (distinct from link failure).
- [ ] **Diagnostics:** Simulation log line includes `mavlink_port=` and `mavlink_sysid=` for support.

---

## Phase 6 — Docs & hygiene

- [ ] **`README_FULL.md`:** Short subsection — SITL port band, sysid allocation, legacy env, orphan blitz.
- [ ] **`AGENTS.md`:** Link this file under simulation / fleet.
- [ ] **Optional `TODO.md` bullet:** One line pointer to this tracker (only when Phase 2 lands or when operator asks).
- [ ] **Remove completed sections** from this file per `.cursor/rules/todo-list-hygiene.mdc` (migrate locked decisions to README, delete done bullets).

---

## Non-goals (capture elsewhere if needed)

- Changing **live hardware** MAVLink URLs (non-SITL).
- Randomizing **gRPC** ports (already dynamic).
- **TCP** sim bridges or multi-machine SITL.
- Rewriting fleet stream keys to non-`sysid` scheme (unless Phase 1 decision picks it).

---

## References (code)

| Area | Path |
|------|------|
| Spawn / stop / reconnect | `Sources/GuardianHQ/Infrastructure/Simulation/SitlService.swift` |
| Port formulas & launch specs | `Sources/GuardianHQ/Infrastructure/Simulation/SitlLaunchRecipe.swift` |
| MAVSDK sessions | `Sources/GuardianHQ/Systems/Fleet/Services/FleetLinkService.swift` |
| UDP bind wait | `Sources/GuardianHQ/Systems/Utilities/.../GuardianUdpPortUtilities.swift` |
| Cold orphan kill | `Sources/GuardianHQ/Infrastructure/Simulation/GuardianSitlOrphanBlitz.swift` |
| Reconnect policy | `Sources/GuardianHQ/.../GuardianSitlFleetLinkReconnectPolicy.swift` |
| Mission SIM cleanup | `README_FULL.md` → Mission Run SIM clean up |

---

## Manual test matrix (until automated)

- [ ] Spawn 3 ArduPilot sims → note ports/sysids in log → stop all → spawn 3 again → **ports and sysids differ**; map shows correct vehicles.
- [ ] Force-quit app with sims running → relaunch → orphan blitz → spawn → no ghost telemetry.
- [ ] MC-R bulk spawn full mission → complete run SIM cleanup → bulk spawn again → no stale positions.
- [ ] Reconnect link (no sim kill) after random ports ship → link recovers on **same** stored port.
- [ ] PX4 path (when Phase 3 done): same matrix as ArduPilot.
