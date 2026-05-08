# Paladin System Overview

Paladin is GuardianHQ's cross-system autonomy platform. It is integral to the app (not a plugin), but it is organized into explicit domains so each concern remains isolated and testable.

This document explains the current Paladin structure, boundaries, and how to extend it safely.

## Goals

- Keep mission orchestration logic separate from fleet-health intelligence.
- Let systems like Missions and LiveDrive remain usable independently, while still exposing hooks for Paladin.
- Centralize Paladin integration through one core entrypoint (`PaladinEngine`).
- Support growth into MC-E and future autonomy features without entangling UI and transport layers.

## Folder Structure

Paladin lives at:

- `Sources/GuardianHQ/Systems/Paladin/`

Current structure:

- `Core/` - shared entrypoint and cross-domain API surface.
- `DomainModels/` - normalized models used across Paladin domains.
- `Domains/` - bounded domain logic (MissionControl, Fleet, Missions, LiveDrive).
- `Policies/` - pure decision rules (planned expansion area).
- `Runtime/` - execution machinery (planned expansion area).
- `Integrations/` - adapters to external systems (Fleet bridge, logging, notifications).

## Core Entrypoint

`Core/PaladinEngine.swift` is the main facade used by other systems.

Responsibilities:

- Exposes domain handles (`mission`, `liveDrive`, `fleet`) via stable APIs.
- Bridges Mission Control into existing Paladin compile/runtime helpers.
- Prevents external systems from reaching deep into Paladin internals.

When adding new Paladin capabilities, prefer extending `PaladinEngine` first, then implementing in the target domain.

## Domain Boundaries

### PaladinMissionControlDomain

Mission run orchestration and execution planning.

Owns:

- session compile/runtime flow
- route/path execution intent
- mission-phase logging/events
- handover/takeover/tag-team strategy (MC domain concern)

Does not own:

- raw fleet telemetry transport
- low-level vehicle command transport
- calibration workflow internals

### PaladinFleetDomain

Vehicle readiness intelligence for autonomy decisions.

Owns:

- health/readiness normalization
- preflight status tracking
- calibration status tracking
- autonomy eligibility signal output for Paladin MC

Does not own:

- reserve/tag-team/handover mission strategy
- mission schedule logic

### PaladinMissionsDomain (stub)

Mission catalog/support snapshot hooks for future mission-level autonomy features.

### PaladinLiveDriveDomain (stub)

LiveDrive cooperation hooks (takeover-oriented integration surface).

## Fleet Integration Model

Paladin Fleet integration starts from the existing preflight subsystem and expands over time.

Implemented scaffold:

- `Integrations/Fleet/PaladinFleetPreflightBridge.swift`
  - Maps `SingleVehiclePreflightProbeResult` into normalized Paladin readiness models.
- `DomainModels/PaladinFleetReadinessModels.swift`
  - Defines health/preflight/calibration/eligibility model vocabulary.
- `Domains/Fleet/PaladinFleetDomain.swift`
  - Stores readiness by vehicle and provides summary accessors.

This enables Paladin MC to consume a consistent "is this vehicle autonomy-ready?" signal without embedding Fleet-specific probe logic.

## Logging + Notifications

- `Integrations/Logging/PaladinLogTemplates.swift` - template keys and registry for Paladin log localization/copy evolution.
- `Integrations/Notifications/PaladinNotificationPlugin.swift` - Paladin notification extension on app-level `UserNotificationService`.

## Current Status

Implemented:

- Core facade (`PaladinEngine`) and MissionControl wiring to it.
- Domain stubs for Missions and LiveDrive.
- Fleet readiness domain scaffold + preflight mapping bridge.
- Logging and notification integrations moved under Paladin integrations.

Planned next:

- Split MissionControl runtime/compiler internals into dedicated `Runtime/` + `Policies/` files.
- Wire Fleet readiness updates from real preflight probe callsites (MissionControl start-run and Vehicles preflight flows).
- Expand Fleet readiness with calibration process states and richer health signal ingestion.

## Extension Guidelines

- Keep domain boundaries strict:
  - Fleet domain reports readiness.
  - MissionControl domain decides mission behavior.
- Prefer adding normalized `DomainModels` instead of passing UI-specific structs across domains.
- Place external-system adapters in `Integrations/`, not inside core domains.
- Keep `Policies/` deterministic and side-effect free where possible.
- Route cross-domain access through `PaladinEngine` so callers depend on stable APIs.
