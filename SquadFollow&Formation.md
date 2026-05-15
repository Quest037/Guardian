# Squad follow & formation — implementation checklist

Actionable tracker for **wingman follow** and **formation control** in Mission Control runs. Squad **lifecycle** (per-primary cycles, stagger, rollup, operator complete/abort) lives in **`MRESquadsToDo.md`**. This file covers **how wingmen move** relative to the primary and what MRE must own.

Related: **`TODO.md`** → Mission Control → Squads / Planner formations; **`README_FULL.md`** → Mission task authoring, reserve swap geometry.

---

## Locked architecture (v1)

| Role | Autopilot mode | Who decides movement |
|------|----------------|----------------------|
| **Primary** (squad leader) | **AUTO_MISSION** (PX4) / **AUTO** (ArduPilot) | Autopilot executes uploaded mission; MRE owns cycle start/stop and mission boundaries. |
| **Wingmen** | **OFFBOARD** (PX4) / **GUIDED** (ArduPilot) | **MRE** streams setpoints continuously; wingmen do **not** independently execute the mission path while following. |
| **Formation geometry** | External to autopilot | Guardian formation controller computes offset targets from primary telemetry; wingmen fly/drive toward those targets via OFFBOARD/GUIDED. |

**Principles (do not regress):**

- Every vehicle may **store** the same mission onboard; only the **primary** has **mission authority** (active execution) while the squad is in follow mode.
- Do **not** put all vehicles in AUTO_MISSION at once — causes drift, timing divergence, and formation instability.
- OFFBOARD/GUIDED setpoints are a **heartbeat**: stream at a stable rate (target ~20 Hz); loss triggers autopilot offboard-loss / guided failsafe (HOLD, RTL, LOITER, etc. per vehicle params).
- Prefer **OFFBOARD/GUIDED + streamed targets** over **AUTO_LOITER** for wingmen holding formation — loiter keeps internal nav active and fights formation control on rovers and tight offsets.
- **FOLLOW_TARGET / Follow Me** alone is **not** v1 formation control (pursuit only, no tactical offsets). v1 uses explicit offset positions from primary state.
- **v1 formation shape:** **convoy** (line behind / along primary heading) only. Chevron, arrowhead, and on-the-fly formation changes are **v2**.

**MRE ownership:** While a wingman is bound and following, **MRE controls that vehicle at all times** — mode entry, setpoint stream, pause/hold between cycles, promotion handoff, release, reserve swap reposition, abort/complete wind-down, and teardown. No “wingman runs its own AUTO mission” during active follow.

---

## Dependency order

1. **`MRESquadsToDo.md`** — per-squad primary lifecycle and MAVLink cycle boundaries on **primary only** (scheduling / MC-R items shipped there) — wingman follow must respect squad cycle keys and not block sibling squads.
2. This file **§ v1** — wingman pipeline on top of stable primary squads.
3. **`MRESquadsToDo.md`** promotion / release RoE — uses mode switches defined here.
4. **§ v2** — additional formation shapes and live formation changes.

---

## v1 — Wingmen working end-to-end (convoy)

### A — Model & mission authoring

- [ ] **Squad follow binding:** Wingman roster rows (`.wingman`, `leaderRosterDeviceId`) resolve to the same squad as primary; `buildTaskSquadMissions` / planner include wingman assignment IDs in squad scope (telemetry, logs, prompts use **TaskName:N** via `MissionControlSquadUtilities`).
- [ ] **Mission upload on wingmen:** Upload same task mission to wingmen for **promotion / failover** readiness; while following, wingman does **not** start AUTO mission execution.
- [ ] **Formation field (convoy only):** Task or squad policy defaults to **convoy**; document in mission workspace (no chevron/arrowhead picker in v1). Align with `TODO.md` “Formations” bullet as **convoy-only** until v2.
- [ ] **Spacing parameters:** Convoy offset(s) — e.g. along-track distance per wingman index, optional lateral lane — authored or locked defaults; validate against vehicle class (UAV vs UGV).

### B — Fleet catalogue & recipes (Layer 0 / 1)

- [ ] **Mode commands:** Catalogue atoms (or existing `do.mode`) for PX4 **OFFBOARD** and ArduPilot **GUIDED**; primary remains **AUTO_MISSION** / **AUTO** when starting squad execution.
- [ ] **Setpoint streaming:** Layer 0 commands for position / velocity / yaw (and rover steering if required) suitable for OFFBOARD/GUIDED; document required stream rate and frame (NED / body) per stack.
- [ ] **Hold / pause wingman:** Recipe or command path to stream “hold current” setpoints without exiting OFFBOARD/GUIDED (between-cycles tactic for wingmen mirrors primary policy where product requires).
- [ ] **Offboard-loss awareness:** Surface failsafe outcome in logs when stream stops; MRE must not silently stop streaming while wingman still assigned to follow.

### C — MRE formation controller (runtime)

