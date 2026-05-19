import Foundation
import SwiftUI

/// Formation lab (Simulate on): spawns SITLs (same as Vehicles), preflights, then streams formation spacing via OFFBOARD/GUIDED.
/// Simulators **persist** in ``SitlService`` / Vehicles when leaving this panel; only formation streams stop.
@MainActor
final class FormationsPlaygroundController: ObservableObject {
    @Published var simCount: Int = 3
    @Published var vehicleClass: FormationsPlaygroundVehicleClass = .ugvWheeled
    @Published var vehicleSizeTier: VehicleSizeTier = .medium
    @Published var formation: MissionSquadFormationKind = .arrowhead
    @Published var spacing: MissionSquadFormationSpacing = .tight
    @Published private(set) var phase: FormationsPlaygroundPhase = .idle
    @Published private(set) var isBusy = false
    @Published private(set) var statusText = "Spawn simulators to preview formation spacing."
    @Published private(set) var connectedSimCount = 0
    @Published private(set) var slots: [FormationsPlaygroundSlotState] = []
    @Published private(set) var logLines: [FormationsPlaygroundLogLine] = []
    @Published private(set) var telemetryTraceSampleCount = 0
    /// When on, gold centroid + circle rim handles move/rotate the slot group; anchor pose drives layout (not live primary telemetry).
    @Published var isSlotGroupMapEditEnabled = false

    private var telemetryRecorder = FormationsPlaygroundTelemetryTraceRecorder()
    private var tickTask: Task<Void, Never>?
    private var followProgressBySlotID: [UUID: (lastDistanceM: Double?, ticksWithoutProgress: Int)] = [:]
    private var lastLoggedMessageBySlotID: [UUID: String] = [:]
    private var lastLoggedMovementBySlotID: [UUID: String] = [:]
    private weak var fleetLink: FleetLinkService?
    private weak var sitl: SitlService?
    private var simulationPlatform: SimulationPlatform = .ardupilot
    private var spawnDefaults: SimSpawnDefaults = .default
    private var formationAnchorLat: Double = SimSpawnDefaults.default.latitudeDeg
    private var formationAnchorLon: Double = SimSpawnDefaults.default.longitudeDeg
    private var formationAnchorHeadingDeg: Double = SimSpawnDefaults.default.headingDeg
    private var formationAnchorAltM: Double = SimSpawnDefaults.default.altitudeM
    /// Gold clone layout while **Adjust slots on map** is on — committed to ``formationAnchor*`` on edit end.
    private var slotGroupPreviewLat: Double = SimSpawnDefaults.default.latitudeDeg
    private var slotGroupPreviewLon: Double = SimSpawnDefaults.default.longitudeDeg
    private var slotGroupPreviewHeadingDeg: Double = SimSpawnDefaults.default.headingDeg
    private var slotGroupPreviewAltM: Double = SimSpawnDefaults.default.altitudeM
    /// After map edit commit, tick streams the fixed layout (not live-primary chase) until the next reform.
    private var holdsMapCommittedFormationLayout = false

    private static let tickIntervalNs: UInt64 = 100_000_000
    private static let linkWaitTimeoutS: TimeInterval = 60
    private static let preflightSource = "formations.playground.preflight"
    private static let snapSource = "formations.playground.reform_snap"
    private static let maxLogLines = 250
    private static let slotGroupCircleMinRadiusM: Double = 6
    private static let slotGroupCirclePaddingM: Double = 2

    func attach(
        fleetLink: FleetLinkService,
        sitl: SitlService,
        spawnDefaults: SimSpawnDefaults,
        simulationPlatform: SimulationPlatform
    ) {
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.simulationPlatform = simulationPlatform
        self.spawnDefaults = spawnDefaults
        formationAnchorLat = spawnDefaults.latitudeDeg
        formationAnchorLon = spawnDefaults.longitudeDeg
        formationAnchorHeadingDeg = spawnDefaults.headingDeg
        formationAnchorAltM = spawnDefaults.altitudeM
    }

    /// Ends formation follow / control streams without despawning simulators (Training **Stop**).
    func stopActiveFormationSession() async {
        tickTask?.cancel()
        tickTask = nil
        if phase == .following {
            telemetryRecorder.endSession()
            telemetryTraceSampleCount = telemetryRecorder.samples.count
        }
        phase = .idle
        await stopAllStreams()
        if slots.isEmpty {
            statusText = "Spawn simulators to fill the roster."
        } else if slots.allSatisfy(\.linkReady) {
            statusText = "\(slots.count) simulator(s) ready."
        } else {
            statusText = "Waiting for simulators to link…"
        }
    }

    /// Leaving the Formations tab: stop streamed formation control only (SITLs stay in Vehicles).
    func leavePanel() {
        tickTask?.cancel()
        tickTask = nil
        if phase == .following {
            phase = .idle
        }
        Task { await stopAllStreams() }
        if slots.isEmpty {
            statusText = "Spawn simulators to preview formation spacing."
        } else {
            statusText =
                "\(slots.count) simulator(s) remain in Vehicles. Preflight or apply formation when you return."
        }
    }

    /// Stops every playground-tracked SITL (same as stopping cards in Vehicles).
    func stopPlaygroundSquad() {
        tickTask?.cancel()
        tickTask = nil
        if phase == .following {
            telemetryRecorder.endSession()
            telemetryTraceSampleCount = telemetryRecorder.samples.count
        }
        phase = .idle
        let slotsToStop = slots
        slots = []
        connectedSimCount = 0
        statusText = "Stopping simulators…"
        Task { @MainActor in
            await stopAllStreams()
            guard let sitl else {
                clearFormationLogs()
                statusText = "Spawn simulators to preview formation spacing."
                return
            }
            for slot in slotsToStop {
                sitl.stop(id: slot.sitlSessionID)
            }
            if let fleetLink, !sitl.instances.contains(where: \.isAlive) {
                fleetLink.clearStaleVehicleStateWhenNoSitlAlive()
            }
            clearFormationLogs()
            statusText = "Spawn simulators to preview formation spacing."
        }
    }

    /// Reconcile slot rows with running SITLs after returning to the panel.
    func syncFromFleetOnAppear(fleetLink: FleetLinkService) {
        syncSlotsFromRunningSitl(fleetLink: fleetLink)
        refreshConnectedSimCount(fleetLink: fleetLink)
        if slots.isEmpty {
            statusText = "Spawn simulators to preview formation spacing."
        } else if phase != .following {
            let live = slots.filter(\.linkReady).count
            statusText =
                "\(live) of \(slots.count) linked in Vehicles. Preflight each slot, then apply formation."
        }
    }

    var orderedVehicleIDs: [String] {
        slots.compactMap(\.vehicleID)
    }

    var preflightReadyVehicleIDs: [String] {
        slots.compactMap { slot in
            guard slot.preflightPassed == true, let vid = slot.vehicleID else { return nil }
            return vid
        }
    }

