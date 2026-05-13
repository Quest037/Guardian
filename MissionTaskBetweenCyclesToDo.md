# Mission Task — Between cycles (RTL / Loiter / Park)

Operator-facing control for **what the squad does in the gap between task cycles** (repeating / delayed-repeat tasks). **Locked actions (v1):** **RTL**, **Loiter**, **Park** — no other between-cycles actions in this pass.

## Product rules

- **Authoring (mission template):** Operator sets between-cycles on each **task** in **Missions** → **Tasks** → task **settings** (local overlay / drawer chrome in `MissionsView` + `MissionTaskSettingsSidebar`).
- **Mission Control Setup (MCS):** Same field editable per task in **MC-S** task **settings** `AppDrawer` (today: `presentTaskSettingsSidebar` → `MissionRunTaskPolicyOverridesSidebarView` in `MissionControlSetupView`).
- **Mission Control Running (MCR):** Same field editable **live** in **MC-R** task **settings** `AppDrawer` (same `MissionRunTaskPolicyOverridesSidebarView` host path as MCS; ensure mutations apply to the **active run** mission snapshot and take effect for **future** between-cycle gaps without breaking an in-flight cycle unless product explicitly allows mid-gap edits).
- **Failure fallback (dispatch / execution):** If the **chosen** between-cycles action **fails** (catalogue / recipe / transport failure — define the exact failure signal in implementation), automatically fall back: **UAV → Loiter**; **any other vehicle class → Park** (use existing fleet atoms: loiter / park recipes or catalogue entries already used elsewhere).

## Model & persistence

- Align `MissionTaskBetweenCyclesAction` (and any UI labels) with **RTL | Loiter | Park** only for operator copy; map cleanly to existing fleet dispatch (`MissionRunFleetDispatch.betweenCyclesTaskDispatch` in `MissionControlModels.swift`). **Remove or retire** unused cases (e.g. `land`, `none`) from this surface **only if** mission JSON / defaults remain coherent — prefer one `Codable` shape with explicit migration only if the user later requests it (see repo **no legacy missions** rule: do not dual-decode old keys unless asked).
- Default template value: pick a single conservative default (e.g. **RTL** or **Loiter**) and document it in this file once chosen.
- Mission **template** save/load: field lives on `MissionTask` (`Mission.swift`); ensure MCS / MCR run copies stay in sync with `MissionControlStore` / `MissionRunEnvironment` mutation paths when editing live.

## Runtime (Paladin / executor)

- **Planning:** `MissionRunExecutionSubsystem` already accumulates `betweenCyclesCommands` when advancing cycles — extend or adjust so emitted commands match **only** RTL / Loiter / Park, and insert **fallback** dispatch when primary fails (per class rule above). Log template keys or structured events should make post-run review obvious (primary vs fallback).
- **Ordering:** Confirm order relative to deferred next-cycle start (`regularityDelay` / `setTaskStartDeferral`) so vehicles receive between-cycles behaviour **before** the next cycle arms, without racing autopilot state.
- **Squad / multi-slot:** Define behaviour when a task has multiple roster slots (primary + wingmen): same action for all vs primary-only — **default v1:** apply the same between-cycles dispatch to each bound vehicle unless an existing squad policy already says otherwise (document decision here after code read).

## UI / copy

- **Missions:** `MissionTaskSettingsSidebar` — add a labeled control (e.g. menu or segmented) visible when **regularity** implies between-cycle gaps (`continuous`, `continuousWithDelay`; hide or disable with help text for `onceAtStart` / `operatorTriggered` if no gap exists).
- **MC-S / MC-R:** `MissionControlPolicySidebars.swift` — extend `MissionRunTaskPolicyOverridesSidebarView` with the same control + short help (“Between laps, send the squad: …”). MCR: ensure **live** edits persist via existing `onChange` / `syncRunFromStore` patterns.
- Operator strings: use **RTL**, **Loiter**, **Park**; avoid autopilot jargon where a neutral fleet label exists; no roadmap copy (see `.cursor/rules/no-future-version-user-copy.mdc`).

## Tests

- **Dispatch mapping:** extend `MissionRunFleetDispatchPolicyMappingTests` for RTL / Loiter / Park → expected recipe or catalogue shape.
- **Fallback:** unit tests for “primary fails → UAV loiter / non-UAV park” classifier (pure function preferred) wired from execution or command subsystem.
- **UI / model (optional):** snapshot or decode test for `MissionTask` JSON round-trip with new enum set if `Codable` shape changes.

## Docs

- After behaviour is locked, add a short **README** subsection under mission / Mission Control run mechanics (or pointer from existing Mission Run doc) describing between-cycles scope, the three actions, and failure fallback — **not** before implementation is settled.

## Explicitly out of scope (this file)

- **“Swap In Replacement”** as a between-cycles action — captured in `NEXTVERSION.md` (2026-05-13 entry).
