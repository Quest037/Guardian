# Live Leaflet map performance & shared builder

Operator-facing maps that use **`GuardianMapView` → `GuardianMapModel` → `OSMMapView` (WKWebView + Leaflet)** should stay smooth at **tens of live vehicles** without burning the main thread on every MAVLink hub sample.

This file tracks **central transport/render** work plus a **shared live-map builder** that every feature plugs into so marker payloads stay cheap and consistent.

## Goals

- **Throttle / coalesce** rapid `vehicleMarkers` / `routeGeometry` publishes before they cross the Swift → JS bridge.
- **Diff** marker updates in JS (or Swift) so unchanged ids / unchanged icon payloads do not force full layer rebuilds.
- **Decouple** “position changed” from “icon / roster art changed”: no PNG→base64 work on every telemetry tick.
- **Avoid** rebuilding static overlays (geofences, full route polylines) on the same cadence as hub-driven marker motion unless topology changed.
- Provide a **single shared builder API** for “live roster / hub positions → `MapVehicleMarker`” so Mission Control, Live Drive, Missions, Settings (spawn map), and future surfaces do not fork parallel marker logic.

## Phase A — Central map stack (`GuardianMapModel` + `OSMMapView` + bridge)

- [ ] **Coalesce `@Published` updates**: batch `vehicleMarkers` + `routeGeometry` mutations that occur in the same runloop tick (or within ~16–100 ms window) into one bridge message where safe.
- [ ] **Identity / diff contract**: document and enforce stable `MapVehicleMarker.id` semantics for live updates; skip JS refresh when encoded payload is `Equatable`-equal to previous (already partially true for `GuardianRouteMapGeometry` — extend pattern to markers path).
- [ ] **Bridge profiling**: instrument or log payload sizes / call frequency in debug builds; confirm win after coalescing.
- [ ] **Optional `viewportNudge` / `recenterNonce` hygiene**: ensure high-frequency telemetry does not accidentally bump fit/recenter paths.

## Phase B — Shared live-map builder (new module under Global Utilities)

Add a small, testable surface (names TBD) under `Sources/GuardianHQ/Systems/Utilities/` and wire through `Utilities` / `GlobalUtilities`, e.g.:

- [ ] **`LiveLeafletMapMarkerBuildInputs`**: roster rows + `FleetLinkService` + `SitlService` + mission template slice + focus filters (task isolation, reserve pool rules) — pure data in, no SwiftUI.
- [ ] **`LiveLeafletMapMarkerCache`**: LRU or dictionary keyed by `(assignmentIdentity, imageBasenamesSignature)` → cached `imageDataURL` (or precomputed small PNG bytes) so **position-only** updates reuse the string without `NSImage` → TIFF → PNG → base64.
- [ ] **`buildMapVehicleMarkersLive(...)`** (or nested namespace): returns `[MapVehicleMarker]` + a **lightweight motion digest** string (lat/lon/heading only, coarser quantization than internal truth if needed) for `onChange` gating — **must not** call image encode to compute digest.
- [ ] **Unit tests** in `tests/GuardianHQTests/`: cache hit on second build with moved coordinates; digest stability; empty / unbound roster edges.

## Phase C — Migrate each `GuardianMapView` consumer to the builder

Current call sites (grep `GuardianMapView(`): `MissionControlSetupView`, `LiveDriveView`, `MissionsView`, `SettingsView`.

- [ ] **Mission Control — live overview** (`MissionControlSetupView`): replace `missionLiveVehicleMarkers` + `liveOverviewMapMarkerCoordinateDigest` coupling so digest uses **motion-only** signature; route `imageDataURL` through cache; stop rebuilding `geofenceOverlays` inside `pushLiveOverviewMapMarkersOnly()` unless fence topology / draft / selection changed.
- [ ] **Mission Control — MCS staging map**: same builder + cache for `setupStagingMapVehicleMarkers` / `setupStagingMapMarkerCoordinateDigest` if the same anti-pattern exists.
- [ ] **Live Drive**: adopt builder for roster overlay markers (`MissionControlLiveDriveMapOverlay` or successor) so LD and MC-R share one path.
- [ ] **Missions workspace map**: adopt builder for any live/hub-driven roster preview; keep mission-editor-only geometry on existing paths where no hub exists.
- [ ] **Settings (sim spawn map)**: adopt only if it ever shows live hub positions with roster art; otherwise skip or stub inputs.

## Phase D — Telemetry gating (feature-adjacent, may stay in features)

- [ ] **Hub `onChange`**: review `fleetLink.hubTelemetry?.lastUpdate` handlers so SIM drag / overlay reconcile does not invalidate entire MC chrome at hub rate unless necessary.
- [ ] **Optional UI-only Hz cap**: e.g. max 10 Hz map marker apply from hub, always take latest sample (document product tradeoff in README if operator-visible).

## Done / retire criteria

- [ ] With **4 SITL streams** moving, main-thread time from marker pipeline drops materially (Instruments / signpost or simple debug counters).
- [ ] **No** full icon re-encode on position-only digest changes (verified by cache metrics or breakpoint).
- [ ] All live **`GuardianMapView`** surfaces use the **shared builder** (or explicitly document why a surface is static-only and exempt).

## References (code anchors)

- `GuardianMapModel` / `GuardianRouteMapGeometry` — `Sources/GuardianHQ/General/Utilities/Templates/Map/GuardianMapView.swift`
- MC live map digest + `pushLiveOverviewMapMarkersOnly` — `MissionControlSetupView.swift` (`liveOverviewMapMarkerCoordinateDigest`, `missionLiveVehicleMarkers`, `missionControlRosterMapMarkerImageDataURL`)
- LD overlay markers — `MissionControlLiveDriveMapOverlay.swift` (`rosterMapMarkerImageDataURL` duplication to fold into shared cache)
