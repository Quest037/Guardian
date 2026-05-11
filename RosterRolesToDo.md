# Roster roles — Missions extension subsystem

This document is the **implementation backlog** for turning roster **behavior roles** (distinct from primary / wingman / reserve **slot** roles) into a first-class **Missions-owned catalog** that **Mission Control / MRE** consume at run time. Work should stay **coherent with `TODO.md`** (Mission Roster Slots) but **detailed planning lives here**.

---

## 0 — Why this exists

- **Missions** defines mission templates, including **rosters** (`RosterDevice`) and per-device **behavior role** (`RosterRole`). Operators pick from the built-in catalog in the Missions UI (v1); slots may still default to **`.none`** until set.
- **Mission Control + MRE** execute runs. They should **not** own the role definition table; they **resolve** `role_id` → machine tags / weights and apply policy. **Extension** of the catalog is a **Missions concern**; **engagement** for behavior is **MRE**.

**Rule of thumb:** Plugins that want new roles or tags **extend the Missions subsystem** (registration API). Paladin / MC **read** the resolved profile from the compiled mission snapshot.

---

## 1 — Current code (anchor points)

| Area | Location |
|------|-----------|
| Persisted role on roster device | `Sources/GuardianHQ/Systems/Missions/Models/Mission.swift` — `RosterRole` on `RosterDevice.role` |
| Slot (primary / wingman / reserve) | `MissionRosterSlotRole` — **not** the same as behavior role |
| Missions UI (role picker) | `Sources/GuardianHQ/Systems/Missions/Views/MissionsView.swift` — `ForEach(RosterRole.allCases)`, `rosterBehaviorRoleLabel` |
| Catalog + MRE DTO types | `Sources/GuardianHQ/Systems/Missions/Models/RosterRoleCatalog.swift` |

**Shipped (v1 Missions):** eight built-in behavior roles + `none`; catalog tags/weights; `RosterRoleMREPayload` for future MC/MRE export; `RosterDevice` decode keeps legacy keys (`character`, etc.) and maps unknown `role` strings to `.none`. Summary and file anchors: **[`README.md`](README.md)** (Mission roster behavior roles).

---

## 2 — Ownership model

| Concern | Owner |
|---------|--------|
| Canonical role IDs, display strings, tags, default weights | **Missions** (catalog + types) |
| Plugin registration of extra roles / tag overlays | **Missions** plugin surface (same process as other mission extensions) |
| Persisted choice on template | `RosterDevice.role` (string-backed enum or string id — see §6) |
| Run-time interpretation, logging, policy tilt | **MC / MRE** (consumes DTO only) |

**Dependency direction:** MC imports Missions **types** (or a thin shared module if you split later); Missions must **not** import Paladin. If circular risk appears, extract **`RosterRoleDefinition` + tags** into a small file both targets can import without pulling full Missions UI.

---

## 3 — v1 behavior roles (eight)

Stable **slug** = `RosterRole` case raw value (or parallel `id` string if you move to open set later).

| Slug | Display | Blurb (operator + Paladin hint) |
|------|---------|----------------------------------|
| `guardian` | Guardian | Defend / screen a designated asset or choke; hold ground over pursuit. |
| `scout` | Scout | Sense forward; prefer evasion, early exit, and report-before-commit. |
| `marauder` | Marauder | Strike / pressure; accept exposure for decisive effect. |
| `relay` | Relay | Extend link and awareness; favor geometry that keeps the stack connected. |
| `shepherd` | Shepherd | Formation integrity; keep squad inside timing/spacing envelopes. |
| `warden` | Warden | Overwatch + RoE bias; deconflict and throttle until the picture is clean. |
| `breacher` | Breacher | Vanguard through hazard; clear corridor for the main body. |
| `medic` | Medic | Recover / sustain; escort, cover, degraded-wingman support over scoring. |

**Dropped idea:** **Anchor** — squad **primary** already provides spatial / command anchor; no separate role.

**Guardian vs Warden (doc for UX + MRE):** Guardian optimizes for **protecting a thing**; Warden optimizes for **rules and cross-fleet clarity**. Both can be “defensive”; Paladin uses tags to separate **asset-tied** vs **RoE-tied** behavior.