    func spawnPlaygroundSims(missionControl: MissionControlStore) async {
        guard let fleetLink, let sitl else { return }
        guard fleetLink.isSimulateEnabled else {
            statusText = "Turn on Simulate in the top bar before spawning."
            return
        }

        let count = min(10, max(1, simCount))
        simCount = count
        phase = .spawning
        await stopAllStreams()
        stopPlaygroundSquadTrackedInstancesOnly(sitl: sitl)
        await sitl.waitForRecentlyReleasedPortsToSettle()
        clearFormationLogs()
        slots = []

        isBusy = true
        for index in 0..<count {
            statusText = "Spawning simulator \(index + 1) of \(count)…"
            let before = Set(sitl.instances.map(\.id))
            let defaults = staggeredSpawnDefaults(slotIndex: index)
            sitl.spawn(
                preset: vehicleClass.simulationPreset,
                platform: simulationPlatform,
                defaults: defaults,
                owner: .trainingRoster
            )
            let added = sitl.instances.filter {
                !before.contains($0.id) && $0.spawnOwner == .trainingRoster
            }
            for row in added {
                slots.append(
                    FormationsPlaygroundSlotState(
                        sitlSessionID: row.id,
                        vehicleID: vehicleID(forStackInstance: row.stackInstanceIndex, fleetLink: fleetLink),
                        linkReady: false,
                        preflightPassed: nil,
                        preflightDetail: nil
                    )
                )
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        isBusy = false

        phase = .connecting
        statusText = "Waiting for fleet link (\(count) simulators in Vehicles)…"
        guard await waitForAllSlotsFleetReady(fleetLink: fleetLink) else {
            statusText =
                "Timed out waiting for simulators to reach live telemetry. Check Vehicles or SITL logs, then retry preflight."
            refreshSlotRows(fleetLink: fleetLink)
            phase = .idle
            return
        }
        refreshConnectedSimCount(fleetLink: fleetLink)
        try? await Task.sleep(nanoseconds: 750_000_000)

        phase = .preflight
        statusText = "Running preflight on \(count) simulators…"
        let allPassed = await runPreflightOnSlots(
            missionControl: missionControl,
            fleetLink: fleetLink,
            sitl: sitl
        )
        refreshSlotRows(fleetLink: fleetLink)

        let readyIDs = preflightReadyVehicleIDs
        guard !readyIDs.isEmpty else {
            statusText =
                "Preflight failed for every simulator. Use Retry on each row, open Vehicles to inspect, or respawn the squad."
            phase = .idle
            return
        }
        guard slots.first?.preflightPassed == true, slots.first?.vehicleID != nil else {
            statusText = "Primary simulator failed preflight. Retry primary or respawn the squad."
            phase = .idle
            return
        }
        if !allPassed {
            statusText =
                "Preflight: \(readyIDs.count) of \(count) passed — apply formation to move ready simulators, or retry failed rows."
            phase = .idle
            return
        }

        await applyFormationControl(fleetLink: fleetLink)
    }

    /// Starts one Training lab SITL and returns immediately; link + preflight finish in the background.
    @discardableResult
    func spawnTrainingLabSimulator(
        preset: SimulationVehiclePreset,
        platform: SimulationPlatform,
        sizeTier: VehicleSizeTier,
        gazeboPlacement: GazeboVehiclePlacement?,
        missionControl: MissionControlStore
    ) async -> FormationsPlaygroundSlotState? {
        guard let fleetLink, let sitl else { return nil }
        guard fleetLink.isSimulateEnabled else {
            statusText = "Turn on Simulate in the top bar before spawning."
            return nil
        }

        let index = slots.count
        let before = Set(sitl.instances.map(\.id))
        let defaults = staggeredSpawnDefaults(slotIndex: index)
        sitl.spawn(
            preset: preset,
            platform: platform,
            defaults: defaults,
            owner: .trainingRoster,
            gazeboPlacement: gazeboPlacement
        )
        guard let row = sitl.instances.first(where: {
            !before.contains($0.id) && $0.spawnOwner == .trainingRoster
        }) else {
            statusText = sitl.lastError ?? "Spawn failed — check SITL logs."
            return nil
        }

        let slot = FormationsPlaygroundSlotState(
            sitlSessionID: row.id,
            vehicleID: vehicleID(forStackInstance: row.stackInstanceIndex, fleetLink: fleetLink),
            linkReady: false,
            preflightPassed: nil,
            preflightDetail: nil
        )
        slots.append(slot)

        if let vid = slot.vehicleID {
            fleetLink.setVehicleSizeTier(sizeTier, forVehicleID: vid)
        }

        if slots.count == 1 {
            statusText = "Connecting simulator…"
        } else {
            statusText = "\(slots.count) simulators — connecting latest…"
        }

        let slotID = slot.id
        let sitlSessionID = row.id
        Task { @MainActor [weak self] in
            await self?.completeTrainingLabSimulatorStartup(
                slotID: slotID,
                sitlSessionID: sitlSessionID,
                missionControl: missionControl
            )
        }
        return slot
    }

    /// Link wait, fleet bind, and preflight for a Training lab row (does not block the add-vehicle UI).
    private func completeTrainingLabSimulatorStartup(
        slotID: UUID,
        sitlSessionID: UUID,
        missionControl: MissionControlStore
    ) async {
        guard let fleetLink, let sitl else { return }

        _ = await waitForSlotFleetReady(slotID: slotID, fleetLink: fleetLink)
        refreshSlotRows(fleetLink: fleetLink)

        if let inst = sitl.instances.first(where: { $0.id == sitlSessionID && $0.isAlive }) {
            _ = await bindFleetLinkToFormationSimulator(inst: inst, fleetLink: fleetLink, sitl: sitl)
        }

        refreshSlotRows(fleetLink: fleetLink)
        guard let vehicleID = slots.first(where: { $0.id == slotID })?.vehicleID else { return }

        let probe = await missionControl.runSingleVehiclePreflightProbe(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            leaveArmed: true,
            allowDuringLiveMission: true,
            preflightAuditSource: Self.preflightSource
        )
        if let idx = slots.firstIndex(where: { $0.id == slotID }) {
            slots[idx].preflightPassed = probe.passed
            slots[idx].preflightDetail = probe.detail
            slots[idx].linkReady = true
        }
        refreshSlotRows(fleetLink: fleetLink)
        statusText = liveStatusLabel()
    }

    /// Replaces in-memory slot list when the Training lab roster edits squads (no SITL stop).
    func replaceSlotsForTrainingLab(_ next: [FormationsPlaygroundSlotState]) {
        slots = next
        connectedSimCount = next.filter(\.linkReady).count
        if next.isEmpty {
            statusText = "Add vehicles to your training session."
        } else {
            statusText = "\(next.count) simulator(s) in roster."
        }
    }

    /// Stops one roster row's SITL and removes it from the playground slot list.
    func removeSlot(id: UUID) async {
        guard let sitl, let fleetLink, let index = slots.firstIndex(where: { $0.id == id }) else { return }
        let slot = slots[index]
        if let vehicleID = slot.vehicleID {
            await fleetLink.stopFormationFollowStream(vehicleID: vehicleID)
        }
        sitl.stop(id: slot.sitlSessionID)
        slots.remove(at: index)
        refreshConnectedSimCount(fleetLink: fleetLink)
    }

    func applyFormationControl() async {
        guard let fleetLink else { return }
        await applyFormationControl(fleetLink: fleetLink)
    }

    func formationSettingsDidChange(fleetLink: FleetLinkService) {
        if !slots.isEmpty, !isSlotGroupMapEditEnabled {
            captureFormationAnchor(fleetLink: fleetLink)
        }
        guard phase == .following, !isSlotGroupMapEditEnabled else { return }
        Task { await refreshFormationStreams() }
    }

    func retrySimulatorConnection(
        slotID: UUID,
        missionControl: MissionControlStore
    ) async {
        guard let fleetLink, let sitl,
              let index = slots.firstIndex(where: { $0.id == slotID })
        else { return }

        var slot = slots[index]
        guard let vehicleID = slot.vehicleID else { return }

        phase = .connecting
        statusText = slot.linkReady ? "Retrying preflight…" : "Reconnecting telemetry…"
        await fleetLink.stopFormationFollowStream(vehicleID: vehicleID)

        if !slot.linkReady,
           let inst = sitl.instances.first(where: { $0.id == slot.sitlSessionID && $0.isAlive }) {
            let reconnected = await bindFleetLinkToFormationSimulator(
                inst: inst,
                fleetLink: fleetLink,
                sitl: sitl
            )
            if !reconnected {
                slots[index].preflightPassed = false
                slots[index].preflightDetail = sitl.lastError ?? "Reconnect failed."
                slots[index].linkReady = false
                statusText = slots[index].preflightDetail ?? "Reconnect failed."
                phase = .idle
                return
            }
        }

        refreshSlotRows(fleetLink: fleetLink)
        guard let refreshedIndex = slots.firstIndex(where: { $0.id == slotID }) else {
            phase = .idle
            return
        }
        slot = slots[refreshedIndex]

        if !slotFleetReady(fleetLink: fleetLink, vehicleID: vehicleID) {
            statusText = "Waiting for live telemetry…"
            guard await waitForSlotFleetReady(slotID: slotID, fleetLink: fleetLink) else {
                slots[refreshedIndex].preflightPassed = false
                slots[refreshedIndex].preflightDetail = MissionControlStore.preflightProbeNotConnectedDetail
                slots[refreshedIndex].linkReady = false
                statusText = "Timed out waiting for telemetry. Try Replace or check SITL logs."
                phase = .idle
                return
            }
            slots[refreshedIndex].linkReady = true
        }

        phase = .preflight
        statusText = "Retrying preflight…"
        let probe = await missionControl.runSingleVehiclePreflightProbe(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            leaveArmed: true,
            allowDuringLiveMission: true,
            preflightAuditSource: Self.preflightSource
        )
        slots[refreshedIndex].preflightPassed = probe.passed
        slots[refreshedIndex].preflightDetail = probe.detail
        slots[refreshedIndex].linkReady = true
        phase = .idle
        statusText = probe.passed
            ? liveStatusLabel()
            : "Preflight failed: \(probe.detail)"
    }

    /// True when this row may be replaced (no live link, preflight pending, or preflight failed).
    func canReplaceSlot(_ slot: FormationsPlaygroundSlotState) -> Bool {
        !slot.linkReady || slot.preflightPassed != true
    }

    func shouldOfferSimulatorRetry(slot: FormationsPlaygroundSlotState) -> Bool {
        GuardianSimulatorSlotRecoveryPolicy.shouldOfferRetry(slot: slot)
    }

    func retryButtonTitle(for slot: FormationsPlaygroundSlotState) -> String {
        GuardianSimulatorSlotRecoveryPolicy.formationRetryButtonTitle(
            linkReady: slot.linkReady,
            isConnecting: phase == .connecting || phase == .preflight
        )
    }

    var cardActionsLocked: Bool { isBusy }

    @discardableResult
    func replaceSlot(
        slotID: UUID,
        missionControl: MissionControlStore,
        preset: SimulationVehiclePreset? = nil,
        platform: SimulationPlatform? = nil,
        sizeTier: VehicleSizeTier? = nil,
        gazeboPlacement: GazeboVehiclePlacement? = nil
    ) async -> FormationsPlaygroundSlotState? {
        guard let fleetLink, let sitl,
              let index = slots.firstIndex(where: { $0.id == slotID })
        else { return nil }
        guard fleetLink.isSimulateEnabled else {
            statusText = "Turn on Simulate in the top bar before replacing."
            return nil
        }
        let old = slots[index]
        if let vid = old.vehicleID {
            await fleetLink.stopFormationFollowStream(vehicleID: vid)
            await fleetLink.stopTrainingControlStream(vehicleID: vid)
        }
        if let oldInst = sitl.instances.first(where: { $0.id == old.sitlSessionID }) {
            fleetLink.unregisterSimulatedVehicle(systemID: oldInst.mavlinkSystemID)
        }
        sitl.stop(id: old.sitlSessionID)
        await sitl.waitForRecentlyReleasedPortsToSettle()
        slots.remove(at: index)

        let resolvedPreset = preset ?? vehicleClass.simulationPreset
        let resolvedPlatform = platform ?? simulationPlatform
        let resolvedTier = sizeTier ?? vehicleSizeTier

        statusText = "Replacing simulator (stop + spawn)…"
        isBusy = true
        let before = Set(sitl.instances.map(\.id))
        let defaults = staggeredSpawnDefaults(slotIndex: index)
        sitl.spawn(
            preset: resolvedPreset,
            platform: resolvedPlatform,
            defaults: defaults,
            owner: .trainingRoster,
            gazeboPlacement: gazeboPlacement
        )
        guard let row = sitl.instances.first(where: {
            !before.contains($0.id) && $0.spawnOwner == .trainingRoster
        }) else {
            statusText = sitl.lastError ?? "Could not spawn replacement simulator."
            return nil
        }
        let replacement = FormationsPlaygroundSlotState(
            sitlSessionID: row.id,
            vehicleID: vehicleID(forStackInstance: row.stackInstanceIndex, fleetLink: fleetLink),
            linkReady: false,
            preflightPassed: nil,
            preflightDetail: nil
        )
        slots.insert(replacement, at: index)
        if let vid = replacement.vehicleID {
            fleetLink.setVehicleSizeTier(resolvedTier, forVehicleID: vid)
        }
        isBusy = false

        if let inst = sitl.instances.first(where: { $0.id == replacement.sitlSessionID && $0.isAlive }) {
            _ = await bindFleetLinkToFormationSimulator(inst: inst, fleetLink: fleetLink, sitl: sitl)
        }

        guard await waitForSlotFleetReady(slotID: replacement.id, fleetLink: fleetLink) else {
            statusText = "Replacement simulator did not reach live telemetry in time."
            return slots.first(where: { $0.id == replacement.id })
        }
        refreshSlotRows(fleetLink: fleetLink)
        try? await Task.sleep(nanoseconds: 750_000_000)

        await retrySimulatorConnection(slotID: replacement.id, missionControl: missionControl)

        if phase == .following, replacement.vehicleID != nil, slots[index].preflightPassed == true {
            await refreshFormationStreams()
        }
        return slots.first(where: { $0.id == replacement.id })
    }

    /// Back-compat alias for preflight-failure replace; same as ``replaceSlot``.
    func replaceFailedSlot(
        slotID: UUID,
        missionControl: MissionControlStore
    ) async {
        await replaceSlot(slotID: slotID, missionControl: missionControl)
    }

    func refreshConnectedSimCount(fleetLink: FleetLinkService) {
        refreshSlotRows(fleetLink: fleetLink)
        let connected = slots.filter(\.linkReady).count
        if connectedSimCount != connected {
            connectedSimCount = connected
        }
    }

    func buildAllMapMarkers(fleetLink: FleetLinkService) -> [MapVehicleMarker] {
        buildMapMarkers(fleetLink: fleetLink)
            + buildFormationSlotTargetMarkers(fleetLink: fleetLink)
            + buildFormationSlotCloneMarkers(fleetLink: fleetLink)
    }

    /// WGS84 points for formation map fit — **vehicle markers + red slot targets only** (no spawn home / anchor).
    func formationMapFitPoints(fleetLink: FleetLinkService) -> [(Double, Double)] {
        buildAllMapMarkers(fleetLink: fleetLink).map { ($0.lat, $0.lon) }
    }

    func clearFormationLogs() {
        logLines = []
        followProgressBySlotID = [:]
        lastLoggedMessageBySlotID = [:]
        lastLoggedMovementBySlotID = [:]
        telemetryRecorder.clear()
        telemetryTraceSampleCount = 0
    }

    /// Plain-text + JSONL telemetry trace for paste into analysis tools.
    func telemetryTraceClipboardExport() -> String {
        let plain = telemetryRecorder.plainTextExport()
        let jsonl = telemetryRecorder.jsonLinesExport()
        guard !jsonl.isEmpty else { return plain }
        guard !plain.isEmpty else { return jsonl }
        return plain + "\n\n--- jsonl ---\n\n" + jsonl
    }

    var hasTelemetryTrace: Bool { telemetryTraceSampleCount > 0 }

    /// Red-outline ghosts — live layout during map edit; fixed committed layout after edit ends until next reform.
    func buildFormationSlotTargetMarkers(fleetLink: FleetLinkService) -> [MapVehicleMarker] {
        guard !slots.isEmpty else { return [] }
        let anchor: FormationAnchorPose
        if isSlotGroupMapEditEnabled {
            anchor = liveFormationAnchorPose(fleetLink: fleetLink)
        } else if holdsMapCommittedFormationLayout {
            anchor = committedFormationAnchorPose()
        } else {
            anchor = liveFormationAnchorPose(fleetLink: fleetLink)
        }
        return formationSlotMarkers(
            fleetLink: fleetLink,
            anchor: anchor,
            id: MapVehicleMarkerIdentity.formationPlaygroundSlotTarget(ordinal:),
            glyphKind: .formationSlotTarget,
            colorHex: "#ef4444",
            accessibilityPrefix: "Slot"
        )
    }

    /// Gold-outline preview clones — move with map edit handles; applied to streams when edit ends.
    func buildFormationSlotCloneMarkers(fleetLink: FleetLinkService) -> [MapVehicleMarker] {
        guard isSlotGroupMapEditEnabled, !slots.isEmpty else { return [] }
        return formationSlotMarkers(
            fleetLink: fleetLink,
            anchor: slotGroupPreviewAnchorPose(),
            id: MapVehicleMarkerIdentity.formationPlaygroundSlotClone(ordinal:),
            glyphKind: .formationSlotClone,
            colorHex: "#fbbf24",
            accessibilityPrefix: "Preview slot"
        )
    }

    func buildFormationSlotGroupMapEdit(fleetLink: FleetLinkService) -> GuardianFormationSlotGroupMapEdit? {
        guard isSlotGroupMapEditEnabled, !slots.isEmpty else { return nil }
        let anchor = slotGroupPreviewAnchorPose()
        return GuardianFormationSlotGroupMapEdit(
            centerLat: anchor.lat,
            centerLon: anchor.lon,
            headingDeg: anchor.headingDeg,
            circleRadiusM: formationSlotGroupCircleRadiusM(fleetLink: fleetLink, anchor: anchor)
        )
    }

    func setSlotGroupMapEditEnabled(_ enabled: Bool, fleetLink: FleetLinkService) async {
        guard enabled != isSlotGroupMapEditEnabled else { return }
        if enabled {
            seedSlotGroupPreviewAnchor(fleetLink: fleetLink)
            isSlotGroupMapEditEnabled = true
            return
        }
        isSlotGroupMapEditEnabled = false
        commitPreviewAnchorToFormationLayout()
        await commitSlotGroupMapEditToStreams(fleetLink: fleetLink)
    }

    /// Updates preview clone layout only (call ``syncFormationSlotMapEditChrome()`` after drag ends).
    func previewFormationSlotGroupCenter(lat: Double, lon: Double) {
        guard isSlotGroupMapEditEnabled else { return }
        slotGroupPreviewLat = lat
        slotGroupPreviewLon = lon
    }

    func previewFormationSlotGroupHeading(headingDeg: Double) {
        guard isSlotGroupMapEditEnabled else { return }
        slotGroupPreviewHeadingDeg = headingDeg
    }

    func commitSlotGroupMapEditToStreams(fleetLink: FleetLinkService) async {
        guard phase == .following else { return }
        holdsMapCommittedFormationLayout = true
        await applyFormationAnchorToStreams(fleetLink: fleetLink)
    }

    private func commitPreviewAnchorToFormationLayout() {
        formationAnchorLat = slotGroupPreviewLat
        formationAnchorLon = slotGroupPreviewLon
        formationAnchorHeadingDeg = slotGroupPreviewHeadingDeg
        formationAnchorAltM = slotGroupPreviewAltM
    }

    private func formationSlotMarkers(
        fleetLink: FleetLinkService,
        anchor: FormationAnchorPose,
        id: (Int) -> String,
        glyphKind: GuardianMapVehicleGlyphKind,
        colorHex: String,
        accessibilityPrefix: String
    ) -> [MapVehicleMarker] {
        let primaryID = slots.first?.vehicleID ?? ""
        let spacing = resolvedSpacing(fleetLink: fleetLink, primaryVehicleID: primaryID)
        return slots.indices.map { index in
            let coord: RouteCoordinate
            if index == 0 {
                coord = RouteCoordinate(lat: anchor.lat, lon: anchor.lon)
            } else {
                coord = Utilities.mission.squadFormation.desiredPadSlot(
                    formation: formation,
                    primaryLatitudeDeg: anchor.lat,
                    primaryLongitudeDeg: anchor.lon,
                    primaryHeadingDeg: anchor.headingDeg,
                    wingmanOrdinal: index - 1,
                    spacing: spacing
                )
            }
            let role = index == 0 ? "primary" : "wingman \(index)"
            return MapVehicleMarker(
                id: id(index),
                lat: coord.lat,
                lon: coord.lon,
                label: "",
                colorHex: colorHex,
                glyphKind: glyphKind,
                imageDataURL: nil,
                showLabel: false,
                selected: false,
                draggable: false,
                headingDeg: anchor.headingDeg,
                accessibilityTitle: "\(accessibilityPrefix) \(role)"
            )
        }
    }

    private func formationSlotGroupCircleRadiusM(
        fleetLink: FleetLinkService,
        anchor: FormationAnchorPose
    ) -> Double {
        let primaryID = slots.first?.vehicleID ?? ""
        let spacing = resolvedSpacing(fleetLink: fleetLink, primaryVehicleID: primaryID)
        let center = RouteCoordinate(lat: anchor.lat, lon: anchor.lon)
        var maxM = Self.slotGroupCircleMinRadiusM
        for index in slots.indices {
            let coord: RouteCoordinate
            if index == 0 {
                coord = center
            } else {
                coord = Utilities.mission.squadFormation.desiredPadSlot(
                    formation: formation,
                    primaryLatitudeDeg: anchor.lat,
                    primaryLongitudeDeg: anchor.lon,
                    primaryHeadingDeg: anchor.headingDeg,
                    wingmanOrdinal: index - 1,
                    spacing: spacing
                )
            }
            let d = MissionRunMovePointParkPlanner.haversineMeters(
                lat1: center.lat,
                lon1: center.lon,
                lat2: coord.lat,
                lon2: coord.lon
            )
            maxM = max(maxM, d)
        }
        return max(Self.slotGroupCircleMinRadiusM, maxM + Self.slotGroupCirclePaddingM)
    }

    func buildMapMarkers(fleetLink: FleetLinkService) -> [MapVehicleMarker] {
        slots.enumerated().compactMap { index, slot in
            guard let vehicleID = slot.vehicleID,
                  let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg
            else { return nil }
            let vType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType ?? vehicleClass.fleetVehicleType
            let label: String = {
                if index == 0 { return "Primary" }
                if slot.preflightPassed == false { return "W\(index) ✗" }
                if slot.preflightPassed == nil { return "W\(index) …" }
                return "W\(index)"
            }()
            return MapVehicleMarker(
                id: MapVehicleMarkerIdentity.fleetHubVehicle(vehicleID),
                lat: lat,
                lon: lon,
                label: label,
                colorHex: fleetLink.mapColorHex(forVehicleID: vehicleID),
                glyphKind: GuardianMapVehicleGlyphKind.forFleetVehicleType(vType),
                imageDataURL: nil,
                showLabel: true,
                selected: index == 0,
                draggable: false,
                headingDeg: MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub)
            )
        }
    }

    // MARK: - Private

    private func vehicleID(forStackInstance index: Int, fleetLink: FleetLinkService) -> String {
        if let inst = sitl?.instances.first(where: { $0.stackInstanceIndex == index && $0.isAlive }) {
            return fleetLink.vehicleID(forSystemID: inst.mavlinkSystemID) ?? inst.guardianVehicleStreamKey
        }
        let systemID = index + 1
        return fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
    }

    private func staggeredSpawnDefaults(slotIndex: Int) -> SimSpawnDefaults {
        var d = spawnDefaults
        guard slotIndex > 0 else { return d }
        // Spread wingmen astern / lateral so rear-row slots are not all "ahead of slot" (reverse OFFBOARD).
        let asternLaneM = Double((slotIndex + 1) / 2) * 5.0
        let lateralM = (slotIndex % 2 == 0 ? 1.0 : -1.0) * min(3.0, Double((slotIndex - 1) % 3 + 1))
        let offset = MissionSquadFormationGeometry.offsetCoordinate(
            latitudeDeg: d.latitudeDeg,
            longitudeDeg: d.longitudeDeg,
            headingDeg: d.headingDeg,
            forwardMeters: -asternLaneM,
            rightMeters: lateralM
        )
        d.latitudeDeg = offset.lat
        d.longitudeDeg = offset.lon
        return d
    }

    private func liveStatusLabel() -> String {
        let ready = preflightReadyVehicleIDs.count
        let total = slots.count
        guard total > 0 else { return "Spawn simulators to preview formation spacing." }
        if phase == .following {
            return "\(ready) of \(total) ready · \(formation.displayTitle) · \(spacing.displayTitle) spacing"
        }
        return "\(ready) of \(total) preflight passed · \(formation.displayTitle) · \(spacing.displayTitle)"
    }

    private func stopPlaygroundSquadTrackedInstancesOnly(sitl: SitlService) {
        for slot in slots {
            sitl.stop(id: slot.sitlSessionID)
        }
    }

    private func syncSlotsFromRunningSitl(fleetLink: FleetLinkService) {
        guard let sitl else { return }
        let alive = sitl.instances
            .aliveInstances(owner: .trainingRoster)
            .sorted { $0.stackInstanceIndex < $1.stackInstanceIndex }
        guard !alive.isEmpty else {
            slots = slots.filter { row in
                sitl.instances.contains(where: { $0.id == row.sitlSessionID && $0.isAlive })
            }
            return
        }

        var merged: [FormationsPlaygroundSlotState] = []
        for inst in alive {
            let vid = vehicleID(forStackInstance: inst.stackInstanceIndex, fleetLink: fleetLink)
            let prior = slots.first(where: { $0.sitlSessionID == inst.id })
            var preflightPassed = prior?.preflightPassed
            var preflightDetail = prior?.preflightDetail
            if preflightPassed == nil,
               let hub = fleetLink.hubTelemetry(forVehicleID: vid),
               hub.isArmed == true {
                preflightPassed = true
                preflightDetail = "Already armed."
            }
            let linkReady = slotFleetReady(fleetLink: fleetLink, vehicleID: vid)
            merged.append(
                FormationsPlaygroundSlotState(
                    sitlSessionID: inst.id,
                    vehicleID: vid,
                    linkReady: linkReady,
                    preflightPassed: preflightPassed,
                    preflightDetail: preflightDetail
                )
            )
        }
        slots = merged
        simCount = max(simCount, merged.count)
    }

    private func bindFleetLinkToFormationSimulator(
        inst: SitlRunningInstance,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async -> Bool {
        let vehicleID = vehicleID(forStackInstance: inst.stackInstanceIndex, fleetLink: fleetLink)
        await fleetLink.stopFormationFollowStream(vehicleID: vehicleID)

        if GuardianSitlFleetLinkReconnectPolicy.simulatorFleetLinkReadyWithMavsdkSession(
            fleetLink: fleetLink,
            vehicleID: vehicleID
        ) {
            refreshSlotRows(fleetLink: fleetLink)
            return true
        }

        fleetLink.unregisterSimulatedVehicle(systemID: inst.mavlinkSystemID)
        try? await Task.sleep(nanoseconds: 350_000_000)
        let ok = await sitl.reconnectFleetLink(sitlSessionID: inst.id, spawnDefaults: spawnDefaults)
        refreshSlotRows(fleetLink: fleetLink)
        return ok
    }

    private func stopAllStreams() async {
        Utilities.movements.sequenceStore.clearAll()
        guard let fleetLink else { return }
        for vehicleID in orderedVehicleIDs {
            await fleetLink.stopFormationFollowStream(vehicleID: vehicleID)
        }
    }

    private func slotFleetReady(fleetLink: FleetLinkService, vehicleID: String) -> Bool {
        GuardianSitlFleetLinkReconnectPolicy.simulatorFleetLinkReady(
            fleetLink: fleetLink,
            vehicleID: vehicleID
        )
    }

    private func syncFormationVehicleSizeTiers(fleetLink: FleetLinkService) {
        for slot in slots {
            guard let vehicleID = slot.vehicleID else { continue }
            VehicleClassSizePreferencesStore.shared.setTier(vehicleSizeTier, forVehicleID: vehicleID)
            fleetLink.setVehicleSizeTier(vehicleSizeTier, forVehicleID: vehicleID)
        }
    }

    private func refreshSlotRows(fleetLink: FleetLinkService) {
        guard let sitl else { return }
        for index in slots.indices {
            let sessionID = slots[index].sitlSessionID
            if let row = sitl.instances.first(where: { $0.id == sessionID }) {
                slots[index].vehicleID = vehicleID(
                    forStackInstance: row.stackInstanceIndex,
                    fleetLink: fleetLink
                )
            } else {
                slots[index].vehicleID = nil
                slots[index].linkReady = false
                continue
            }
            if let vid = slots[index].vehicleID {
                slots[index].linkReady = slotFleetReady(fleetLink: fleetLink, vehicleID: vid)
            } else {
                slots[index].linkReady = false
            }
        }
        connectedSimCount = slots.filter(\.linkReady).count
        syncFormationVehicleSizeTiers(fleetLink: fleetLink)
    }

    private func waitForAllSlotsFleetReady(fleetLink: FleetLinkService) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.linkWaitTimeoutS)
        while Date() < deadline {
            refreshSlotRows(fleetLink: fleetLink)
            if slots.count == simCount, slots.allSatisfy(\.linkReady) {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func waitForSlotFleetReady(slotID: UUID, fleetLink: FleetLinkService) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.linkWaitTimeoutS)
        while Date() < deadline {
            refreshSlotRows(fleetLink: fleetLink)
            if let slot = slots.first(where: { $0.id == slotID }), slot.linkReady {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func runPreflightOnSlots(
        missionControl: MissionControlStore,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async -> Bool {
        await stopAllStreams()
        var allPassed = true
        for index in slots.indices {
            guard let vehicleID = slots[index].vehicleID else {
                slots[index].preflightPassed = false
                slots[index].preflightDetail = "Not linked."
                allPassed = false
                continue
            }
            if !slotFleetReady(fleetLink: fleetLink, vehicleID: vehicleID) {
                slots[index].preflightPassed = false
                slots[index].preflightDetail = MissionControlStore.preflightProbeNotConnectedDetail
                allPassed = false
                continue
            }
            let probe = await missionControl.runSingleVehiclePreflightProbe(
                vehicleID: vehicleID,
                fleetLink: fleetLink,
                sitl: sitl,
                leaveArmed: true,
                allowDuringLiveMission: true,
                preflightAuditSource: Self.preflightSource
            )
            slots[index].preflightPassed = probe.passed
            slots[index].preflightDetail = probe.detail
            if !probe.passed { allPassed = false }
        }
        return allPassed
    }

    private func applyFormationControl(fleetLink: FleetLinkService) async {
        let ready = preflightReadyVehicleIDs
        guard !ready.isEmpty else {
            statusText = "Preflight at least the primary simulator before reforming."
            return
        }

        let wasFollowing = phase == .following
        if !wasFollowing {
            phase = .assembling
        }
        telemetryRecorder.beginSession(
            formationTitle: formation.displayTitle,
            spacingTitle: spacing.displayTitle,
            vehicleClassTitle: vehicleClass.displayTitle
        )
        telemetryTraceSampleCount = 0
        statusText = "Reforming \(formation.displayTitle) · \(spacing.displayTitle) spacing…"
        appendFormationLog(
            vehicleLabel: "Squad",
            state: .movingToPosition,
            message: "Reform started — recovering out-of-position simulators, then re-streaming slots."
        )
        holdsMapCommittedFormationLayout = false
        captureFormationAnchor(fleetLink: fleetLink)
        await recoverOutOfPositionSimulators(fleetLink: fleetLink)
        await startFormationStreams(fleetLink: fleetLink)

        phase = .following
        ensureTickLoop()
        statusText = liveStatusLabel()
    }

    private struct FormationAnchorPose {
        let lat: Double
        let lon: Double
        let headingDeg: Double
        let altM: Double
    }

    private func formationAnchorForTargets(fleetLink: FleetLinkService) -> FormationAnchorPose {
        liveFormationAnchorPose(fleetLink: fleetLink)
    }

    private func liveFormationAnchorPose(fleetLink: FleetLinkService) -> FormationAnchorPose {
        if let primaryID = slots.first?.vehicleID,
           let hub = fleetLink.hubTelemetry(forVehicleID: primaryID),
           let lat = hub.latitudeDeg,
           let lon = hub.longitudeDeg {
            return FormationAnchorPose(
                lat: lat,
                lon: lon,
                headingDeg: MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub) ?? formationAnchorHeadingDeg,
                altM: hub.absoluteAltM ?? hub.altitudeAmslM ?? formationAnchorAltM
            )
        }
        return committedFormationAnchorPose()
    }

    private func committedFormationAnchorPose() -> FormationAnchorPose {
        FormationAnchorPose(
            lat: formationAnchorLat,
            lon: formationAnchorLon,
            headingDeg: formationAnchorHeadingDeg,
            altM: formationAnchorAltM
        )
    }

    private func slotGroupPreviewAnchorPose() -> FormationAnchorPose {
        FormationAnchorPose(
            lat: slotGroupPreviewLat,
            lon: slotGroupPreviewLon,
            headingDeg: slotGroupPreviewHeadingDeg,
            altM: slotGroupPreviewAltM
        )
    }

    private func seedSlotGroupPreviewAnchor(fleetLink: FleetLinkService) {
        let pose = committedFormationAnchorPose()
        if phase == .following, let primaryID = slots.first?.vehicleID,
           let hub = fleetLink.hubTelemetry(forVehicleID: primaryID),
           let lat = hub.latitudeDeg, let lon = hub.longitudeDeg {
            slotGroupPreviewLat = lat
            slotGroupPreviewLon = lon
            slotGroupPreviewHeadingDeg = MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub)
                ?? formationAnchorHeadingDeg
            slotGroupPreviewAltM = hub.absoluteAltM ?? hub.altitudeAmslM ?? formationAnchorAltM
        } else {
            slotGroupPreviewLat = pose.lat
            slotGroupPreviewLon = pose.lon
            slotGroupPreviewHeadingDeg = pose.headingDeg
            slotGroupPreviewAltM = pose.altM
        }
    }

    private func applyFormationAnchorToStreams(fleetLink: FleetLinkService) async {
        guard phase == .following else { return }
        let ready = preflightReadyVehicleIDs
        guard let primaryID = ready.first else { return }

        let lat = formationAnchorLat
        let lon = formationAnchorLon
        let heading = formationAnchorHeadingDeg
        let alt = formationAnchorAltM
        let spacing = resolvedSpacing(fleetLink: fleetLink, primaryVehicleID: primaryID)
        let primarySpeed = fleetLink.hubTelemetry(forVehicleID: primaryID)?.horizontalGroundSpeedMS

        let primaryTarget = FormationsPlaygroundStreamTargets.primaryHold(
            lat: lat,
            lon: lon,
            primaryHeadingDeg: heading,
            absoluteAltitudeM: alt
        )
        if fleetLink.isFormationFollowStreaming(vehicleID: primaryID) {
            fleetLink.updateFormationFollowTarget(vehicleID: primaryID, target: primaryTarget)
        } else {
            await ensureFormationStream(vehicleID: primaryID, target: primaryTarget, fleetLink: fleetLink)
        }

        var wingmanOrdinal = 0
        for vehicleID in ready.dropFirst() {
            let slot = Utilities.mission.squadFormation.desiredPadSlot(
                formation: formation,
                primaryLatitudeDeg: lat,
                primaryLongitudeDeg: lon,
                primaryHeadingDeg: heading,
                wingmanOrdinal: wingmanOrdinal,
                spacing: spacing
            )
            let vType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType ?? vehicleClass.fleetVehicleType
            let target = FormationsPlaygroundStreamTargets.wingmanPursuit(
                wingmanVehicleID: vehicleID,
                slot: slot,
                primaryHeadingDeg: heading,
                vehicleType: vType,
                wingmanAbsoluteAltitudeM: alt,
                primarySpeedMS: primarySpeed,
                fleetLink: fleetLink
            )
            if fleetLink.isFormationFollowStreaming(vehicleID: vehicleID) {
                fleetLink.updateFormationFollowTarget(vehicleID: vehicleID, target: target)
            } else {
                await ensureFormationStream(vehicleID: vehicleID, target: target, fleetLink: fleetLink)
            }
            wingmanOrdinal += 1
        }
    }

    private func captureFormationAnchor(fleetLink: FleetLinkService) {
        if let primaryID = slots.first?.vehicleID,
           let hub = fleetLink.hubTelemetry(forVehicleID: primaryID),
           let lat = hub.latitudeDeg,
           let lon = hub.longitudeDeg {
            formationAnchorLat = lat
            formationAnchorLon = lon
            formationAnchorHeadingDeg = MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub) ?? formationAnchorHeadingDeg
            formationAnchorAltM = hub.absoluteAltM ?? hub.altitudeAmslM ?? formationAnchorAltM
        } else {
            formationAnchorLat = spawnDefaults.latitudeDeg
            formationAnchorLon = spawnDefaults.longitudeDeg
            formationAnchorHeadingDeg = spawnDefaults.headingDeg
            formationAnchorAltM = spawnDefaults.altitudeM
        }
    }

    private func startFormationStreams(fleetLink: FleetLinkService) async {
        let ready = preflightReadyVehicleIDs
        guard let primaryID = ready.first else { return }

        let spacing = resolvedSpacing(fleetLink: fleetLink, primaryVehicleID: primaryID)
        let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryID)
        let primarySpeed = primaryHub?.horizontalGroundSpeedMS

        let primaryTarget = FormationsPlaygroundStreamTargets.primaryHold(
            lat: formationAnchorLat,
            lon: formationAnchorLon,
            primaryHeadingDeg: formationAnchorHeadingDeg,
            absoluteAltitudeM: formationAnchorAltM
        )
        await ensureFormationStream(vehicleID: primaryID, target: primaryTarget, fleetLink: fleetLink)

        await withTaskGroup(of: Void.self) { group in
            var wingmanOrdinal = 0
            for vehicleID in ready.dropFirst() {
                let ordinal = wingmanOrdinal
                wingmanOrdinal += 1
                let slot = Utilities.mission.squadFormation.desiredPadSlot(
                    formation: formation,
                    primaryLatitudeDeg: formationAnchorLat,
                    primaryLongitudeDeg: formationAnchorLon,
                    primaryHeadingDeg: formationAnchorHeadingDeg,
                    wingmanOrdinal: ordinal,
                    spacing: spacing
                )
                let vType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType
                    ?? vehicleClass.fleetVehicleType
                let target = FormationsPlaygroundStreamTargets.wingmanPursuit(
                    wingmanVehicleID: vehicleID,
                    slot: slot,
                    primaryHeadingDeg: formationAnchorHeadingDeg,
                    vehicleType: vType,
                    wingmanAbsoluteAltitudeM: formationAnchorAltM,
                    primarySpeedMS: primarySpeed,
                    fleetLink: fleetLink
                )
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.ensureFormationStream(vehicleID: vehicleID, target: target, fleetLink: fleetLink)
                }
            }
        }
    }

