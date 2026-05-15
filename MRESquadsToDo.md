# MRE squads — conversion checklist

Squad = **primary roster row** per task path (AUTO mission cycles on primary only). Wingmen/reserves: **OFFBOARD / GUIDED + FOLLOW** later — **ignored** for MAVLink mission-cycle boundaries.

**Stagger:** ``MissionTaskStaggerTrigger`` on each task (mission workspace **Squad stagger**); MRE first wave uses ``MissionTaskStaggerPolicy``. Waypoint / operator release for squads after the first primary ships in §4–5.

**Squad naming:** sequential under task, e.g. task **Dagger** → **Dagger:1**, **Dagger:2**, …

**Operator:** **squad-level complete / abort** required in addition to existing **task-level** complete/abort.

---

## Auto pipeline — task recovery → complete (locked)

Whole-run / task auto wind-down chooses **recovery → complete** unless **every** squad is in or headed to **aborting / aborted** (squads already aborting/aborted are **disregarded** when deciding that branch among the rest).

| Squads | Situation | Task auto pipeline |
|--------|-----------|-------------------|
| 3 | 1 aborting/aborted; 2 grace-complete; 3 complete-now | **Recovery → complete** |
| 2 | 1 completed; 1 executing → abort now | **Recovery → complete** |

**Rule:** Auto **recovery → complete** unless **all** squads are aborting/aborted (or going there). Mixed abort + complete squads still yields **recovery → complete** per table above.

---

## 5 — Scheduling (`MissionRunSchedulingSubsystem`)

- [x] **Squad-level graceful after-cycle** — pending keyed by primary assignment; delivers on that squad’s MAVLink cycle end; task-wide vs squad pending are mutually exclusive per task.

---

## 6 — MCS / MC-R UI (`MissionControlSetupView`, running views, sidebars)

- [x] **One task card**; **per-squad** progress bars (triage + compact list when a path has multiple primaries) + existing stagger / “Start next squad” controls.
- [x] Squad-level **complete** / **abort** (immediate + graceful) with ``GuardianConfirm`` / ``GuardianConfirmDanger`` on the shared run confirm host; per-squad revoke for scheduled squad wind-down.
- [x] Live log / chips: sequential **Dagger:1** naming; speaker or params show squad when useful.
- [x] Tasks-card wind-down notices include per-squad scheduled graceful; task rollup badge still uses ``taskStateByTaskID`` (squad rollup already in derivation).

---

## 7 — Follow-on (not this pass — capture when touching code)

- [ ] Permanent squad delay / bench squad + manual restart (later feature).
- [ ] MRE “re-sync” squads if drift (later).
- [ ] Wingman OFFBOARD/GUIDED convoy follow — ``SquadFollow&Formation.md`` § v1 (separate from MAVLink cycle end on primary).