---

## 4 — Machine-facing catalog (`RosterRoleDefinition`)

Each built-in (and plugin) role exposes a **definition** used for UI and for **MRE export**:

Suggested fields:

- **`id`** — stable string (matches enum raw value in v1).
- **`displayName`**, **`blurb`** — Missions UI + tooltips.
- **`tags: Set<RosterRoleTag>`** — namespaced tokens (§5).
- **`weights: RosterRoleWeights`** — optional bounded floats 0…1 for continuous blending (§6).
- **`schemaVersion`** — catalog revision; bump when tags/weights break semantics.
- **`source`** — `.builtin` / `.plugin(pluginID)` for diagnostics and merge rules.

**Resolution order:** built-in definitions → plugin **additive** tag overlays (and optional weight deltas with **caps**) → ``ResolvedRosterRole`` / MRE payload on the run (see [`MissionRunRosterRoleResolution.swift`](Sources/GuardianHQ/Systems/MissionControl/Models/MissionRunRosterRoleResolution.swift)).

---

## 5 — Tag vocabulary (registry)

Use **dot namespaces** so plugins cannot collide and MRE can `switch` on prefixes.

| Namespace | Meaning | Example tokens |
|-----------|---------|------------------|
| `posture.*` | High-level stance | `posture.defensive`, `posture.offensive`, `posture.probe`, `posture.support`, `posture.overwatch`, `posture.vanguard` |
| `risk.*` | Exposure appetite | `risk.low`, `risk.medium`, `risk.high` |
| `engage.*` | Contact bias | `engage.retain`, `engage.press`, `engage.avoid`, `engage.commit`, `engage.deconflict`, `engage.minimize`, `engage.coordinate` |
| `formation.*` | Spacing / sync | `formation.tight`, `formation.loose`, `formation.lead`, `formation.escort`, `formation.station_keep`, `formation.aggressive_slot` |
| `sensor.*` | Sensing posture | `sensor.forward`, `sensor.wide` |
| `comms.*` | Link behavior | `comms.mesh`, `comms.report_first` |
| `logistics.*` | Sustain / bridge | `logistics.bridge`, `logistics.sync`, `logistics.sustain` |
| `recovery.*` | Help degraded assets | `recovery.primary`, `recovery.cover` |
| `roe.*` | Rules-of-engagement tilt | `roe.strict`, `roe.conservative`, `roe.proportional` |

**v1 suggested tag bundles** (exact sets to implement in code + unit tests):

- **guardian:** `posture.defensive`, `risk.low`, `engage.retain`, `formation.anchor_bias`, `recovery.cover`, `roe.conservative`
- **scout:** `posture.probe`, `risk.medium`, `engage.avoid`, `sensor.forward`, `formation.loose`, `comms.report_first`
- **marauder:** `posture.offensive`, `risk.high`, `engage.press`, `formation.aggressive_slot`, `roe.proportional`
- **relay:** `posture.support`, `risk.low`, `comms.mesh`, `logistics.bridge`, `formation.station_keep`
- **shepherd:** `posture.support`, `risk.low`, `formation.tight`, `engage.coordinate`, `logistics.sync`
- **warden:** `posture.overwatch`, `risk.medium`, `roe.strict`, `engage.deconflict`, `sensor.wide`, `formation.flex`
- **breacher:** `posture.vanguard`, `risk.high`, `engage.commit`, `formation.lead`, `recovery.expendable_order` *(means “accept point position in stack,” not moral framing)*
- **medic:** `posture.support`, `recovery.primary`, `risk.medium`, `engage.minimize`, `formation.escort`, `logistics.sustain`

Document any new tag in this section before shipping.

---

## 6 — Weight knobs (optional v1, for Paladin blending)

Small numeric map **in addition to** tags; keys are stable:

| Key | Semantics |
|-----|-----------|
| `aggression` | 0 = hold / peel, 1 = push |
| `tenacity` | Stick vs abandon position |
| `cohesion` | Pull toward formation / timing |
| `roe_slack` | 0 tight, 1 permissive |
| `support_bias` | Help degraded peers |