    private func refreshFormationStreams() async {
        guard let fleetLink, phase == .following else { return }
        await tick(fleetLink: fleetLink)
    }

    private func ensureTickLoop() {
        guard tickTask == nil, let fleetLink else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickIntervalNs)
                guard let self, !Task.isCancelled, self.phase == .following else { return }
                await self.tick(fleetLink: fleetLink)
            }
        }
    }

    private func tick(fleetLink: FleetLinkService) async {
        let ready = preflightReadyVehicleIDs
        guard let primaryID = ready.first else { return }

        let spacing = resolvedSpacing(fleetLink: fleetLink, primaryVehicleID: primaryID)
        let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryID)
        let lat: Double
        let lon: Double
        let heading: Double
        let alt: Double
        if holdsMapCommittedFormationLayout && !isSlotGroupMapEditEnabled {
            lat = formationAnchorLat
            lon = formationAnchorLon
            heading = formationAnchorHeadingDeg
            alt = formationAnchorAltM
        } else {
            lat = primaryHub?.latitudeDeg ?? formationAnchorLat
            lon = primaryHub?.longitudeDeg ?? formationAnchorLon
            heading = MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: primaryHub)
                ?? formationAnchorHeadingDeg
            alt = primaryHub?.absoluteAltM ?? primaryHub?.altitudeAmslM ?? formationAnchorAltM
            if !isSlotGroupMapEditEnabled {
                formationAnchorLat = lat
                formationAnchorLon = lon
                formationAnchorHeadingDeg = heading
                formationAnchorAltM = alt
            }
        }
        let primarySpeed = primaryHub?.horizontalGroundSpeedMS

        let primaryTarget = FormationsPlaygroundStreamTargets.primaryHold(
            lat: lat,
            lon: lon,
            primaryHeadingDeg: heading,
            absoluteAltitudeM: alt
        )
        if fleetLink.isFormationFollowStreaming(vehicleID: primaryID) {
            fleetLink.updateFormationFollowTarget(vehicleID: primaryID, target: primaryTarget)
        }

        var wingmanOrdinal = 0
        for vehicleID in ready.dropFirst() {
            let slot = Utilities.mission.squadFormation.desiredPadSlot(
                formation: formation,
                primaryLatitudeDeg: lat,
                primaryLongitudeDeg: lon,
                primaryHeadingDeg: heading,
                wingmanOrdinal: wingmanOrdinal,
                spacing: spacing
            )
            let vType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType ?? vehicleClass.fleetVehicleType
            let target = FormationsPlaygroundStreamTargets.wingmanPursuit(
                wingmanVehicleID: vehicleID,
                slot: slot,
                primaryHeadingDeg: heading,
                vehicleType: vType,
                wingmanAbsoluteAltitudeM: alt,
                primarySpeedMS: primarySpeed,
                fleetLink: fleetLink
            )
            if fleetLink.isFormationFollowStreaming(vehicleID: vehicleID) {
                fleetLink.updateFormationFollowTarget(vehicleID: vehicleID, target: target)
            } else {
                await ensureFormationStream(vehicleID: vehicleID, target: target, fleetLink: fleetLink)
            }
            wingmanOrdinal += 1
        }
        refreshConnectedSimCount(fleetLink: fleetLink)
        updateFormationFollowLogs(fleetLink: fleetLink)
    }

    private func resolvedSpacing(fleetLink: FleetLinkService, primaryVehicleID: String) -> MissionSquadConvoySpacing {
        let vType = fleetLink.vehicleModel(forVehicleID: primaryVehicleID)?.data.vehicleType ?? vehicleClass.fleetVehicleType
        return MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: vType,
            spacing: spacing,
            formation: formation
        )
    }

    private func ensureFormationStream(
        vehicleID: String,
        target: FormationFollowStream.Target,
        fleetLink: FleetLinkService
    ) async {
        if fleetLink.isFormationFollowStreaming(vehicleID: vehicleID) {
            fleetLink.updateFormationFollowTarget(vehicleID: vehicleID, target: target)
            return
        }
        _ = await fleetLink.startFormationFollowStream(vehicleID: vehicleID, initialTarget: target)
    }

    // MARK: - Formation logs & stuck recovery

    private func slotLabel(index: Int) -> String {
        index == 0 ? "Primary" : "W\(index)"
    }

    private func appendFormationLog(
        vehicleLabel: String,
        state: FormationsPlaygroundFollowState,
        message: String
    ) {
        logLines.insert(
            FormationsPlaygroundLogLine(vehicleLabel: vehicleLabel, state: state, message: message),
            at: 0
        )
        if logLines.count > Self.maxLogLines {
            logLines.removeLast(logLines.count - Self.maxLogLines)
        }
    }

    private func publishSlotLogIfChanged(slotID: UUID, label: String, evaluation: FormationsPlaygroundFollowDiagnostics.Evaluation) {
        guard lastLoggedMessageBySlotID[slotID] != evaluation.message else { return }
        lastLoggedMessageBySlotID[slotID] = evaluation.message
        appendFormationLog(vehicleLabel: label, state: evaluation.state, message: evaluation.message)
    }

    private func updateFormationFollowLogs(fleetLink: FleetLinkService) {
        guard phase == .following else { return }
        let ready = preflightReadyVehicleIDs
        guard let primaryID = ready.first else { return }

        let spacing = resolvedSpacing(fleetLink: fleetLink, primaryVehicleID: primaryID)
        let anchor = formationAnchorForTargets(fleetLink: fleetLink)
        let primarySpeed = fleetLink.hubTelemetry(forVehicleID: primaryID)?.horizontalGroundSpeedMS

        for (index, vehicleID) in ready.enumerated() {
            let slotID = slots[index].id
            let label = slotLabel(index: index)
            let slotCoord: RouteCoordinate
            if index == 0 {
                slotCoord = RouteCoordinate(lat: anchor.lat, lon: anchor.lon)
            } else {
                slotCoord = Utilities.mission.squadFormation.desiredPadSlot(
                    formation: formation,
                    primaryLatitudeDeg: anchor.lat,
                    primaryLongitudeDeg: anchor.lon,
                    primaryHeadingDeg: anchor.headingDeg,
                    wingmanOrdinal: index - 1,
                    spacing: spacing
                )
            }

            let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            let arrivalM = MissionSquadConvoyFollowControlPolicy.convoyAssemblyArrivalM
            let stuckDistanceM = max(6.0, arrivalM * 4)
            var progress = followProgressBySlotID[slotID] ?? (lastDistanceM: nil, ticksWithoutProgress: 0)
            let dist: Double?
            if let hub, let lat = hub.latitudeDeg, let lon = hub.longitudeDeg {
                dist = MissionRunSquadConvoyAssemblyUtilities.distanceToSlotM(
                    wingmanLatitudeDeg: lat,
                    wingmanLongitudeDeg: lon,
                    slot: slotCoord
                )
            } else {
                dist = nil
            }
            if let dist {
                progress.ticksWithoutProgress = FormationsPlaygroundFollowDiagnostics.updateProgressTicks(
                    previousDistanceM: progress.lastDistanceM,
                    currentDistanceM: dist,
                    previousTicks: progress.ticksWithoutProgress
                )
                progress.lastDistanceM = dist
            }
            followProgressBySlotID[slotID] = progress

            let targetHeading = MissionSquadFormationHeadingPolicy.resolvedTargetHeadingDeg(
                primaryHeadingDeg: anchor.headingDeg
            )
            let evaluation = FormationsPlaygroundFollowDiagnostics.evaluate(
                vehicleLabel: label,
                hub: hub,
                slot: slotCoord,
                targetHeadingDeg: targetHeading,
                arrivalM: arrivalM,
                stuckDistanceM: stuckDistanceM,
                ticksWithoutProgress: progress.ticksWithoutProgress
            )
            publishSlotLogIfChanged(slotID: slotID, label: label, evaluation: evaluation)
            publishMovementLogIfChanged(
                slotID: slotID,
                label: label,
                vehicleID: vehicleID,
                slot: slotCoord,
                targetHeading: targetHeading,
                primarySpeedMS: primarySpeed,
                fleetLink: fleetLink
            )
            recordTelemetryTraceSample(
                slotID: slotID,
                vehicleID: vehicleID,
                label: label,
                hub: hub,
                slot: slotCoord,
                targetHeading: targetHeading,
                anchor: anchor,
                primarySpeedMS: primarySpeed,
                arrivalM: arrivalM,
                fleetLink: fleetLink
            )
        }
        telemetryTraceSampleCount = telemetryRecorder.samples.count
    }

    private func recordTelemetryTraceSample(
        slotID: UUID,
        vehicleID: String,
        label: String,
        hub: FleetHubVehicleTelemetry?,
        slot: RouteCoordinate,
        targetHeading: Double,
        anchor: FormationAnchorPose,
        primarySpeedMS: Double?,
        arrivalM: Double,
        fleetLink: FleetLinkService
    ) {
        let vType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType ?? vehicleClass.fleetVehicleType
        let pursuit = Utilities.movements.formationSlotPursuit(
            slot: slot,
            targetHeadingDeg: targetHeading,
            vehicleType: vType,
            hub: hub,
            primarySpeedMS: primarySpeedMS
        )
        let streamTarget = FormationsPlaygroundStreamTargets.wingmanPursuit(
            wingmanVehicleID: vehicleID,
            slot: slot,
            primaryHeadingDeg: anchor.headingDeg,
            vehicleType: vType,
            wingmanAbsoluteAltitudeM: anchor.altM,
            primarySpeedMS: primarySpeedMS,
            fleetLink: fleetLink
        )
        let streamPositionYawHold = streamTarget.pursuitForwardMS == nil

        telemetryRecorder.record(
            FormationsPlaygroundTelemetryRecordInput(
                slotID: slotID,
                vehicleLabel: label,
                vehicleID: vehicleID,
                hub: hub,
                slot: slot,
                targetHeadingDeg: targetHeading,
                primaryLatitudeDeg: anchor.lat,
                primaryLongitudeDeg: anchor.lon,
                primaryHeadingDeg: anchor.headingDeg,
                movementID: pursuit?.plan.movementID,
                bodyForwardMS: pursuit?.plan.bodyForwardMS,
                yawspeedDegS: pursuit?.plan.yawspeedDegS,
                streamPositionYawHold: streamPositionYawHold,
                arrivalM: arrivalM,
                headingToleranceDeg: MissionSquadConvoyFollowControlPolicy.convoyAssemblyHeadingToleranceDeg
            )
        )
    }

    private func publishMovementLogIfChanged(
        slotID: UUID,
        label: String,
        vehicleID: String,
        slot: RouteCoordinate,
        targetHeading: Double,
        primarySpeedMS: Double?,
        fleetLink: FleetLinkService
    ) {
        let vType = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType ?? vehicleClass.fleetVehicleType
        guard let pursuit = Utilities.movements.formationSlotPursuit(
            slot: slot,
            targetHeadingDeg: targetHeading,
            vehicleType: vType,
            hub: fleetLink.hubTelemetry(forVehicleID: vehicleID),
            primarySpeedMS: primarySpeedMS
        ) else { return }
        let key = "\(pursuit.plan.movementID.rawValue)|\(pursuit.plan.summary)"
        guard lastLoggedMovementBySlotID[slotID] != key else { return }
        lastLoggedMovementBySlotID[slotID] = key
        var detail = "\(label): \(pursuit.plan.movementID.rawValue) — \(pursuit.plan.summary)"
        if !pursuit.evidence.declinedMovementIDs.isEmpty {
            let declined = pursuit.evidence.declinedMovementIDs.map(\.rawValue).joined(separator: ", ")
            detail += " (unsupported: \(declined))."
        }
        appendFormationLog(
            vehicleLabel: label,
            state: .movingToPosition,
            message: detail
        )
        try? GuardianMovementEvidenceStore.append(pursuit.evidence)
    }

    /// SITL snap + stream restart for wingmen (and primary when far from hold) before re-streaming formation targets.
    private func recoverOutOfPositionSimulators(fleetLink: FleetLinkService) async {
        let ready = preflightReadyVehicleIDs
        guard let primaryID = ready.first else { return }

        let spacing = resolvedSpacing(fleetLink: fleetLink, primaryVehicleID: primaryID)
        let anchor = formationAnchorForTargets(fleetLink: fleetLink)
        let arrivalM = MissionSquadConvoyFollowControlPolicy.convoyAssemblyArrivalM
        for (index, vehicleID) in ready.enumerated() {
            guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else { continue }
            let label = slotLabel(index: index)
            let slotCoord: RouteCoordinate
            let headingDeg: Double
            let altM: Double
            if index == 0 {
                slotCoord = RouteCoordinate(lat: anchor.lat, lon: anchor.lon)
                headingDeg = MissionSquadFormationHeadingPolicy.resolvedTargetHeadingDeg(
                    primaryHeadingDeg: anchor.headingDeg
                )
                altM = anchor.altM
            } else {
                slotCoord = Utilities.mission.squadFormation.desiredPadSlot(
                    formation: formation,
                    primaryLatitudeDeg: anchor.lat,
                    primaryLongitudeDeg: anchor.lon,
                    primaryHeadingDeg: anchor.headingDeg,
                    wingmanOrdinal: index - 1,
                    spacing: spacing
                )
                headingDeg = MissionSquadFormationHeadingPolicy.resolvedTargetHeadingDeg(
                    primaryHeadingDeg: anchor.headingDeg
                )
                altM = anchor.altM
            }

            guard let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg
            else { continue }

            let distM = MissionRunSquadConvoyAssemblyUtilities.distanceToSlotM(
                wingmanLatitudeDeg: lat,
                wingmanLongitudeDeg: lon,
                slot: slotCoord
            )
            guard FormationsPlaygroundFollowDiagnostics.shouldSnapToSlot(distanceM: distM, arrivalM: arrivalM) else {
                continue
            }

            await fleetLink.stopFormationFollowStream(vehicleID: vehicleID)
            let simState = FleetSimState(
                latitudeDeg: slotCoord.lat,
                longitudeDeg: slotCoord.lon,
                absoluteAltitudeM: altM,
                yawDeg: Float(headingDeg)
            )
            let stack = hub.autopilotStack != .unknown
                ? hub.autopilotStack
                : FleetAutopilotStack(simulationPlatform: simulationPlatform)
            await fleetLink.applySimState(
                vehicleID: vehicleID,
                state: simState,
                autopilotStack: stack,
                source: Self.snapSource
            )
            followProgressBySlotID[slots[index].id] = (lastDistanceM: distM, ticksWithoutProgress: 0)
            appendFormationLog(
                vehicleLabel: label,
                state: .movingToPosition,
                message:
                    "\(label): snapped to slot (was \(String(format: "%.1f", distM)) m away) — re-streaming OFFBOARD/GUIDED."
            )
        }
    }
}
