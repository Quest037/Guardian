# CesiumJS map integration — product & architecture brief

Design reference for adding a **3D operational map** to Guardian alongside the existing **2D Leaflet** stack. Use this document to derive a future implementation tracker (`TODO.md` / dedicated `*ToDo.md`) — it is **not** a shipping checklist.

**Related:** `TODO.md` → **Map System**, **Live Drive**; `README_FULL.md` → **Live Leaflet map — bridge coalescing**; `SquadFollow&Formation.md` (convoy geometry, streamed setpoints); `MissionGeofence` (altitude bands).

**External anchor:** Defense / emergency COP pattern with Cesium terrain + mission layers — e.g. [XRF Connects and Integrates Missions with Cesium](https://cesium.com/blog/2026/04/14/xrf-connects-and-integrates-missions-with-cesium/) (terrain base, org-specific 3D Tiles on top, SaaS vs self-hosted ion).

---

## What we are building (and what we are not)

### Goal

A **dependable 3D common operational picture** for **running** missions and **Live Drive** — where operators see:

- **Ground truth shape** — vehicles follow terrain (UGV on slopes, not “ghosting” through painted hills).
- **Air truth** — UAVs at meaningful height above that same ground (AMSL + optional AGL).
- **Mission context in 3D** — routes, geofence altitude bands, squad-relevant geometry.
- **Performance trust** — smooth enough in `WKWebView` that operators use it under load (multi-vehicle telemetry).

This is **operational geospatial context** (military / enterprise style), not a consumer map with satellite basemaps as the product.

### Non-goals (v1 / spike)

- Replacing **all** maps with Cesium (mission **authoring**, settings SIM picker, lightweight 2D surfaces stay on Leaflet).
- Photorealistic globe / mandatory satellite imagery (OPSEC, bandwidth, and visual noise).
- Building a full C2 platform (single COP across XR, command tables, AI briefing) — Guardian integrates **mission + fleet + squads** into one 3D view where it helps MC-R and Live Drive.
- Centimeter survey accuracy or building-level collision (unless a future site pack provides it).

---

## Surface scope

| Surface | Map engine (target) | Rationale |
| --- | --- | --- |
| **Mission Control — running (MC-R)** live overview | **CesiumJS** (3D mode) + optional 2D fallback | Squad / fleet situational awareness, terrain, geofences in volume |
| **Live Drive** (mission overlay + freestyle) | **CesiumJS** (3D mode) + optional 2D fallback | Manual control with spatial context |
| **Mission Control — setup (MCS)** staging map | **Leaflet** (current) | Draggable SIM staging; 3D lower priority |
| **Missions workspace** (template edit) | **Leaflet** (current) | Dense waypoint / fence authoring |
| **Settings** SIM spawn picker | **Leaflet** (current) | Single pin, no fleet motion |

**Operator choice (future):** Per operational screen, toggle **2D** / **3D** where both exist — same underlying mission + hub data, different renderer.

---

## Layer model (Guardian on Cesium)

Think in stacked responsibilities (similar to “Compass base + mission layers” in the XRF post):

```
┌─────────────────────────────────────────────────────────────┐
│  Guardian symbology & interaction                           │
│  Vehicles, selection, follow camera, context menus, squads,   │
│  floating reserve affordances, operator graphics              │
├─────────────────────────────────────────────────────────────┤
│  Mission overlays (from template + run envelope)            │
│  Task routes, mission points, geofence volumes (min/max     │
│  alt + reference), runtime mission points                    │
├─────────────────────────────────────────────────────────────┤
│  Optional site / intel layers (later)                       │
│  Org 3D Tiles, local mesh, drone products — untextured OK   │
├─────────────────────────────────────────────────────────────┤
│  Ground surface (elevation) — required for slope honesty    │
│  See § Terrain strategies                                   │
├─────────────────────────────────────────────────────────────┤
│  Basemap imagery — default OFF or minimal                   │
│  Flat / tactical tint; no dependency on satellite tiles     │
└─────────────────────────────────────────────────────────────┘
```

**Principle:** **Shape** (elevation) and **look** (imagery) are decoupled. UGV slope-following needs **shape**; it does not need heavy **imagery** tiles.

---

## Vehicle altitude & terrain (locked product intent)

### Problem today

Leaflet markers are **lat/lon only** (`MapVehicleMarker`). Hills exist only in **texture**; hub altitude exists for logic but not map truth. UGVs appear to drive through mountains.

### Target behavior

| Vehicle class | Vertical placement | Display extras |
| --- | --- | --- |
| **UGV / ground** | **Clamp to ground** (or terrain sample + small offset) | Optional tiny offset for icon clearance |
| **UAV / aerial** | **AMSL** from hub (`altitudeAmslM` / `absoluteAltM`) | Optional **AGL** = AMSL − sampled terrain; leader line to ground |
| **USV / UUV** | TBD per domain; default like UGV or AMSL per fleet class | Class policy in map bridge |

**Altitude references** for fences and waypoints already exist in mission data (`MissionGeofenceAltitudeReference`: relative home, AGL, MSL). The 3D map should **visualize** those bands as extruded volumes / corridors, using the **same reference rules** as upload / fleet policy (label clearly in UI).

**Do not** use vehicle baro alone to place UGVs on screen if clamping: **terrain at lat/lon** defines ground contact; telemetry lat/lon drives horizontal track.

### Cesium mechanisms (implementation hint)

- `HeightReference.CLAMP_TO_GROUND` / `RELATIVE_TO_GROUND` for ground units.
- Absolute ellipsoid height for aerial units.
- `sampleTerrainMostDetailed` for AGL labels, leader lines, and **background preload** (§ Preload).

**Datum note:** Cesium commonly uses **WGS84 ellipsoid** heights; MAVLink / hub fields are treated as AMSL-ish for ops. Document geoid error for survey users; tactical use may accept v1 without geoid correction.

---

## Terrain strategies (phased)

Not mutually exclusive — pick per deployment profile.

| Phase | Approach | Best for |
| --- | --- | --- |
| **A — Spike** | Cesium World Terrain (or equivalent provider), **imagery off**, flat globe material | Prove clamp, UAV height, bridge perf in `WKWebView` |
| **B — Controlled ops** | **Self-hosted** quantized-mesh and/or **Cesium ion Self-Hosted** | Classified-adjacent, no public CDN |
| **C — AOI pack** | `HeightmapTerrainProvider` / custom DEM (**DTED**, national grid, customer survey) for mission bounding box | Disconnected exercise, predictable bandwidth |
| **D — Corridor “ghost mesh”** | Pre-triangulated **untextured** mesh from DEM along mission polyline + formation buffer | Smallest runtime cost; preload friendly; narrow AOI |

**“Ghost mesh”** here means: **3D outline of terrain without photorealistic map graphics** — single-color or hillshade material, optional wireframe, **no** satellite layer. Still real geometry, not a fake flat plane.

**3D Tiles** (buildings, site models) are **optional overlays**, not a substitute for ground elevation. Clamp-to-ground does not stop icons passing through **buildings** unless separate assets or logic are added.

---

## Background terrain preload (mission-driven)

**Intent:** Warm elevation data along the **upcoming route** so terrain is ready when squads arrive — avoid pop-in and first-frame clamp lag.

**Inputs (Guardian-owned polylines):**

- Primary **uploaded mission** path / next leg waypoints.
- **Convoy** centerline + **lateral buffer** (wingmen offset from primary — see `SquadFollow&Formation.md`).
- Optional **rolling lookahead** from live primary position (e.g. next 1–5 km).

**Mechanism (Cesium):** Densify polyline → batch `Cartographic` positions → `sampleTerrainMostDetailed(terrainProvider, batch)` in idle/worker time with throttled concurrency. Same terrain provider used for rendering.

**Not required:** Flying a hidden camera along the route (loads imagery + frustum waste) unless imagery preload is explicitly desired later.

**Guards:** Cap corridor length, width, and concurrent requests; cancel on run complete / mission change; respect offline packs (preload only where DEM/tiles exist locally).

---

## Data integration (existing Guardian sources)

Reuse — do not fork parallel mission truth.

| Data | Source (today) | 3D map use |
| --- | --- | --- |
| Vehicle pose | `FleetLinkService` hub: lat/lon, heading, `altitudeAmslM`, `absoluteAltM`, `relativeAltM` | Entity position + labels |
| Live markers | `Utilities.liveLeafletMap` / `LiveLeafletMapMarkerBuildInputs` | Extend bridge payload with **height + clamp policy** per vehicle class |
| Routes / waypoints | Mission template, selected task | 3D polylines / waypoint handles with altitude |
| Geofences | `MissionGeofence` min/max + reference | Extruded polygon / cylinder volumes |
| Run-only geometry | `MissionRunEnvironment` runtime points, merged fences | Same as Leaflet structural identity splits |
| Squad follow | `MissionRunSquadFollowSubsystem`, convoy utilities | Preload corridor; optional offset ribbons |
| Map perf patterns | `GuardianLeafletMissionBridgeCoalescer`, hub throttle ~10 Hz, equatable payloads | **Mirror** for Cesium bridge (marker-only vs structural rebuild) |

**Bridge:** New `GuardianCesiumMissionBridge*` (or shared neutral `GuardianMapBridge*`) should follow the same **structural vs motion** split documented for Leaflet in `README_FULL.md`.

---

## Deployment & security postures

| Posture | Terrain / tiles | Notes |
| --- | --- | --- |
| **Dev / demo** | Cesium ion SaaS acceptable | Token in app config; imagery off by default |
| **Field / off-grid** | ion Self-Hosted and/or **mission AOI DEM pack** | No reliance on public imagery CDN |
| **Customer site** | Customer-supplied DEM → heightmap or ghost mesh tileset | Package with mission export (future) |

Align with operator expectation: **if the 3D view stutters or lies about ground, operators will ignore it** (same trust bar called out in the XRF article).

---

## UX & interaction parity (MC-R / Live Drive)

Minimum parity with Leaflet operational maps before defaulting 3D on:

- Vehicle **selection**, **follow** / tracked entity camera.
- **Context menus** (`GuardianMapContextMenuPolicy`) — same actions, 3D pick handling.
- **Recenter** / viewport nudge semantics (`recenterNonce`, `viewportNudge`).
- **Preserve view** on hub motion; structural rebuild only on route/fence topology change.
- **Floating reserve** swap picker affordances (pulse / eligibility) where applicable.
- Theme: `GuardianTheme` / semantic colors for overlays — avoid raw consumer-map chrome.

**Keyboard / confirm / drawer** stacking unchanged (window-level overlays per app rules).

---

## Performance & engineering constraints

- **Host:** `WKWebView` in macOS app (same class of constraints as `OSMMapView`).
- **Target motion rate:** Match Leaflet hub marker cap (~**10 Hz** default) for pose updates; structural updates rare.
- **Profiling:** Cesium-side counters analogous to `GuardianLeafletMissionBridgeProfiler` / `LiveLeafletMapMarkerPipelineProfiler`.
- **Env overrides:** Consider `GUARDIAN_MAP_*` style knobs for Hz cap, preload enable, terrain provider URL.
- **Multi-vehicle:** Spike with **4+ SITL** streams (per existing map perf smoke guidance).

---

## Suggested implementation phases (for future todos)

Use these as **epic boundaries** when splitting `TODO.md` — order matters.

### Phase 0 — Spike (evaluate)

- Embed CesiumJS in experimental `WKWebView` host.
- Terrain on, imagery off; one UGV clamp + one UAV AMSL.
- Single vehicle follow camera; manual pan still works.
- Bridge one hub stream at ≤10 Hz; measure jank and memory.
- **Exit:** Go / no-go on MC-R + Live Drive 3D mode.

### Phase 1 — Operational 3D mode (MC-R + Live Drive)

- 3D/2D toggle on operational surfaces only.
- Shared marker builder extension (class → clamp vs absolute).
- Mission route + geofence volumes in 3D.
- Context menu + selection + recenter parity.
- Reuse `LiveLeafletMapMarkerBuildInputs` factories where possible.

### Phase 2 — Terrain honesty & squad ops

- UGV clamp production-hardened (terrain-ready gating).
- UAV leader line + MSL/AGL label policy.
- Background preload along primary path + convoy buffer.
- Tie preload to squad cycle / next leg boundaries.

### Phase 3 — Deployable terrain

- Self-hosted or packaged AOI terrain (DEM / ghost mesh).
- Offline preload from mission pack; disable ion SaaS in field profile.
- Document operator workflow for importing site elevation.

### Phase 4 — Optional richness

- Site 3D Tiles (untextured or classified symbology).
- Line-of-sight / viewshed experiments (not v1).
- XR / multi-station COP (out of Guardian app scope unless product expands).

---

## Spike acceptance criteria (Phase 0)

1. UGV track on sloped terrain mesh — **no** obvious tunneling through a hill when clamped.
2. UAV visibly above terrain; altitude label readable.
3. Camera follow on selected vehicle without runaway zoom on update.
4. ≤10 Hz pose updates without sustained frame violations on reference hardware (document machine).
5. No hard dependency on satellite imagery layer.
6. Run teardown disposes WebView / cancels preload without leak warnings.

---

## Backlog seeds (derive todos from here)

- [ ] CesiumJS `WKWebView` host + JS bridge skeleton (Swift ↔ Cesium).
- [ ] Terrain provider abstraction (SaaS / self-hosted / heightmap / none).
- [ ] Extend map vehicle model: height, `HeightReference` policy, vehicle class.
- [ ] MC-R live overview: 3D mode toggle + structural/motion identity ports from Leaflet.
- [ ] Live Drive: 3D mode for mission overlay + freestyle.
- [ ] Geofence 3D extrusion from `MissionGeofence` (+ run merge rules).
- [ ] Waypoint / route 3D polyline from mission altitude fields.
- [ ] `sampleTerrainMostDetailed` preload service (polyline + corridor buffer).
- [ ] Squad-aware preload triggers (next leg, convoy width constant).
- [ ] Bridge coalescing + profiling parity with Leaflet.
- [ ] Context menu pick raycast in 3D.
- [ ] ion Self-Hosted / AOI DEM packaging investigation.
- [ ] Operator docs: 2D vs 3D, altitude labels, offline terrain packs.
- [ ] SITL smoke: 4 vehicles, 10 Hz, 15 min MC-R run in 3D mode.

When items ship, migrate **locked decisions** into `README_FULL.md` and remove completed bullets from the derived tracker per repo todo hygiene.

---

## Open questions (resolve before Phase 1 lock)

1. **Default on or opt-in?** Is 3D default for MC-R after spike, or 2D until operator enables?
2. **Geoid / MSL vs ellipsoid** — acceptable error budget for geofence visualization vs vehicle icon?
3. **Convoy preload width** — fixed meters vs max wingman offset from formation utilities?
4. **Freestyle Live Drive** — clamp UGV only when class known; unknown class behavior?
5. **Licensing** — ion SaaS in CI only vs production keys per customer?

---

## Glossary

| Term | Meaning in Guardian |
| --- | --- |
| **COP** | Common operational picture — shared 3D situational view |
| **Ghost mesh** | Untextured / minimal terrain surface for elevation only |
| **Structural map update** | Route, fence topology, task list identity — full rebuild |
| **Motion map update** | Lat/lon/heading/alt only — marker/entity patch |
| **Corridor** | Polyline path + perpendicular buffer for preload and formation |

---

*Last updated: 2026-05-16 — initial brief from product/architecture discussion (terrain clamp, military-style COP, squad preload, XRF reference).*