Ship **default table per role** in Missions; MRE reads resolved numbers only.

---

## 7 — MRE / Paladin consumption contract (DTO)

When compiling a run (or hydrating Paladin domain), emit a **versioned** payload per roster device (or per assignment):

```json
{
  "role_schema": 1,
  "role_id": "medic",
  "tags": ["posture.support", "recovery.primary", "formation.escort"],
  "weights": {
    "aggression": 0.2,
    "tenacity": 0.6,
    "cohesion": 0.75,
    "roe_slack": 0.25,
    "support_bias": 0.95
  }
}
```

- **`role_schema`:** bump when tags/weights meaning changes.
- **MRE rule:** never branch on `displayName`; only `role_id`, `tags`, `weights`.
- **Logging:** include `role_id` + `source` in structured mission-run logs for debugging plugin overlays.

---

## 8 — Plugin extension (Missions only)

**Shipped (overlays on built-in roles):** `RosterRoleExtensionRegistry` + `RosterRolePluginOverlay` — additive tags, bounded weight deltas (±0.25 total per knob across all plugins), replace-if-same `pluginID` + `targetRole`. `RosterRoleResolvedDefinition.contributingPluginIDs` carries audit provenance. Summary: **[`README.md`](README.md)** (Mission roster behavior roles).

**Not shipped yet:**

- **New `role_id`** (not a `RosterRole` case): full definition from plugin — needs open-set persistence on `RosterDevice` (or equivalent).
- **Merge rules** for new ids (two plugins claiming the same new id) and **plugin `RosterRoleDefinition` arrays** — optional sugar on top of `registerOverlay`; can mirror `missionRosterRoleContributions() -> [RosterRoleDefinition]` later.
- **Existing `id`:** built-in tags are never removed by overlays; v1 does not support `removesTags` (defer to v2 with review).

---

## 9 — v1 checklist (complete)

Shipped (see **[`README.md`](README.md)** — Mission roster behavior roles):

- Catalog, persistence, lossy decode, plugin overlays, MC resolver (`MissionRunRosterRoleResolver`, ``ResolvedRosterRole``), ``MissionRunEnvironment/rosterRoleResolutionsByDeviceID``, execution-start MC log (`rosterBehaviorRolesSnapshot`), Paladin policy-tilt stub log, tests under `RosterRole*` / `MissionRunRosterRole*`.

**Optional UI polish (not v1-blocking):** role icon or color chip per tag cluster; theme tokens for any new roster chrome — track with general Missions UI work if desired.

**Post-v1 (open catalog / new `role_id`):** persistence and merge rules as in §8 *Not shipped yet*.

---

## 10 — Non-goals (v1)

- Paladin fully **acting** on every tag (ship DTO + stub / logging first).
- Automatic role inference from vehicle class alone.
- Replacing `MissionRosterSlotRole` (primary/wingman/reserve) — orthogonal.

---

## 11 — Resolved decisions (v1)

- **`ResolvedRosterRole` / resolver:** `Sources/GuardianHQ/Systems/MissionControl/Models/MissionRunRosterRoleResolution.swift` — Mission Control owns the run envelope slice; Missions types stay in `GuardianHQ` without UI coupling.
- **Unknown `role` strings on decode:** map to `.none` (missions stay loadable). **Plugin-only `role_id`** not in `RosterRole`: deferred until template persistence supports an open id (§8).

---

## 12 — Related

- Operator-oriented summary: **[`README.md`](README.md)** (Mission roster behavior roles)
- App backlog: `TODO.md` → **Mission Roster Slots**
- Missions models: `Mission.swift`, `RosterRoleCatalog.swift`, `RosterRoleExtensionRegistry.swift`
- MC resolution + run hook: `MissionRunRosterRoleResolution.swift`, `MissionRunEnvironment.swift`, `MissionRunExecutionSubsystem.swift` (snapshot log after staging batches)
- UI: `MissionsView.swift`

---

*Last updated: v1 roster roles shipped; optional polish and open-set roles remain future work.*
