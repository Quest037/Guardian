# Squad follow & formation — implementation checklist

Actionable tracker for **wingman follow** and **formation control** in Mission Control runs. Squad **lifecycle** (per-primary cycles, stagger, rollup, operator complete/abort) lives in **`MRESquadsToDo.md`**. This file covers **how wingmen move** relative to the primary and what MRE must own.

Related: **`TODO.md`** → **Pathfinding & geofence avoidance** (shared router; § **P.1** exclusion approach → MRE recovery; primary AUTO + all OFFBOARD/GUIDED motion); Mission Control → Squads / Planner formations; **`README_FULL.md`** → Mission task authoring, reserve swap geometry.

---

## Locked architecture (v1)

| Role | Autopilot mode | Who decides movement |
|------|----------------|----------------------|
| **Primary** (squad leader) | **OFFBOARD/GUIDED** launch→WP1, then **AUTO_MISSION** / **AUTO** | GR plans launch leg; MRE streams setpoints until WP1; then autopilot executes uploaded mission for remaining legs (v2). |
| **Wingmen** | **OFFBOARD** (PX4) / **GUIDED** (ArduPilot) | **MRE** streams setpoints continuously; wingmen do **not** independently execute the mission path while following. |
| **Formation geometry** | External to autopilot | Guardian formation controller computes offset targets from primary telemetry; wingmen fly/drive toward those targets via OFFBOARD/GUIDED. |

**Principles (do not regress):**

- Every vehicle may **store** the same mission onboard; **AUTO** runs only **after** the GR launch leg to WP1 — not from the pad on first start.
- Only the **primary** has **mission authority** (active AUTO execution) after the launch leg; wingmen stay on OFFBOARD/GUIDED while following.
- Do **not** put all vehicles in AUTO_MISSION at once — causes drift, timing divergence, and formation instability.
- OFFBOARD/GUIDED setpoints are a **heartbeat**: stream at a stable rate (target ~20 Hz); loss triggers autopilot offboard-loss / guided failsafe (HOLD, RTL, LOITER, etc. per vehicle params).
- Prefer **OFFBOARD/GUIDED + streamed targets** over **AUTO_LOITER** for wingmen holding formation — loiter keeps internal nav active and fights formation control on rovers and tight offsets.
- **FOLLOW_TARGET / Follow Me** alone is **not** v1 formation control (pursuit only, no tactical offsets). v1 uses explicit offset positions from primary state.
- **v1 formation shapes:** **convoy**, **chevron**, **arrowhead** — authored in MCS task / primary-slot settings (`MissionTask/squadFormation`, primary override). **Live** formation change during a run is **v2**; mid-run retarget without pause is **v3**.

**MRE ownership:** While a wingman is bound and following, **MRE controls that vehicle at all times** — mode entry, setpoint stream, pause/hold between cycles, promotion handoff, release, reserve swap reposition, abort/complete wind-down, and teardown. No “wingman runs its own AUTO mission” during active follow.

**v1 geofence note (known gap):** Uploaded autopilot geofences are enforced by the FC, not by Guardian path planning. **AUTO_MISSION** respects **exclusion** zones by **stopping** when the vehicle reaches the boundary — it does **not** plan a detour around them. Wingman v1 only **gates** streamed setpoints (`MissionControlSquadConvoySetpointGeofenceUtilities`: hold last valid; no detour). **Skirting exclusions** and **reporting approach → MRE recovery** are **v2** (§ P router + § P.1 primary vs wingman goals).

**Launch → first waypoint (v1 today):** Convoy squads **assemble** on the pad, upload mission in **`compiling`**, then primary starts **AUTO** via ``launchPrimaryMissionAfterConvoyAssembly`` (no OFFBOARD GR launch leg until § **P** pathfinding v1 ships). Routed OFFBOARD launch→WP1 is deferred — see § **P** checklist.

**Long-term primary mode (v3 direction):** Extend GR + OFFBOARD beyond the launch leg to **full mission legs** (replace AUTO_MISSION for primary mid-run). Until then, primary uses AUTO only **after** the GR launch approach completes.

---

## Dependency order