- [ ] **`MissionRunSquadFollowSubsystem` (or equivalent):** Owns wingman follow for all active squads; subscribes to **primary** position, heading, velocity (and mission state); computes each wingman **desired position = primary + convoy offset**.
- [ ] **Start follow:** When squad primary enters executing cycle, wingmen on that squad: transition to OFFBOARD/GUIDED, begin setpoint stream, confirm mode via telemetry before marking wingman “on formation.”
- [ ] **Continuous control loop:** Timer/task on MRE executor cadence; **re-stream setpoints** every tick; handle primary telemetry gaps (hold last offset vs freeze wingman — product choice, document in README).
- [ ] **Stop follow:** On squad complete/abort, primary promotion, wingman release, reserve swap, or run teardown — stop stream, command safe mode (HOLD / LOITER / land per policy), clear follow state.
- [ ] **Between-cycles:** When primary is in between-cycles tactic, wingmen follow **same squad policy** (RTL / loiter / park / hold formation) — wingman branch in between-cycles dispatch, not independent AUTO mission.
- [ ] **Stagger / first wave:** Wingmen on squads whose primary has not launched yet stay idle/disarmed or parked per stagger; only wingmen whose primary is active enter follow loop.
- [ ] **Geofence / fleet barriers:** Wingman setpoints respect same geofence and serialized fleet queue rules as primary (no bypass around `MissionRunCommandSubsystem`).

### D — Integration with squad lifecycle (`MRESquadsToDo.md`)

- [ ] **Cycle boundaries:** MAVLink mission **finished** on **primary only** completes that squad’s cycle; wingman follow pauses or holds per between-cycles policy until next primary cycle starts.
- [ ] **Per-squad independence:** Squad A primary ending must not stop wingman follow loop for Squad B on another task/primary (same cross-squad lock as MRE squads doc).
- [ ] **Operator squad complete/abort:** Wind down **all assignments in squad** (primary + wingmen); stop wingman streams before slot evidence moves to terminal states.
- [ ] **Logging:** Distinct template keys for wingman mode entry, stream start/stop, formation error, offboard-loss; params include squad label (`Dagger:1`) and assignment/vehicle ids.

### E — Promotion & release (v1 behaviour)

- [ ] **Promotion (RoE `SquadPromote`):** On primary loss / operator confirm: elected wingman **stops** OFFBOARD/GUIDED follow, switches to **AUTO_MISSION** / **AUTO**, resumes mission from checkpoint; remaining wingmen retarget new primary’s telemetry (update offsets / leader binding).
- [ ] **Release (RoE `RosterRelease`):** Remove wingman from follow loop; safe mode; slot void / `voidedVehicles` map marker per MRE squads doc; optional reserve swap is separate flow.
- [ ] **Reserve swap-in:** Reposition reserve (existing v1 geometry policy) then attach as wingman or primary; if wingman, enter follow under MRE control; do not leave reserve in AUTO mission during follow.

### F — Mission Control UI (operator)

- [ ] **MC-R map:** Show wingmen relative to primary (convoy offsets); distinguish primary vs wingman markers (existing roster slot chrome).
- [ ] **Status:** Wingman row shows follow state (arming, following, hold, lost link, offboard failsafe) without exposing raw mode jargon where a semantic label exists.
- [ ] **No v1 formation picker:** Convoy only; hide or disable non-convoy shapes until v2.

### G — Tests & docs

- [ ] **Unit tests:** Convoy offset math (heading rotation, wingman index ordering); primary telemetry → desired position; promotion retarget offsets.
- [ ] **Integration tests (SIM):** Primary AUTO_MISSION + two wingmen OFFBOARD/GUIDED convoy; stream stop triggers expected failsafe class; promotion switches promoted vehicle to mission mode.
- [ ] **`README_FULL.md`:** Short subsection — primary AUTO, wingmen OFFBOARD/GUIDED, MRE streams setpoints, convoy v1; pointer to this file and `MRESquadsToDo.md`.
- [ ] **`AGENTS.md`:** Link this tracker for wingman follow (separate from squads conversion checklist).

---

## v2 — Formations beyond convoy (deferred)

Do not block v1 on these. Capture design when starting v2.

- [ ] **Formation enum:** Chevron, arrowhead, line abreast, custom offsets per wingman index.
- [ ] **Mission authoring:** Formation picker overrides pattern-default convoy; per-squad override optional.
- [ ] **Live formation change:** Operator or Paladin command to change shape mid-run; smooth retarget without dropping OFFBOARD/GUIDED stream.
- [ ] **Tactical offsets:** Leader heading + speed + curvature for moving formations (not static body offsets only).
- [ ] **Collision / spacing guards:** Minimum separation, max closure rate between wingmen.
- [ ] **Advanced promotion:** Election policy (nearest to path, battery, link) documented and testable.

---

## Reference (modes — keep minimal)

| Guardian role | PX4 | ArduPilot |
|---------------|-----|-----------|
| Primary mission execution | AUTO_MISSION | AUTO |
| Wingman formation follow | OFFBOARD | GUIDED |
| Simple target chase (not v1 formation) | — | FOLLOW / Follow Me |

**Offboard setpoint:** target command streamed continuously (position, velocity, yaw, or rover steer/throttle). Autopilot keeps stabilization; external controller owns high-level motion.

---

## Out of scope for this tracker

- Permanent squad delay / bench squad (`MRESquadsToDo.md` §7, `TODO.md` Squads).
- MRE “re-sync squads if drift” (`MRESquadsToDo.md` §7) — may share follow subsystem later.
- Full Paladin autonomous promotion without operator RoE — follows Rules of Engagement wiring in `TODO.md`.
