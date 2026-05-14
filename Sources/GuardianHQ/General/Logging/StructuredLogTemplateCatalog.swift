import Foundation
import os

/// Built-in English `{{param}}` patterns keyed by ``MissionRunEvent/templateKey``.
/// Future i18n: resolve localized patterns from the same stable id + ``MissionRunEvent/templateParams``.
struct StructuredLogTemplateEntry: Sendable {
    /// Neutral wording for export / reports / pasteboard.
    let defaultPattern: String
    /// Mission Control room live log; when `nil`, ``defaultPattern`` is used for MCR as well.
    let mcrPattern: String?

    init(defaultPattern: String, mcrPattern: String? = nil) {
        self.defaultPattern = defaultPattern
        self.mcrPattern = mcrPattern
    }
}

/// Which built-in pattern variant to read from ``StructuredLogTemplateCatalog``.
enum GuardianStructuredLogLinePresentation: Sendable {
    /// Mission Control room live log (catalog MCR line, then catalog default; user overrides in ``MissionRunLogTemplateRegistry`` apply only here).
    case missionControlRoom
    /// Plain export: catalog defaults only (ignores per-user MCR overrides in the registry).
    case plainExport
}

/// App-wide registry of stable log template ids → default + optional MCR copy.
///
/// Two layers of entries:
/// - **Core entries** — registered inline below (fleet, telemetry, lifecycle, etc.). Owned by the
///   `GuardianHQ` core; one source of truth for app-wide wording.
/// - **Plugin entries** — registered at runtime via ``registerTemplate(pluginID:forKey:defaultPattern:mcr:)``
///   or ``registerTemplates(pluginID:_:)`` with a validated ``GuardianPluginID``. Plugin entries take
///   precedence over core entries with the same key (last-write-wins), so plugins can override
///   core wording when needed.
///
/// Storage is protected by an `OSAllocatedUnfairLock` so registration / lookup are safe from any
/// actor / thread (matters because ``MissionRunEvent/init`` materializes ``message`` on whatever
/// thread the emit site happens to run on).
///
/// Plugins should register early — typically from their assistant / domain ``init`` so the
/// templates are available before any of their emissions fire.
enum StructuredLogTemplateCatalog: Sendable {
    private static let pluginEntries = OSAllocatedUnfairLock<[String: StructuredLogTemplateEntry]>(initialState: [:])
    /// Log template keys registered by ``registerTemplate(pluginID:forKey:defaultPattern:mcr:)`` → owning plugin raw id.
    private static let templateOwnership = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    private static let entries: [String: StructuredLogTemplateEntry] = {
        var e: [String: StructuredLogTemplateEntry] = [:]
        func put(_ key: String, _ def: String, mcr: String? = nil) {
            e[key] = StructuredLogTemplateEntry(defaultPattern: def, mcrPattern: mcr)
        }

        // Fleet mirror (FleetLink → MRE ingest, see ``FleetMirrorLineClassifier``)
        put(
            FleetMirrorLogTemplateKey.fleetMirrorMissionProgress,
            "Autopilot mission progress: item {{current}} of {{total}}.",
            mcr: "Autopilot progress · {{current}}/{{total}}"
        )
        put(
            FleetMirrorLogTemplateKey.fleetMirrorMissionRunComplete,
            "Autopilot mission run complete (progress {{current}}/{{total}}; notifying schedule).",
            mcr: "Cycle complete · {{current}}/{{total}} · schedule notify"
        )
        put(
            FleetMirrorLogTemplateKey.fleetMirrorVehicleStatus,
            "Vehicle message [{{label}}]: {{text}}",
            mcr: "[{{label}}] {{text}}"
        )
        put(
            FleetMirrorLogTemplateKey.fleetMirrorUnclassified,
            "{{text}}",
            mcr: "{{text}}"
        )

        // Fleet commands
        put(
            MissionRunLogTemplateKey.commandInvalidToken,
            "Invalid vehicle token for @{{slotID}}; command dropped.",
            mcr: "Token invalid · @{{slotID}} · dropped"
        )
        put(
            MissionRunLogTemplateKey.commandVehicleUnavailable,
            "Vehicle unavailable for @{{slotID}}; command dropped.",
            mcr: "No vehicle · @{{slotID}} · dropped"
        )
        put(
            MissionRunLogTemplateKey.commandDispatched,
            "Command dispatched to {{vehicleID}}.",
            mcr: "Dispatch → {{vehicleID}} (@{{slotID}})"
        )
        put(
            MissionRunLogTemplateKey.commandNotSent,
            "Command not sent to {{vehicleID}} (no session, blocked by authority gate, or dispatch error).",
            mcr: "Not sent → {{vehicleID}} · @{{slotID}}"
        )
        put(
            MissionRunLogTemplateKey.fleetAckSuccess,
            "Fleet acknowledged: {{summary}} on {{vehicleID}}{{recipeRunSuffix}}.",
            mcr: "ACK OK · {{summary}} · {{vehicleID}}{{recipeRunSuffix}}"
        )
        put(
            MissionRunLogTemplateKey.fleetAckFailed,
            "Fleet command failed: {{summary}} - {{reason}}{{recipeRunSuffix}}",
            mcr: "ACK fail · {{summary}} — {{reason}}{{recipeRunSuffix}}"
        )
        put(
            MissionRunLogTemplateKey.recipeFleetOutcomeTraceMismatch,
            "Recipe outcome ignored for slot updates: trace does not match issued dispatch (run {{runID}}, trace recipe {{traceRecipe}}, issued {{issuedRecipe}}, trace vehicle {{traceVehicleID}}, resolved {{resolvedVehicleID}}).",
            mcr: "Recipe trace mismatch · run {{runID}} · slot evidence skipped"
        )
        put(
            MissionRunLogTemplateKey.missionRunGeofenceFleetAckFailed,
            "Geofence fleet step failed: {{summary}} — {{reason}} (vehicle {{vehicleID}}){{recipeRunSuffix}}.",
            mcr: "Geofence ACK fail · {{summary}} — {{reason}} · {{vehicleID}}{{recipeRunSuffix}}"
        )
        put(
            MissionRunLogTemplateKey.executorPendingBatchesCancelledForLiveDriveEngage,
            "Cleared {{removedCount}} pending executor batch(es) before Live Drive for @{{slotID}}.",
            mcr: "Live Drive prep · cleared {{removedCount}} queued batch(es) · @{{slotID}}"
        )
        put(
            MissionRunLogTemplateKey.executorPendingBatchesCancelledForRunCompleted,
            "Cleared {{removedCount}} pending executor batch(es) after mission run completed.",
            mcr: "Run complete · cleared {{removedCount}} queued batch(es)"
        )
        put(
            MissionRunLogTemplateKey.guardianSitlMotionStopPassAfterRunCompleted,
            "Guardian SITL motion damp after run completed ({{vehicleCount}} vehicle(s)): manual stream stop, mission pause, offboard stop (best effort).",
            mcr: "Run complete · motion damp · {{vehicleCount}} SITL(s)"
        )
        put(
            MissionRunLogTemplateKey.guardianSitlKillPassAfterRunCompleted,
            "Guardian SITL SIM cleanup kill after run completed ({{vehicleCount}} vehicle(s)): manual stream stop, Action.kill force disarm (best effort).",
            mcr: "Run complete · SIM kill · {{vehicleCount}} SITL(s)"
        )
        put(
            MissionRunLogTemplateKey.executorMissionStartBatchSuppressedRunCompleted,
            "Ignored mission-start executor batch (dispatch {{dispatch}}) — mission run already completed.",
            mcr: "Run complete · mission start batch ignored · {{dispatch}}"
        )

        // Telemetry narrative
        put(
            MissionRunLogTemplateKey.telemetryAutopilotSnapshot,
            "Autopilot: mode {{mode}}, {{armState}}, rel alt {{relAlt}}.",
            mcr: "AP · {{mode}} · {{armState}} · {{relAlt}}"
        )
        put(
            MissionRunLogTemplateKey.telemetryFlightModeChange,
            "Flight mode: {{from}} -> {{to}}.",
            mcr: "Mode {{from}} → {{to}}"
        )
        put(MissionRunLogTemplateKey.telemetryArmed, "Armed.", mcr: "Armed")
        put(MissionRunLogTemplateKey.telemetryDisarmed, "Disarmed.", mcr: "Disarmed")
        put(MissionRunLogTemplateKey.telemetryAirborne, "Airborne.", mcr: "Airborne")
        put(
            MissionRunLogTemplateKey.telemetryOnGround,
            "On ground (in-air flag cleared).",
            mcr: "On ground"
        )
        put(
            MissionRunLogTemplateKey.telemetryAltTrend,
            "{{trend}} - rel alt ~{{alt}} m (delta {{delta}} m).",
            mcr: "{{trend}} · AGL ~{{alt}} m (Δ{{delta}})"
        )
        put(
            MissionRunLogTemplateKey.telemetryTrack,
            "Track - {{lat}} deg, {{lon}} deg · rel alt {{relAlt}} · {{mode}}.",
            mcr: "Track {{lat}}, {{lon}} · {{relAlt}} · {{mode}}"
        )
        put(
            MissionRunLogTemplateKey.telemetryApproachWP1,
            "Approaching first waypoint - ~{{distance}} m out, mode {{mode}}.",
            mcr: "Near WP1 · ~{{distance}} m · {{mode}}"
        )
        put(
            MissionRunLogTemplateKey.telemetryTurningLeg,
            "Turning toward leg - heading ~{{heading}} deg, bearing to WP1 ~{{bearing}} deg (~{{distance}} m).",
            mcr: "Turning · hdg {{heading}}° · brg {{bearing}}° · {{distance}} m"
        )
        put(
            MissionRunLogTemplateKey.telemetryMovingWP1,
            "Moving toward WP1 - ~{{distance}} m, aligned within ~{{turn}} deg.",
            mcr: "Inbound WP1 · ~{{distance}} m · within {{turn}}°"
        )

        put(
            MissionRunLogTemplateKey.compileSummary,
            "Compiled {{tracks}} role track(s), {{taskTopology}}, {{teamTopology}}.",
            mcr: "Plan compiled · {{tracks}} tracks · {{taskTopology}} / {{teamTopology}}"
        )

        put(
            MissionRunLogTemplateKey.taskForceStateChanged,
            "Task force changed to {{toDisplay}} state.",
            mcr: "Task force · @{{taskID}} · {{fromDisplay}} → {{toDisplay}}"
        )

        put(
            MissionRunLogTemplateKey.operatorMarkedMissionTaskTriageState,
            "Operator marked @{{taskID}} as {{stateDisplay}}.",
            mcr: "Op · @{{taskID}} · {{stateDisplay}}"
        )

        put(
            MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch,
            "All roster slots report policy complete; automatic protocol confirmation — abort tasks: {{abortTasks}}; complete tasks: {{recoveryTasks}}.",
            mcr: "Slot ack · auto · abort: {{abortTasks}} · complete: {{recoveryTasks}}"
        )

        put(MissionRunLogTemplateKey.executionStarted, "Mission execution started.", mcr: "Execution started (MC)")
        put(
            MissionRunLogTemplateKey.rosterBehaviorRolesSnapshot,
            "Roster behavior roles — {{summary}}.",
            mcr: "Roster roles · {{summary}}"
        )
        put(
            MissionRunLogTemplateKey.missionPointRuntimeSeeded,
            "Mission points runtime envelope seeded ({{count}} row(s); {{reason}}).",
            mcr: "Points runtime · {{count}} · {{reason}}"
        )
        put(
            MissionRunLogTemplateKey.missionPointRuntimeCreated,
            "Mission point created at runtime — {{kind}} `{{pointId}}` @ {{lat}},{{lon}} (source {{source}}).",
            mcr: "Point + · {{kind}} · {{pointId}} · {{source}}"
        )
        put(
            MissionRunLogTemplateKey.missionPointRuntimeUpdated,
            "Mission point updated at runtime — `{{pointId}}` (source {{source}}).",
            mcr: "Point ~ · {{pointId}} · {{source}}"
        )
        put(
            MissionRunLogTemplateKey.missionPointRuntimeClosedChanged,
            "Mission point closed state — `{{pointId}}` closed={{closed}} (source {{source}}).",
            mcr: "Point closed · {{pointId}} · {{closed}} · {{source}}"
        )
        put(
            MissionRunLogTemplateKey.floatingReserveSwapEngaged,
            "Floating reserve swap — roster @{{slotID}} ({{slot}}) took pool berth {{poolSlotID}} (source {{source}}).",
            mcr: "Reserve in · @{{slotID}} · pool {{poolSlotID}} · {{source}}"
        )
        put(
            MissionRunLogTemplateKey.fixedRosterReserveSwapEngaged,
            "Fixed reserve roster swap — vacancy @{{vacancySlotID}} ({{vacancySlot}}) ↔ reserve @{{reserveSlotID}} ({{reserveSlot}}) (source {{source}}).",
            mcr: "Reserve swap · roster · {{vacancySlot}} ↔ {{reserveSlot}} · {{source}}"
        )
        for phase in MissionRunReserveSwapPipelinePhase.allCases {
            let passKey = MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: phase, passed: true)
            let failKey = MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: phase, passed: false)
            put(
                passKey,
                "Reserve swap phase {{phase}} passed — task {{missionTaskID}} · vehicle {{vehicleID}} · {{detail}}.",
                mcr: "Swap {{phase}} · pass · {{vehicleID}} · {{detail}}"
            )
            put(
                failKey,
                "Reserve swap phase {{phase}} failed — task {{missionTaskID}} · vehicle {{vehicleID}} · {{detail}}.",
                mcr: "Swap {{phase}} · fail · {{vehicleID}} · {{detail}}"
            )
        }
        put(
            MissionRunLogTemplateKey.executionMissionMissing,
            "Mission template missing from store; cannot upload MAVLink mission.",
            mcr: "No mission template in store · cannot upload MAVLink"
        )

        put(
            MissionRunLogTemplateKey.runStoppedImmediate,
            "Run aborted immediately; fleet commands issued per abort plan.",
            mcr: "Abort now · fleet per abort plan"
        )
        put(
            MissionRunLogTemplateKey.runGracefulAfterCycle,
            "Current mission cycle finished; graceful abort — fleet actions from abort policy were queued for end of cycle.",
            mcr: "Cycle end · graceful abort queued"
        )
        put(
            MissionRunLogTemplateKey.runOneOffFinished,
            "Mission cycle finished; run complete - returning to launch / home.",
            mcr: "Cycle done · RTL / home"
        )
        put(
            MissionRunLogTemplateKey.scheduleSkipNoMission,
            "Deferred path mission start skipped - mission template not found in store.",
            mcr: "Deferred start skipped · no mission in store"
        )
        put(
            MissionRunLogTemplateKey.scheduleTaskMissionStartDeferred,
            "MAVLink mission start for this path deferred ({{duration}}).",
            mcr: "MAVLink start hold · {{duration}}"
        )

        put(
            MissionRunLogTemplateKey.stagingPassStarted,
            "Mission Control staging pass started.",
            mcr: "Staging pass · start"
        )
        put(
            MissionRunLogTemplateKey.stagingPassComplete,
            "Mission Control staging pass complete ({{slotCount}} slot(s) evaluated).",
            mcr: "Staging pass · done · {{slotCount}} slot(s)"
        )
        put(
            MissionRunLogTemplateKey.stagingNoToken,
            "No fleet vehicle token; skipping staging.",
            mcr: "No fleet token · skip staging"
        )
        put(
            MissionRunLogTemplateKey.stagingSimPoseFromSetup,
            "SITL slot {{slot}}: spawn pose is set on the Mission Control setup map (SIM_OPOS / SIH_LOC), not from this staging pass.",
            mcr: "SIM @{{slot}} · pose from setup map"
        )
        put(
            MissionRunLogTemplateKey.stagingLiveReadonly,
            "Live vehicle staging is telemetry-driven (read-only).",
            mcr: "Live staging · telemetry only"
        )
        put(
            MissionRunLogTemplateKey.mcsReservePoolHomeMapBatch,
            "Reserve pool map home (@{{taskID}}): placement requested for {{sent}} SIM(s) at {{latDeg}}°, {{lonDeg}}° (hub positions catch up asynchronously).{{modeNote}}",
            mcr: "Pool home map · @{{taskID}} · {{sent}} SIM(s) · {{latDeg}},{{lonDeg}}{{modeNote}}"
        )

        put(
            MissionRunLogTemplateKey.missionNotStartedNeedsPath,
            "MAVLink mission not started (need enabled path with assigned primary vehicle(s) and waypoints).",
            mcr: "MAVLink not started · need path + primaries + wpts"
        )
        put(
            MissionRunLogTemplateKey.missionNotStartedNoPrimaries,
            "MAVLink mission not started (task has no assigned primaries).",
            mcr: "MAVLink not started · no primaries"
        )
        put(
            MissionRunLogTemplateKey.missionPlanItemsEncodeFailed,
            "Could not encode MAVLink mission items for @{{slotID}} ({{reason}}).",
            mcr: "Plan encode failed · @{{slotID}} · {{reason}}"
        )
        put(
            MissionRunLogTemplateKey.missionGeofencePolygonsEncodeFailed,
            "Could not encode geofence polygons for MAVLink upload @{{slotID}} ({{reason}}).",
            mcr: "Geofence encode failed · @{{slotID}} · {{reason}}"
        )
        put(
            MissionRunLogTemplateKey.missionGeofencePx4InclusionFencesOmitted,
            "Omitted {{count}} inclusion geofence(s) for PX4 MAVLink upload @{{slotID}} — mission home must lie inside each inclusion fence; those fences were not sent to the vehicle.",
            mcr: "Geofence upload · omitted {{count}} inclusion @{{slotID}} (home outside fence)"
        )
        put(
            MissionRunLogTemplateKey.mcrLiveGeofenceFleetPushSummary,
            "MC-R geofence push finished: {{succeeded}} of {{attempted}} roster slot(s) acknowledged the upload or clear recipe.",
            mcr: "Geofence push · {{succeeded}}/{{attempted}} slots acknowledged"
        )
        put(
            MissionRunLogTemplateKey.missionGeofenceFleetPushMissionPlanMissing,
            "MC-R geofence push @{{slotID}}: no compiled waypoint mission for this slot — using standalone geofence upload only (some autopilots reject fence uploads while the onboard mission plan is empty).",
            mcr: "Geofence push @{{slotID}} · no plan · standalone upload (risky)"
        )
        put(
            MissionRunLogTemplateKey.missionExecuting,
            "Executing MAVLink mission for @{{slotID}} ({{itemCount}} item(s), {{formation}}, {{timing}}).",
            mcr: "MAVLink live · @{{slotID}} · {{itemCount}} items · {{formation}} · {{timing}}"
        )

        put(
            MissionRunLogTemplateKey.startMissionTaskSkippedPhase,
            "MAVLink task start skipped (session phase {{phase}}).",
            mcr: "Task start skipped · phase {{phase}}"
        )
        put(
            MissionRunLogTemplateKey.startMissionTaskNoDispatchContext,
            "startMissionTask skipped — no dispatch context (fleet link / simulation services not attached on this run, or mission template missing).",
            mcr: "startMissionTask · no dispatch context (link/SITL/template)"
        )
        put(
            MissionRunLogTemplateKey.startMissionTaskNoExecutionContext,
            "Task start-now skipped — no execution context.",
            mcr: "Deferred start · no execution context"
        )
        put(
            MissionRunLogTemplateKey.startMissionTaskSkippedAlreadyExecuting,
            "startMissionTask skipped — this task is already executing a cycle.",
            mcr: "startMissionTask · skipping · already executing"
        )
        put(
            MissionRunLogTemplateKey.abortMissionTaskNoDispatchContext,
            "abortMissionTask skipped — no dispatch context.",
            mcr: "abortMissionTask · no dispatch context"
        )
        put(
            MissionRunLogTemplateKey.completeMissionTaskNoDispatchContext,
            "completeMissionTask skipped — no dispatch context.",
            mcr: "completeMissionTask · no dispatch context"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortNowSkippedNoSlots,
            "abortMissionTask skipped — no roster slots bound to this path.",
            mcr: "Task abort now · no slots"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteNowSkippedNoSlots,
            "completeMissionTask skipped — no roster slots bound to this path.",
            mcr: "Task complete now · no slots"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedNoSlots,
            "Per-path graceful abort not scheduled — no roster slots bound to this path.",
            mcr: "Graceful task abort · no slots"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedNoSlots,
            "Per-path graceful complete not scheduled — no roster slots bound to this path.",
            mcr: "Graceful task complete · no slots"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortSkippedNoCommands,
            "abortMissionTask skipped — abort policy resolves to no fleet commands for bound slots on this path.",
            mcr: "Task abort · no fleet commands"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortEndAttemptNoted,
            "Mission Control marked this path for abort mission-end protocol; issuing fleet commands next.",
            mcr: "Task abort · attempt noted"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteSkippedNoCommands,
            "completeMissionTask skipped — complete policy resolves to no fleet commands for bound slots on this path.",
            mcr: "Task complete · no fleet commands"
        )
        put(
            MissionRunLogTemplateKey.missionTaskRecoveryEndAttemptNoted,
            "Mission Control marked this path for recovery mission-end protocol; issuing fleet commands next.",
            mcr: "Task recovery · attempt noted"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortNowDispatched,
            "Path @{{taskID}} aborted immediately; fleet commands issued per abort policy for this path’s slots.",
            mcr: "Task abort now · @{{taskID}}"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteNowDispatched,
            "Path @{{taskID}} complete wind-down issued immediately per complete policy for this path’s slots.",
            mcr: "Task complete now · @{{taskID}}"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedNoCommands,
            "Graceful path abort at cycle end skipped — no fleet commands for this path’s slots.",
            mcr: "Task abort graceful · no commands"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedNoCommands,
            "Graceful path complete at cycle end skipped — no fleet commands for this path’s slots.",
            mcr: "Task complete graceful · no commands"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortGracefulDispatched,
            "Path @{{taskID}} graceful abort: fleet actions from abort policy dispatched at end of cycle.",
            mcr: "Task abort graceful · dispatched · @{{taskID}}"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteGracefulDispatched,
            "Path @{{taskID}} graceful complete: recovery wind-down dispatched at end of cycle.",
            mcr: "Task complete graceful · dispatched · @{{taskID}}"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortGracefulScheduled,
            "Per-path graceful abort scheduled for end of the current autopilot mission cycle.",
            mcr: "Task abort graceful · scheduled"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteGracefulScheduled,
            "Per-path graceful complete scheduled for end of the current autopilot mission cycle.",
            mcr: "Task complete graceful · scheduled"
        )
        put(
            MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedWholeRunStopActive,
            "Per-path graceful abort not scheduled — a whole-run end-of-cycle stop is already active.",
            mcr: "Graceful task abort · whole-run stop active"
        )
        put(
            MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedWholeRunStopActive,
            "Per-path graceful complete not scheduled — a whole-run end-of-cycle stop is already active.",
            mcr: "Graceful task complete · whole-run stop active"
        )

        put(
            MissionRunLogTemplateKey.scheduleAbortAfterCycleNotQueuedNoContext,
            "Abort-after-cycle plan built but not queued — no execution context yet (start or cycle activity first).",
            mcr: "Abort-after-cycle · not queued · no execution context"
        )
        put(
            MissionRunLogTemplateKey.scheduleCompleteAfterCycleNotQueuedNoContext,
            "Complete-after-cycle wind-down built but not queued — no execution context yet (start or cycle activity first).",
            mcr: "Complete-after-cycle · not queued · no execution context"
        )
        put(
            MissionRunLogTemplateKey.scheduleCompleteNowSkippedNoContext,
            "Complete now skipped — no execution context (fleet session not captured).",
            mcr: "Complete now · no execution context"
        )
        put(
            MissionRunLogTemplateKey.scheduleAbortNowSkippedNoContext,
            "Abort now skipped — no execution context (fleet session not captured).",
            mcr: "Abort now · no execution context"
        )

        put(
            MissionRunLogTemplateKey.lifecycleRunFailed,
            "{{detail}}",
            mcr: "{{detail}}"
        )
        put(
            MissionRunLogTemplateKey.lifecycleSimHomeRestoreBatch,
            "SIM start-pose restore after run complete ({{phase}}): applied {{applied}}, skipped {{skipped}}, {{candidates}} candidate(s).",
            mcr: "SIM home · {{phase}} · applied {{applied}} · skipped {{skipped}} · {{candidates}} cand"
        )
        put(
            MissionRunLogTemplateKey.lifecycleSimCleanupParkBatch,
            "Run-complete SIM park cleanup: attempted {{attempted}}, succeeded {{succeeded}}, failed {{failed}}.",
            mcr: "SIM park cleanup · ok {{succeeded}} / {{attempted}} · failed {{failed}}"
        )
        put(
            MissionRunLogTemplateKey.lifecycleSimCleanupKillBatch,
            "Run-complete SIM kill cleanup: attempted {{attempted}}, succeeded {{succeeded}}, failed {{failed}}.",
            mcr: "SIM kill cleanup · ok {{succeeded}} / {{attempted}} · failed {{failed}}"
        )
        put(
            MissionRunLogTemplateKey.lifecycleSimCleanupRunStarted,
            "Run-complete SIM cleanup starting: kill wave {{sitlKill}} SITL session(s), teleport {{teleport}}, mission/battery union {{union}}, completion {{completion}}.",
            mcr: "SIM cleanup · start · kill {{sitlKill}} · teleport {{teleport}} · union {{union}} · {{completion}}"
        )
        put(
            MissionRunLogTemplateKey.lifecycleSimCleanupRunFinished,
            "Run-complete SIM cleanup finished: kill attempted {{killAttempted}} (failed {{killFailed}}), mission clear {{missionClear}}, geofence clear {{geofenceClear}}, roster teleport applied {{rTeleApplied}} skipped {{rTeleSkipped}}, pool teleport applied {{pTeleApplied}} skipped {{pTeleSkipped}}, battery vehicles {{battery}}.",
            mcr: "SIM cleanup · done · kill {{killAttempted}} (fail {{killFailed}}) · clr {{missionClear}} · gf {{geofenceClear}} · r-tel {{rTeleApplied}}/{{rTeleSkipped}} · p-tel {{pTeleApplied}}/{{pTeleSkipped}} · bat {{battery}}"
        )

        put(
            MissionRunLogTemplateKey.runCompleteWindDownImmediate,
            "Run ended for recovery; fleet wind-down issued per complete policy on bound slots.",
            mcr: "Recovery · wind-down per complete policy"
        )
        put(
            MissionRunLogTemplateKey.runCompleteWindDownAfterCycle,
            "Current mission cycle finished; entering recovery — complete-policy wind-down was queued for end of cycle.",
            mcr: "Cycle end · recovery · wind-down queued"
        )

        put(
            MissionRunLogTemplateKey.planRevisionAppliedImmediate,
            "Applied plan revision {{revision}} immediately.",
            mcr: "Plan rev {{revision}} · applied now"
        )
        put(
            MissionRunLogTemplateKey.planRevisionQueuedSafePoint,
            "Queued plan revision {{revision}} for next safe point.",
            mcr: "Plan rev {{revision}} · queued @ safe point"
        )
        put(
            MissionRunLogTemplateKey.planRevisionQueuedNextCycle,
            "Queued plan revision {{revision}} for next mission cycle.",
            mcr: "Plan rev {{revision}} · queued @ next cycle"
        )
        put(
            MissionRunLogTemplateKey.missionRunningUnboundedRegularity,
            "Mission remains running (unbounded task regularity). Stop manually when ready.",
            mcr: "Unbounded regularity · mission still running"
        )
        put(
            MissionRunLogTemplateKey.betweenCyclesPrimaryFailedDispatchingFallback,
            "Between-cycles command failed ({{primary}}) for @{{slotID}} ({{slot}}); roster class {{vehicleClass}} — issuing fallback: {{fallback}}.",
            mcr: "Between cycles · {{primary}} failed · @{{slotID}} · {{vehicleClass}} · fallback {{fallback}}"
        )

        put(
            MissionRunLogTemplateKey.policyAuthorityEditApplied,
            "{{scope}} updated to {{value}}.",
            mcr: "{{scope}} → {{value}}"
        )
        put(
            MissionRunLogTemplateKey.policyAuthorityEditDenied,
            "{{scope}} edit denied — {{reason}}.",
            mcr: "{{scope}} · denied · {{reason}}"
        )

        return e
    }()

    /// Wording for `key` in the requested presentation. Plugin entries take precedence over core
    /// entries; falls back to `nil` when no entry is registered (treated as "missing template" by
    /// ``storedMessage(forKey:templateParams:)`` — asserts in DEBUG).
    static func pattern(forKey key: String, presentation: GuardianStructuredLogLinePresentation) -> String? {
        let entry = pluginEntries.withLock { $0[key] } ?? entries[key]
        guard let entry else { return nil }
        switch presentation {
        case .missionControlRoom:
            return entry.mcrPattern ?? entry.defaultPattern
        case .plainExport:
            return entry.defaultPattern
        }
    }

    /// Plugin registration: add (or override) a single template entry owned by ``pluginID``.
    /// Idempotent — last write wins. Safe to call from any actor / thread.
    static func registerTemplate(
        pluginID: GuardianPluginID,
        forKey key: String,
        defaultPattern: String,
        mcr: String? = nil
    ) {
        pluginEntries.withLock { entries in
            entries[key] = StructuredLogTemplateEntry(defaultPattern: defaultPattern, mcrPattern: mcr)
        }
        templateOwnership.withLock { ownership in
            ownership[key] = pluginID.rawValue
        }
    }

    /// Bulk plugin registration; every key is attributed to ``pluginID`` for later teardown.
    static func registerTemplates(
        pluginID: GuardianPluginID,
        _ contributions: [String: StructuredLogTemplateEntry]
    ) {
        guard !contributions.isEmpty else { return }
        pluginEntries.withLock { entries in
            for (k, v) in contributions {
                entries[k] = v
            }
        }
        templateOwnership.withLock { ownership in
            for k in contributions.keys {
                ownership[k] = pluginID.rawValue
            }
        }
    }

    /// Removes every plugin-registered template row owned by this plugin id.
    static func unregisterAllTemplates(forPlugin pluginID: GuardianPluginID) {
        let keys = templateOwnership.withLock { ownership -> [String] in
            let keys = ownership.filter { $0.value == pluginID.rawValue }.map(\.key)
            for k in keys {
                ownership.removeValue(forKey: k)
            }
            return keys
        }
        pluginEntries.withLock { entries in
            for k in keys {
                entries.removeValue(forKey: k)
            }
        }
    }

    /// Removes a previously-registered plugin entry (no-op for core entries / unknown keys).
    /// Mostly useful for tests.
    static func unregisterTemplate(forKey key: String) {
        _ = pluginEntries.withLock { entries in
            entries.removeValue(forKey: key)
        }
        _ = templateOwnership.withLock { ownership in
            ownership.removeValue(forKey: key)
        }
    }

    static func interpolate(_ pattern: String, params: [String: String]) -> String {
        var result = pattern
        for (k, v) in params {
            result = result.replacingOccurrences(of: "{{\(k)}}", with: v)
        }
        return result
    }

    /// Materializes ``MissionRunEvent/message`` from the catalog default (export) pattern. Every emitted `templateKey` must have an entry.
    static func storedMessage(forKey key: String, templateParams: [String: String] = [:]) -> String {
        guard let pattern = pattern(forKey: key, presentation: .plainExport) else {
            #if DEBUG
            assertionFailure("Missing StructuredLogTemplateCatalog entry for template key: \(key)")
            #endif
            return "[[missing log template: \(key)]]"
        }
        return interpolate(pattern, params: templateParams)
    }
}

extension MissionRunEvent {
    /// Creates an event whose ``message`` is resolved from ``StructuredLogTemplateCatalog`` (default pattern).
    /// Automatically injects `templateParams["taskID"]` from the event-level `taskID` so catalog
    /// templates can write `@{{taskID}}` and have it resolve to a colored, clickable task mention
    /// in MCR (and to the human task name in plain-text export) without each call site having to
    /// pass it manually.
    init(
        level: MissionRunEventLevel = .info,
        taskID: UUID? = nil,
        taskLabel: String? = nil,
        speaker: MissionRunEventSpeaker = .missionControl,
        target: MissionRunEventTarget? = nil,
        templateKey: String,
        templateParams: [String: String] = [:],
        id: UUID = UUID(),
        at: Date = Date()
    ) {
        var augmented = templateParams
        if let taskID, augmented["taskID"] == nil {
            augmented["taskID"] = taskID.uuidString
        }
        self.init(
            id: id,
            at: at,
            level: level,
            taskID: taskID,
            taskLabel: taskLabel,
            speaker: speaker,
            target: target,
            message: StructuredLogTemplateCatalog.storedMessage(forKey: templateKey, templateParams: augmented),
            templateKey: templateKey,
            templateParams: augmented
        )
    }
}