1. **`MRESquadsToDo.md`** — per-squad primary lifecycle and MAVLink cycle boundaries on **primary only** (scheduling / MC-R items shipped there) — wingman follow must respect squad cycle keys and not block sibling squads.
2. This file **§ v1** — wingman pipeline on top of stable primary squads (shipped).
3. **`MRESquadsToDo.md`** promotion / release RoE — uses mode switches defined in v1.
4. **`TODO.md` → Pathfinding & geofence avoidance** — shared Guardian router (exclusions as obstacles; skirt inside inclusion) + **§ P.1** exclusion approach reporting and role-specific MRE recovery. **Blocks** meaningful geofence behaviour for primary AUTO and all OFFBOARD/GUIDED motion (wingmen, park/reposition, end-policy moves).
5. This file **§ v2 — Convoy trail** — trail motion model **on top of** pathfinding (approach legs route around exclusions; trail arc-length is how wingmen lag the primary, not how they avoid fences).
6. This file **§ v2 — Formations** — additional shapes, live formation change, tactical offsets (can parallelize after pathfinding; trail still recommended before polyline handoff in cluttered maps).
7. This file **§ v3 — Road network routing** — task **domain classification** (open vs road-following); snap routes to OSM roads when appropriate; **UGV and UAV** (mixed squads, overwatch). Extends § P router; does not replace open-field skirt.
8. This file **§ v3 — 3D geofences & router** — promote § P **2D** router to **3D** (floor + ceiling bands); airborne exclusion volumes (e.g. radar keep-outs). Can parallelize with § R once § P is stable; required for altitude-aware § P.1 recovery on aerial tasks.
9. This file **§ v3 — MRE-owned primary mission** — evaluate dropping AUTO_MISSION for primary once § P (+ § R where road-based, § 3D where vertical fences matter) and runtime follower are proven in SIM and production-like runs.

---

## v1 — Wingmen working end-to-end (convoy)

### A — Model & mission authoring

- [x] **Squad follow binding:** Wingman roster rows (`.wingman`, `leaderRosterDeviceId`) resolve to the same squad as primary; `buildTaskSquadMissions` / planner include wingman assignment IDs in squad scope (telemetry, logs, prompts use **TaskName:N** via `MissionControlSquadUtilities`). (`MissionControlSquadFollowBindingUtilities`, `MissionTaskSquad/wingmanBindings`.)
- [x] **Mission upload on wingmen:** Upload same task mission to wingmen for **promotion / failover** readiness; while following, wingman does **not** start AUTO mission execution. (Upload on squad dispatch; no `missionStart` on wingmen.)
- [x] **Formation field:** `MissionSquadFormationKind` on task (default **convoy**); primary slot may override via `MissionRunAssignmentPolicies/squadFormationOverride`. MCS task + primary-slot policy drawers expose picker when the task has wingmen. Mission workspace still locks **pattern** to convoy when wingmen are present (shape is MCS/run policy, not mission editor pattern row).
- [x] **Spacing parameters:** Convoy offset(s) — e.g. along-track distance per wingman index, optional lateral lane — authored or locked defaults; validate against vehicle class (UAV vs UGV). (`MissionSquadConvoySpacingPolicy`, `MissionControlSquadConvoyFormationUtilities`.)

### B — Fleet catalogue & recipes (Layer 0 / 1)

- [x] **Mode commands:** Catalogue atoms (or existing `do.mode`) for PX4 **OFFBOARD** and ArduPilot **GUIDED**; primary remains **AUTO_MISSION** / **AUTO** when starting squad execution. (Wingmen: `FormationFollowStream` + `FleetLinkService/startFormationFollowStream` — PX4 OFFBOARD, ArduPilot `mode guided` via existing shell path.)
- [x] **Setpoint streaming:** Layer 0 commands for position / velocity / yaw (and rover steering if required) suitable for OFFBOARD/GUIDED; document required stream rate and frame (NED / body) per stack. (~10 Hz global position; PX4 `Offboard/setPositionGlobal` AMSL, ArduPilot `gotoLocation` in Guided.)
- [x] **Hold / pause wingman:** Between-cycles **Loiter** tactic freezes last valid setpoints on the wingman stream (`holdingBetweenCycles`); park/RTL stops streams before dispatch.
- [x] **Offboard-loss awareness:** MRE logs `squad_follow.offboard_stream_lost` when the setpoint stream ends unexpectedly; reconnect + `stream_failed` phase; exhaustion pauses primary and surfaces operator prompt.

### C — MRE formation controller (runtime)

- [x] **`MissionRunSquadFollowSubsystem` (or equivalent):** Owns wingman follow for all active squads; subscribes to **primary** position, heading, velocity (and mission state); computes each wingman **desired position = primary + convoy offset**; streams setpoints at ~10 Hz.
- [x] **Start follow:** When squad primary enters executing cycle, wingmen on that squad: transition to OFFBOARD/GUIDED, begin setpoint stream, confirm mode via telemetry before marking wingman “on formation.” (Stream start + `following` phase when stream acks.)
- [x] **Continuous control loop:** Timer/task on MRE executor cadence; **re-stream setpoints** every tick; handle primary telemetry gaps (hold last offset vs freeze wingman — product choice, document in README). (10 Hz tick; convoy targets on **task path** behind primary's along-track projection; parallel wingman stream start + tick retry if stream not registered.)
- [x] **Stop follow:** On squad complete/abort, primary promotion, wingman release, reserve swap, or run teardown — stop stream, command safe mode (HOLD / LOITER / land per policy), clear follow state. (Cycle end, operator squad/task wind-down, run immediate complete/abort, `startExecution` reset, reserve swap `clearFollowState`; hold after stream stop.)
- [x] **Between-cycles:** When primary is in between-cycles tactic, wingmen follow **same squad policy** (RTL / loiter / park / hold formation) — wingman branch in between-cycles dispatch, not independent AUTO mission.
- [x] **Stagger / first wave:** Wingmen on squads whose primary has not launched yet stay idle/disarmed or parked per stagger; only wingmen whose primary is active enter follow loop. (Follow starts only on `startSquadExecution` for that primary.)
- [x] **Geofence / fleet barriers (v1 — setpoint gate only):** Wingman streams respect squad effective geofences via hold-last-valid + fleet queue deferral (`MissionControlSquadConvoySetpointGeofenceUtilities`, `FleetLinkService/shouldDeferFormationFollowSetpoints`). **Does not** skirt exclusions — replace with pathfinding router in v2 § P.

### D — Integration with squad lifecycle (`MRESquadsToDo.md`)

- [x] **Cycle boundaries:** MAVLink mission **finished** on **primary only** completes that squad’s cycle; wingman follow pauses or holds per between-cycles policy until next primary cycle starts. (Stream stop on primary mission-finished → `onPrimarySquadCycleEnded`.)
- [x] **Per-squad independence:** `activePrimaries` keyed by primary assignment id; teardown / between-cycles / halt scoped to one squad.
- [x] **Operator squad complete/abort:** Wind down **all assignments in squad** (primary + wingmen); stop wingman streams before slot evidence moves to terminal states. (Wingman OFFBOARD/GUIDED stream stopped on squad-scoped or task-scoped operator wind-down; primary wind-down commands unchanged.)
- [x] **Logging:** Distinct template keys for wingman mode entry, stream start/stop, formation error, offboard-loss; params include squad label (`Dagger:1`) and assignment/vehicle ids.

### E — Promotion & release (v1 behaviour)

- [x] **Promotion (RoE `SquadPromote`):** `performSquadPromoteWingmanToPrimary` + `promoteWingmanToSquadPrimary` — wingman stops follow, optional `fleetVehicleDoMissionStart`, remaining wingmen retarget new primary telemetry.
- [x] **Release (RoE `RosterRelease`):** `performRosterReleaseWingmanFromSquadFollow` — stop follow, optional park, `missionRunRosterReleasedAssignmentIDs` for MC-R chrome.
- [x] **Reserve swap-in:** `resumeWingmanFollowAfterReserveSwapIfNeeded` after post-commit reserve swap.

### F — Mission Control UI (operator)

- [x] **MC-R map:** Wingmen use the same hub telemetry markers as other roster assignments (per-vehicle live channels).
- [x] **Status:** Wingman roster row shows follow phase labels via `wingmanFollowPhase` + `squadFollowStatusRevision` refresh; released wingmen show “Released from squad”.
- [x] **MCS formation picker (v1):** Task policy sidebar + primary-slot policy sidebar (inherit / convoy / chevron / arrowhead) when the task has wingmen. Live mid-run formation change deferred to v2 § F.

### G — Tests & docs

- [x] **Unit tests:** Convoy offset, binding, geofence gate, wingman phase labels, `taskHasWingmen`, roster-release revision.
- [ ] **Integration tests (SIM):** Primary AUTO_MISSION + wingmen OFFBOARD/GUIDED convoy; stream stop failsafe; promotion — manual SITL smoke (not automated in CI).
- [x] **`README_FULL.md`:** Wingman convoy follow subsection under Mission task authoring.
- [x] **`AGENTS.md`:** Pointers to subsystem, checklist, prompt bridge, MC-R phase API.

---

## Field bugs — launch leg & convoy (fix backlog)

SIM/field findings on shipped **GR launch→WP1**, **convoy assembly**, and formation streams. Close these before treating § **P** / § **T** launch-leg behaviour as done.

- [x] **Convoy assembly — wingman heading:** During `staging` / `assemblingConvoy`, wingman stream **yaw** uses **primary hub heading** (not path tangent). See ``MissionRunSquadFollowSubsystem`` tick + assembly streams.
- [x] **Convoy hold — primary heading on stop:** While primary waits for wingmen (`launchToWaypoint` catch-up) or during `staging` / `compiling`, primary OFFBOARD holds **current position + locked hub heading** (``convoyHoldHeadingDeg`` / ``convoyHoldCoordinate``) — not carrot bearing toward the next route point. **LtWP must not hold** when wingmen are in slot — only ``wingmenLaggingLaunchLegConvoy`` (not zero ground speed alone).
- [x] **GR launch→WP1 — route quality:** ``GuardianGeofenceRouter`` skirts exclusions; visibility-graph **A\*** with turn/detour/backward cost; **string-pull** + pull-toward-goal; **Bezier corner smoothing**; **second string-pull after smoothing**; 10 m clearance. **Debug:** MC-R fleet **Debug** draws primary GR polyline (black dashed). Reopen if SIM still shows bad detours.
- [x] **Launch→WP1 — primary catch-up speed:** Primary slows to ``launchLegPrimaryWaitSpeedMS`` while wingmen lag on ``launchToWaypoint``.
- [x] **GR → AUTO handoff (path distance):** Launch leg completes on **remaining distance along the routed polyline** only (not crow-flies to WP1); one-shot MRE handoff guard. See ``MissionSquadConvoyFollowControlPolicy/guardianRouterLaunchApproachArrived``.
- [x] **Wingmen hold through compile:** After convoy assembly, wingmen **freeze in slot** during `compiling` (mission upload) — no bunching chase toward a stationary primary.

---

## v2 — Pathfinding, convoy trail, formations (deferred)

Do not block v1 on these. **Pathfinding (§ P)** is the shared foundation; **convoy trail (§ T)** is a squad-follow consumer of that router, not a separate obstacle-avoidance system.

### P — Pathfinding & geofence avoidance (prerequisite)

**Product lock:** **Exclusion** geofences are **keep-out obstacles** — vehicles must **skirt** them (maximize clearance where practical). **Inclusion** is the outer operable boundary. Autopilot-uploaded fences remain **breach / backup** policy; Guardian owns **route geometry** for both AUTO mission legs and streamed OFFBOARD/GUIDED motion.

| Surface | v1 behaviour | v2 target |
|---------|----------------|-----------|
| **Primary AUTO** | FC stops at exclusion boundary; no detour around keep-outs | **Launch→WP1:** GR + OFFBOARD always (convoy); then AUTO. Mission legs: planner reroute at upload + § P.1 recovery; v3 replaces remaining AUTO legs with MRE-streamed path |
| **Wingmen OFFBOARD/GUIDED** | Hold last valid setpoint on violation | Stream **next point on a legal path** toward **formation target** (§ P.1); convoy/trail slot, not solo mission reroute |
| **Exclusion approach / breach** | No structured report to MRE; FC may stop/RTL per params | Vehicle **reports** approach; MRE **captures** and pathfinds — role-specific goals (§ P.1) |
| **Park / reposition / between-cycles** | Direct goto where used | Same router API |
| **Convoy trail approach** | Heading-astern / chord through holes | Trail targets sampled along **routed** path to join route |

**Checklist (canonical — do not duplicate in `TODO.md`):**

- [ ] **Guardian 2D pathfinding system (proper v1 — not incremental patches):** One shared router under Global Utilities / Mission Control — free-space or corridor/medial nodes (not fence-offset vertices); single clearance model on every leg (A* + string-pull, optional corner smoothing); deterministic unit tests (hole between start and goal, nested exclusion inside inclusion, multi-hole); **no illegal straight-chord fallbacks** when routing fails; MC-R map overlay matches execution geometry. **Reverted (2026-05):** experimental ``GuardianGeofenceRouter`` removed from tree; v1 convoy uses direct AUTO after assembly + upload until this ships. Consumers (staged): mission compile/upload leg repair; OFFBOARD launch→WP1; policy move+park / RTL / reposition; wingman formation streams; reserve swap join pose.
- [ ] **Launch→WP1 OFFBOARD leg (deferred):** After pathfinding v1, convoy squads may again run routed OFFBOARD to first waypoint before AUTO; until then primary starts AUTO after assembly + mission upload (``launchPrimaryMissionAfterConvoyAssembly``).
- [ ] **Mission compile / upload:** Reroute legs at upload (launch → WP1, inter-WP, etc.); log detoured vs author path.
- [ ] **Runtime setpoint follower:** Shared service for formation streams, park, reposition, policy moves — replan from current pose when target or fences change (replace hold-last-valid as sole strategy; ``MissionControlSquadConvoySetpointGeofenceUtilities`` today).
- [ ] **Replace** hold-last-valid as the **only** geofence strategy for wingmen — extend GR follower to all convoy phases and primary mission legs (not only blocked chords).
- [ ] **SIM smoke:** Launch and path separated by exclusion; track stays outside red zones (primary + wingmen).
- [ ] **`README_FULL.md`:** Obstacle skirt vs FC breach; router call sites; exclusion approach reporting and primary vs wingman recovery (§ P.1).
- [ ] **Open-field only in v2:** Road snap and task domain classification — **§ v3 R** (same router API, graph layer on top).
- [ ] **GR → AUTO handoff (primary):** Mission is already onboard from the compiling phase — after GR arrival, drop `recipe.fleet.do.mission.continue.after.operator.park` (offboard stop + mode mission + arm + mission start). Stop the primary OFFBOARD stream, then dispatch catalogue `command.fleet.vehicle.do.mission.start` only (arm/set mode only if telemetry still requires it).

### P.1 — Exclusion approach reporting & MRE recovery (depends on § P router)

**Intent:** When a vehicle **would enter** or **has entered** an exclusion zone, it **reports** to MRE; MRE **captures** the event and uses the shared pathfinder to get motion legal again. **Primary** and **wingman** use the **same router** but **different pathfinding goals** — mission progress vs formation fidelity.

| Role | Pathfinding goal | Success criterion |
|------|------------------|-------------------|
| **Primary** | Rejoin **mission track** for the active squad cycle — along the task polyline / next mission leg / routed spine toward cycle completion | Vehicle resumes progress toward mission intent (not merely “outside the red zone”) |
| **Wingman** | Reach the **current formation target** (convoy offset on polyline, trail arc-length point, or assembly seed) while skirting exclusions | Best-effort **formation** relative to primary telemetry; may lag if primary cuts through a hole — do **not** upload or execute an independent AUTO mission path |

**Report sources (combine; dedupe per vehicle):**

- **Guardian-predicted:** Proposed setpoint, next AUTO leg, or chord to formation target would violate squad **effective geofences** (same geometry as `MissionControlSquadConvoySetpointGeofenceUtilities` — report *before* streaming or before relying on FC stop).
- **FC / telemetry (optional):** Fence breach STATUSTEXT, geofence prearm failures, primary **stopped at fence** with mission still active — correlate with assignment + squad context.

**MRE behaviour (high level):**

- [ ] **Event model:** Typed exclusion-approach / breach signal per assignment (fence id optional, coordinate, source: predicted vs FC); enqueue on MRE executor; distinct mission log templates (squad label, slot, primary vs wingman).
- [ ] **Primary handler:** Pause or hold primary mission authority as needed; pathfind **current pose → rejoin point** on mission spine (inside inclusion, outside exclusions); re-upload mission segment or switch to streamed legs when § M ships — v2 may be **upload patch** only while primary stays AUTO.
- [ ] **Wingman handler:** Do not change wingman mission authority; pathfind **current pose → current formation target** from `MissionRunSquadFollowSubsystem` (convoy / trail phase); continue streaming setpoints along the legal path; replan when primary or target moves.
- [ ] **Coordination:** If primary is recovering, wingmen still target formation relative to **live** primary pose — wingman detour must not chord through the same exclusion; primary recovery takes precedence for squad pause policy (document: freeze wingmen vs allow skirt-only).
- [ ] **FC params (safety net only):** Document recommended `FENCE_ACTION` (or stack equivalent) so FC does not fight MRE; Guardian owns detour geometry — see `TODO.md` FC breach params bullet.
- [ ] **Tests:** Unit — predicted violation emits event; router goals differ for primary rejoin vs wingman-to-slot. SIM — primary stalls at exclusion → MRE detour → mission advances; wingman chord blocked → reports → skirts while primary on-route.
- [ ] **Operator:** MC-R / mission log shows exclusion recovery in progress; optional prompt when recovery exhausts retries (reuse squad follow prompt patterns).

### P.2 — Mid-run mission join (reserve swap / vacancy — decide later)

**Defer** until launch→WP1 GR is exercised in SIM. **Decision:** When a vehicle binds mid-run (reserve swap post-commit, floating-pool vacancy), does mission execution use **GR + OFFBOARD** to the join pose / first mission leg, or stay on direct ``do.mission.upload.start`` / ``do.mission.upload.start.item``?

- [ ] **Product decision:** GR approach vs AUTO upload for ``MissionRunEnvironment+ReserveSwapPostCommitHandoff`` and ``MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection``.
- [ ] **If GR:** Reuse ``approachingFirstWaypoint`` / launch-leg subsystem; define join goal (hub pose vs WP index vs squad primary track).
- [ ] **If AUTO (interim):** Document why join path differs from first-start launch leg until unified OFFBOARD mission model (§ M).

### T — Convoy trail (pre-path follow; **depends on § P**)

**Role:** Fix wingmen wandering when polyline/heading-astern fires before the primary has joined the route. **Trail** defines *where along the leader’s motion history* each wingman should sit; **pathfinding** defines *how to reach those points without crossing exclusions*.

Three stages in ``MissionRunSquadFollowSubsystem``:

| Stage | Motion model | Pathfinding |
|-------|----------------|-------------|
| **1 — Convoy creation** | Seed chain primary → wingman₁ → wingman₂… at locked spacing for assembly | Route each wingman to its seed slot from current pose (skirt exclusions) |
| **2 — Approach / join route** | Ring buffer of primary pose history (~10 Hz); wingman *i* targets **(ordinal+1)×spacing** m back along trail arc-length (not body-astern; not polyline projection while primary is off-route) | History defines *desired* trail point; **router** produces streamed setpoints along a legal path to that point (replan if primary cuts through a hole) |
| **3 — Run** | Hand off to task-polyline convoy slots once primary is on-path and at/past WP1 | Polyline-anchored offsets as today; setpoints still **router-filtered** so convoy line does not chord through exclusions |

**Checklist:**

- [ ] **Stage 1:** Assembly chain geometry + pathfound routes to seed positions.
- [ ] **Stage 2:** Primary pose ring buffer; trail arc-length targets; integrate router on every stream tick (not raw chord to trail point).
- [ ] **Stage 3:** Smooth or single-tick switch trail → polyline; retain pathfinding on polyline phase.
- [ ] **Trail length cap:** Squad depth × spacing + margin.
- [ ] **Tests:** Primary off-route with exclusion between launch and WP1 — wingmen skirt; primary on-route — trail → polyline handoff without fence violation.
- [ ] **Logging:** Distinct keys for trail stage transitions and path replan (squad label + assignment ids).

**Do not** implement trail arc-length alone without § P — that reproduces “straight line through exclusion” with extra complexity.

### F — Formations beyond convoy (after or parallel to § T)

- [ ] **Formation enum:** Chevron, arrowhead, line abreast, custom offsets per wingman index.
- [ ] **Mission authoring:** Formation picker overrides pattern-default convoy; per-squad override optional.
- [ ] **Live formation change:** Operator or Paladin command to change shape mid-run; smooth retarget without dropping OFFBOARD/GUIDED stream (offsets still pathfound to legal positions).
- [ ] **Tactical offsets:** Leader heading + speed + curvature for moving formations (not static body offsets only).
- [ ] **Collision / spacing guards:** Minimum separation, max closure rate between wingmen.
- [ ] **Advanced promotion:** Election policy (nearest to path, battery, link) documented and testable.

---

## v3 — Road routing, 3D geofences & MRE-owned primary (deferred)

Do not block v2. **§ R** extends the § P router with a **road graph** and **task-domain inference**; **§ 3D** promotes the § P **2D** router to full **vertical** geofence-aware routing (floor + ceiling); **§ M** moves the **primary** onto the same streamed-motion stack as wingmen once routing is trusted.

### R — Road network routing & task domain (extends § P)

**Product lock:** When a task is **road-based**, Guardian routes along the **road network** (snap like mission workspace / OSM map context — chords across blocks and fields are wrong for ground convoys). When a task is **open-field / aerial**, use § P **open-field** skirt only. **Mixed squads** are normal: UGV primary on roads, **UAV wingmen in overwatch** (offset above/near the **routed** ground track, not the raw author polyline through buildings).

**Not UGV-only:** Road snap applies to any assignment whose **task domain** is road-following (typically UGV primaries). UAVs on the same task use the **same routed centerline** for horizontal track (with class-specific altitude / offset), so overwatch stays tied to the convoy path the ground element actually drives.

| Input | Role |
|-------|------|
| **Author task path** (waypoints + pattern) | Hint geometry for classification and fallback |
| **OSM / road graph** (extract, cache, offline-capable) | Snap graph; driveable centerlines |
| **Effective geofences** | Still hard constraints — road snap must not cut through exclusions (horizontal § P until § 3D ships) |
| **Vehicle class + squad role** | UGV: on-road follower; UAV: overwatch offset from routed track |

**Task domain classification (analyse path, decide mode):**

- [ ] **Heuristics v1:** Infer `roadFollowing` vs `openField` from waypoint polyline vs OSM road proximity (mean distance to nearest driveable edge, % of legs on-road, urban vs rural density, task pattern / vehicle mix on roster).
- [ ] **Operator override:** Per-task (or per-run) toggle: **Follow roads** / **Open field** / **Auto** — visible in mission task settings; Auto uses heuristics.
- [ ] **Confidence & logging:** Emit MRE log when Auto chooses road vs open (params: score, task id, squad label); MC-R map preview optional: show **snapped** route overlay vs author path.
- [ ] **Re-classify on edit:** Re-run classification when waypoints or roster vehicle classes change pre-run.

**Road graph & snap (extends Guardian router):**

- [ ] **Graph build:** Import or derive driveable edges from OSM (mission bbox + corridor buffer); cache per mission / tile; respect one-way and access tags where available.
- [ ] **Snap API:** `route(start, goal, fences, domain: .roadFollowing | .openField)` — road mode: shortest/legal path on graph then skirt exclusions; open mode: § P polygon router only.
- [ ] **Mission compile:** Road-based tasks: replace or supplement WPs with graph-aligned spine before upload (v2/v3 primary AUTO) or before MRE stream legs (§ M).
- [ ] **Runtime follower:** Stream setpoints along snapped polyline; replan when primary deviates or graph block (dead end, exclusion covers road).
- [ ] **Convoy trail / wingmen (§ T):** Trail arc-length and convoy slots measured along **routed** track, not author chord.
- [ ] **Mixed squad overwatch:** UAV offsets from routed UGV centerline (lateral, along-track, altitude band); pathfound UAV reposition to overwatch slots uses open-field or “air corridor” policy — document in README.

**Checklist (implementation also tracked in `TODO.md` → Pathfinding — road layer):**

- [ ] Unit tests: classify synthetic polylines (on-road vs cross-country); snap A→B around block; exclusion blocking a street triggers skirt or reroute.
- [ ] SIM smoke: UGV squad on suburban task — track follows streets; UAV wingmen hold offset over routed path, not through exclusion.
- [ ] **Failure modes:** No road data in bbox → fall back to open-field + operator warning; ambiguous Auto → conservative (open-field) or prompt.

**Do not** snap UAV-only patrol tasks to roads unless operator enables **Follow roads** or Auto confidence is high and policy allows aerial road corridor.

### 3D — Vertical geofences & router (extends § P; **depends on § P**, § P.1)

**Product lock:** v2 § P routes in the **horizontal plane** only (altitude on mission items / setpoints is separate). v3 promotes the shared Guardian router to **3D** so geofences are **volume** constraints: each fence has a **floor** and **ceiling** (see ``MissionGeofence`` `min_altitude` / `max_altitude` + reference). Operators can place **exclusion zones that float in the air** — required for tactics such as **radar coverage**, NOTAM-style volumes, or layered airspace — without treating every keep-out as a column from ground to sky.

| Concern | v2 (§ P) | v3 (§ 3D) |
|---------|----------|-----------|
| **Exclusion shape** | Horizontal polygon/circle only on fleet wire | Full **altitude band** enforced in planner, follower, and approach reporting |
| **Router** | 2D skirt inside inclusion | **3D** path: route around/over/under airborne exclusions per vehicle class and mission policy |
| **Authoring / map** | 2D map overlays | Extruded volume preview (floor/ceiling); validate band vs vehicle class |
| **FC upload** | Horizontal geometry to MAVSDK geofence | Stack-capable **3D** fence upload where autopilot supports it; Guardian still owns detour geometry |

**Checklist:**

- [ ] **Model & wire:** Use mission fence altitude bands end-to-end (authoring → effective geofences → router → optional FC upload); extend fleet `geofencePolygonsJSON` / MAVSDK path only when stack supports vertical fences — until then Guardian enforces 3D in MRE only.
- [ ] **3D router API:** `route3D(start, goal, fences, …)` — same consumers as § P (mission compile, runtime follower, § P.1 recovery, § T trail, § R snap + graph); exclusions are **non-traversable volumes**; inclusion is a bounded operable volume.
- [ ] **Airborne exclusions:** Support keep-outs that do not touch the ground (radar umbrella, transit corridors); primary and wingman paths may pass **under** or **around** per RoE / task policy — document defaults (UAV: avoid volume; UGV: N/A unless mast height modeled).
- [ ] **§ P.1 in 3D:** Predicted approach and breach recovery use vertical intersection (setpoint leg vs volume), not horizontal-only `MissionControlSquadConvoySetpointGeofenceUtilities`.
- [ ] **Wingman overwatch (§ R):** UAV formation offsets respect airborne exclusions on the routed track (climb/descend or lateral detour with primary).
- [ ] **Tests:** Unit — point/segment inside floating exclusion; route passes below floor or around volume. SIM — mission with mid-air exclusion; track never enters volume.
- [ ] **`README_FULL.md`:** 3D fence authoring, v2 horizontal-only vs v3 volume routing, FC vs Guardian enforcement split.

**Do not** block v2 § P on 3D — ship horizontal skirt first; § 3D extends the same router API once 2D behaviour is proven.

### M — MRE-owned primary mission (OFFBOARD/GUIDED; **depends on § P**, § T, § R for road tasks; **§ 3D** for altitude-band / airborne-exclusion tasks)

**Why consider this:** Field behaviour shows **AUTO_MISSION respects exclusion geofences** by **stopping** at the boundary — not by detouring. The limitation is **planning** (no skirt, no speed shaping, tight coupling to uploaded WP semantics), not “ignores geofences.” Running the **primary** on **OFFBOARD/GUIDED + streamed setpoints** — with MRE owning route progress, replanning, and cycle boundaries — aligns primary and wingmen under one controller and enables tactics AUTO_MISSION is poor at (dynamic **speed**, coordinated detours, road-following snap for UGV primaries, overwatch-aligned UAV motion).

**Prerequisites (do not start § M before):**

- **§ P — Pathfinding & geofence avoidance** shipped for wingman streams (and park/reposition).
- **§ T — Convoy trail** stable in cluttered maps.
- **§ R — Road routing** for tasks classified road-based (UGV primary at minimum).
- **§ 3D — Vertical geofences & router** for tasks with altitude-band fences or airborne exclusions (UAV / mixed airspace).
- Runtime setpoint follower proven at mission-run cadence with offboard-loss / reconnect policy operators trust.

**Checklist:**

- [ ] **Product / architecture note:** Document AUTO_MISSION vs MRE-primary tradeoffs (stop-at-fence vs skirt; road snap; mission-finished / WP advance semantics; RTL and breach policy; SIM vs live stacks) in `README_FULL.md`; phased rollout (per vehicle class, feature flag).
- [ ] **Cycle boundaries without AUTO:** Define how MRE detects “cycle complete” when primary is not on AUTO_MISSION (path progress along routed spine, last WP, operator intent) — compatible with `MRESquadsToDo.md`.
- [ ] **Mission upload role:** Clarify whether uploaded mission remains **failover / promotion** only, or shrinks to geofence + rally metadata while MRE owns leg geometry.
- [ ] **Primary follow subsystem:** Extend `MissionRunSquadFollowSubsystem` (or sibling) to stream **primary** setpoints along **pathfound / road-snapped** route in “MRE mission” mode; wingmen unchanged (trail / convoy on primary telemetry).
- [ ] **Speed & motion profiles:** Author or runtime-adjust speed along route segments under MRE.
- [ ] **Between-cycles / abort / promotion:** Re-verify wind-down when primary leaves AUTO_MISSION.
- [ ] **SIM smoke:** Full mixed squad — UGV primary on snapped roads + UAV overwatch; exclusions skirted; primary does not stall at fence unless policy says hold.
- [ ] **Gradual rollout:** Per-run or per-task “MRE drives primary”; distinct log keys for MRE-leg vs AUTO leg.

**Out of scope for v3 initial pass:** Removing mission upload entirely; Paladin-only autonomous mission authoring without operator template.

### U — Mission Control operator UI (deferred)

- [ ] **Mid-run squad formation:** Task triage **squad card** — operator changes squad formation shape while the run is live; Paladin or manual command; smooth retarget on OFFBOARD/GUIDED streams without dropping follow (offsets pathfound per § P / § F).

---

## Reference (modes — keep minimal)

| Guardian role | PX4 | ArduPilot |
|---------------|-----|-----------|
| Primary mission execution (v1–v2) | AUTO_MISSION | AUTO |
| Primary mission execution (v3 § M target) | OFFBOARD | GUIDED |
| Road-following route (v3 § R; UGV / classified tasks) | OFFBOARD / GUIDED setpoints on snapped graph | Same |
| UAV overwatch on road task (v3 § R) | OFFBOARD / GUIDED; offset from routed ground track | Same |
| Wingman formation follow | OFFBOARD | GUIDED |
| Simple target chase (not v1 formation) | — | FOLLOW / Follow Me |

**Offboard setpoint:** target command streamed continuously (position, velocity, yaw, or rover steer/throttle). Autopilot keeps stabilization; external controller owns high-level motion.

---

## Out of scope for this tracker

- Permanent squad delay / bench squad (`MRESquadsToDo.md` §7, `TODO.md` Squads).
- MRE “re-sync squads if drift” (`MRESquadsToDo.md` §7) — may share follow subsystem later.
- Full Paladin autonomous promotion without operator RoE — follows Rules of Engagement wiring in `TODO.md`.
- **Pathfinding implementation source tree** — tracked in `TODO.md` (Utilities / Mission Control planner); this file defines **squad-follow consumption** only.
