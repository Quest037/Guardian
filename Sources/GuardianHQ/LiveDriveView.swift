import AppKit
import SwiftUI

struct LiveDriveView: View {
    @ObservedObject var store: LiveDriveStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var missionControlStore: MissionControlStore
    @ObservedObject var manualControlSettings: ManualControlSettingsStore
    @StateObject private var mapModel = GuardianMapModel(preserveView: true)
    @State private var vehiclePickerVisible = false
    @State private var mediaTab: LiveDriveMediaTab = .map
    @State private var sessionStartInFlight = false
    @State private var sessionStatusText: String?
    @State private var sessionStatusIsError = false
    @State private var freestylePreflightPresented = false
    @State private var lastKeyboardCommandText: String?
    @State private var lastKeyboardCommandFailed = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                subBar

                GeometryReader { geo in
                    let spacing: CGFloat = 14
                    let outerPadding: CGFloat = 16
                    let totalW = geo.size.width
                    let totalH = geo.size.height
                    let contentW = max(0, totalW - (outerPadding * 2))
                    let contentH = max(0, totalH - (outerPadding * 2))
                    // Left column is 70% of content area width (explicit requirement).
                    let leftW = contentW * 0.7
                    // Right column consumes remaining width after gutter.
                    let rightW = max(0, contentW - leftW - spacing)
                    // Left column vertical split is 70/30 (with gutter accounted for).
                    let mediaH = max(220, (contentH - spacing) * 0.7)
                    let telemetryH = max(120, (contentH - spacing) * 0.3)

                    HStack(alignment: .top, spacing: spacing) {
                        VStack(spacing: spacing) {
                            mediaCard
                                .frame(maxWidth: .infinity)
                                .frame(height: mediaH)
                            telemetryCard
                                .frame(height: telemetryH)
                        }
                        .frame(width: leftW)

                        logCard
                            .frame(width: rightW, height: contentH)
                    }
                    .padding(outerPadding)
                    .frame(width: totalW, height: totalH, alignment: .topLeading)
                }
            }
            .background(
                KeyboardEventMonitor(isEnabled: keyboardControlsEnabled) { event in
                    handleKeyboardEvent(event)
                }
            )

            if vehiclePickerVisible {
                Color.black.opacity(0.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vehiclePickerVisible = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }

            if vehiclePickerVisible {
                LiveDriveVehiclePickerSidebar(
                    vehicles: pickableVehicles,
                    selectedVehicleID: selectedVehicleID,
                    onSelect: { vehicle in
                        store.selectVehicle(resolvedVehicleID(for: vehicle))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vehiclePickerVisible = false
                        }
                        mapModel.recenter()
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vehiclePickerVisible = false
                        }
                    }
                )
                .frame(width: 380)
                .frame(maxHeight: .infinity)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $freestylePreflightPresented) {
            if let vehicle = selectedPickableVehicle,
               let vehicleID = selectedVehicleID {
                VehicleTestArmSheet(
                    vehicleTitle: vehicle.title,
                    vehicleID: vehicleID,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    controlStore: missionControlStore,
                    leaveArmed: true,
                    autoCloseOnPass: true,
                    onPassed: {
                        Task { @MainActor in
                            activateFreestyleSessionAfterPreflight()
                        }
                    }
                )
            }
        }
    }

    private var pickableVehicles: [MissionPickableFleetVehicle] {
        buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl)
    }

    private var selectedVehicleID: String? {
        store.activeVehicleID
    }

    private var selectedHub: FleetHubVehicleTelemetry? {
        guard let id = selectedVehicleID else { return nil }
        return fleetLink.hubTelemetry(forVehicleID: id)
    }

    private var selectedVehicleMarker: [MapVehicleMarker] {
        guard let id = selectedVehicleID, let hub = selectedHub, let lat = hub.latitudeDeg, let lon = hub.longitudeDeg else { return [] }
        let imageDataURL = markerImageDataURL(forVehicleID: id)
        return [
            MapVehicleMarker(
                id: id,
                lat: lat,
                lon: lon,
                label: "",
                colorHex: fleetLink.mapColorHex(forVehicleID: id),
                imageDataURL: imageDataURL,
                showLabel: false,
                selected: true,
                draggable: false,
                headingDeg: hub.headingDeg
            ),
        ]
    }

    /// Equatable signature so `.task(id:)` only re-pushes the marker into the
    /// shared map model when the underlying lat/lon/heading changes.
    private var liveDriveMarkerSignature: LiveDriveMarkerSignature {
        LiveDriveMarkerSignature(
            vehicleID: selectedVehicleID,
            lat: selectedHub?.latitudeDeg,
            lon: selectedHub?.longitudeDeg,
            headingDeg: selectedHub?.headingDeg
        )
    }

    private var subBar: some View {
        HStack(spacing: 10) {
            
            Picker("", selection: $mediaTab) {
                Text("Map").tag(LiveDriveMediaTab.map)
                Text("Camera").tag(LiveDriveMediaTab.camera)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)

            Spacer(minLength: 2)

            if selectedVehicleID != nil {
                if let sessionStatusText {
                    Text(sessionStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(sessionStatusIsError ? Color.orange.opacity(0.95) : .gray)
                        .lineLimit(1)
                }
                if let lastKeyboardCommandText {
                    Text(lastKeyboardCommandText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(lastKeyboardCommandFailed ? Color.orange.opacity(0.95) : .gray.opacity(0.92))
                        .lineLimit(1)
                }

                Button("Clear Vehicle") {
                    store.clearActiveVehicleIfIdle()
                }
                .buttonStyle(.bordered)
                .disabled(selectedVehicleID == nil || store.hasActiveSession)

                if store.hasActiveSession {
                    Menu("End Session") {
                        Button("Loiter") {
                            endFreestyleSession(with: .holdPosition)
                        }
                        Button("RTL") {
                            endFreestyleSession(with: .returnToLaunch)
                        }
                        Button("Land") {
                            endFreestyleSession(with: .land)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Start Session") {
                        if vehicleIsInLiveMission {
                            Task { await startMissionSession() }
                        } else {
                            startFreestyleSession()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(selectedVehicleID == nil || sessionStartInFlight)
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vehiclePickerVisible.toggle()
                    }
                } label: {
                    Label("Vehicle Picker", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
            }
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func startFreestyleSession() {
        guard selectedVehicleID != nil else { return }
        sessionStatusText = nil
        sessionStatusIsError = false
        freestylePreflightPresented = true
    }

    @MainActor
    private func activateFreestyleSessionAfterPreflight() {
        guard let vehicleID = selectedVehicleID else { return }
        // Freestyle session takes authority above Paladin.
        fleetLink.setCommandAuthorityGate(vehicleID: vehicleID, minimumCategory: .manualTakeover)
        store.beginSession()
        sessionStatusText = "Freestyle session active."
        sessionStatusIsError = false
    }

    /// Placeholder for future Paladin/manual-handoff policy hooks.
    @MainActor
    private func startMissionSession() async {
        sessionStatusText = "Mission session handoff not implemented yet."
        sessionStatusIsError = true
    }

    @MainActor
    private func endFreestyleSession(with command: FleetVehicleCommand) {
        guard let vehicleID = selectedVehicleID else { return }
        let usedInLiveMission = missionControlStore.isVehicleStreamUsedInLiveMission(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        )

        _ = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: command,
            source: "liveDrive.endSession",
            category: .manualTakeover
        )
        // Release manual takeover gate. `.paladin` is the baseline "no extra gate" priority.
        fleetLink.setCommandAuthorityGate(vehicleID: vehicleID, minimumCategory: .paladin)
        store.endSession()

        let label: String = {
            switch command {
            case .holdPosition: return "Loiter"
            case .returnToLaunch: return "RTL"
            case .land: return "Land"
            default: return "End"
            }
        }()
        if usedInLiveMission {
            sessionStatusText = "Session ended (\(label)); returned to mission authority."
        } else {
            sessionStatusText = "Session ended (\(label)); manual control released."
        }
        sessionStatusIsError = false
    }

    private var mediaCard: some View {
        Group {
            switch mediaTab {
            case .map:
                GuardianMapView(model: mapModel)
                    .task(id: liveDriveMarkerSignature) {
                        mapModel.vehicleMarkers = selectedVehicleMarker
                    }
            case .camera:
                ZStack {
                    Color.black.opacity(0.35)
                    VStack(spacing: 8) {
                        Image(systemName: "video")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.gray)
                        Text("Camera view placeholder")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let label = lastKeyboardCommandText, store.hasActiveSession {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lastKeyboardCommandFailed ? Color.orange.opacity(0.95) : .white.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if let vehicle = selectedPickableVehicle {
                    HStack(spacing: 10) {
                        telemetryVehicleBadge(for: vehicle)
                            .frame(width: 34, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(telemetryHeaderName(for: vehicle))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(telemetryHeaderSubtitle(for: vehicle))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.gray)
                        }
                    }
                } else {
                    Text("Vehicle health / telemetry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                if let hub = selectedHub {
                    HStack(spacing: 8) {
                        telemetryPill("Mode", hub.flightMode.isEmpty ? "—" : hub.flightMode)
                        telemetryPill(
                            "Armed",
                            hub.isArmed ? "Yes" : "No",
                            accent: hub.isArmed ? Color.green : Color.gray.opacity(0.7)
                        )
                        telemetryPill("Battery", hub.batteryRemainingPercent.map { "\(Int(round($0)))%" } ?? "—")
                        telemetryPill("GPS", hub.gpsFixType ?? "—")
                    }
                }
            }
            if let hub = selectedHub {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            telemetryPrimaryBox(
                                "Altitude",
                                hub.relativeAltM.map { String(format: "%.1f m", $0) } ?? "—"
                            )
                            telemetryPrimaryBox(
                                "Heading",
                                hub.headingDeg.map { String(format: "%.0f°", $0) } ?? "—"
                            )
                        }

                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.02))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                        .frame(height: 42)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Messages")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.gray)
                        Text("No active messages.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.gray.opacity(0.9))
                            .lineLimit(3)
                    }
                    .padding(8)
                    .frame(width: 220, alignment: .topLeading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text("Select a vehicle to view telemetry.")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(telemetryCardBorderColor, lineWidth: 1.5)
        )
    }

    private var telemetryCardBorderColor: Color {
        guard let id = selectedVehicleID, let status = fleetLink.vehicleStatus(forVehicleID: id) else {
            return Color.white.opacity(0.08)
        }
        return status.color.uiColor.opacity(0.9)
    }

    private var selectedPickableVehicle: MissionPickableFleetVehicle? {
        guard let selectedVehicleID else { return nil }
        return pickableVehicles.first(where: { resolvedVehicleID(for: $0) == selectedVehicleID })
    }

    /// When selected vehicle is part of a live mission, prefer mission roster slot labeling.
    private var liveMissionRosterContext: (slotName: String, roleName: String?)? {
        guard let selectedVehicleID else { return nil }
        let activeRuns = missionControlStore.runs.filter { $0.status == .running || $0.status == .paused }
        for run in activeRuns {
            guard let assignment = run.assignments.first(where: {
                resolvedFleetStreamVehicleID(assignment: $0, fleetLink: fleetLink, sitl: sitl) == selectedVehicleID
            }) else { continue }
            let roleFromPlan = missionControlStore.paladinSessionsByRunID[run.id]?.plan.roleTracks
                .first(where: { $0.assignmentID == assignment.id })?
                .pathDisplayName
            return (assignment.slotName, roleFromPlan)
        }
        return nil
    }

    private func telemetryHeaderName(for vehicle: MissionPickableFleetVehicle) -> String {
        if let ctx = liveMissionRosterContext {
            return ctx.slotName
        }
        return vehicle.title
    }

    private func telemetryHeaderSubtitle(for vehicle: MissionPickableFleetVehicle) -> String {
        let idText = vehicle.vehicleShortID
        guard let ctx = liveMissionRosterContext else { return idText }
        if let role = ctx.roleName, !role.isEmpty {
            return "\(role) • \(idText)"
        }
        return idText
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(logHeaderTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(logSourceLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
            }

            ScrollView {
                Text(logText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.gray.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var logHeaderTitle: String {
        if selectedVehicleID == nil { return "Log" }
        return vehicleIsInLiveMission ? "Paladin Log" : "Vehicle Log"
    }

    private var logSourceLabel: String {
        vehicleIsInLiveMission ? "Mission" : "Direct"
    }

    private var vehicleIsInLiveMission: Bool {
        guard let id = selectedVehicleID else { return false }
        return missionControlStore.isVehicleStreamUsedInLiveMission(vehicleID: id, fleetLink: fleetLink, sitl: sitl)
    }

    private var logText: String {
        guard let vehicleID = selectedVehicleID else { return "No vehicle selected." }
        if vehicleIsInLiveMission {
            let sessions = missionControlStore.runs
                .filter { $0.status == .running || $0.status == .paused }
                .compactMap { missionControlStore.paladinSessionsByRunID[$0.id] }
            let lines = sessions.flatMap { session in
                session.events.map { $0.plainTextLine() }
            }
            return lines.isEmpty ? "No Paladin lines yet." : lines.joined(separator: "\n")
        }
        let lines = fleetLink.combinedLogs(filteredVehicleIDs: [vehicleID])
        return lines.isEmpty ? "No vehicle log lines yet." : lines.joined(separator: "\n")
    }

    private func resolvedVehicleID(for vehicle: MissionPickableFleetVehicle) -> String? {
        resolvedFleetStreamVehicleID(token: vehicle.token, fleetLink: fleetLink, sitl: sitl)
    }

    private func markerImageDataURL(forVehicleID vehicleID: String) -> String? {
        guard let vehicle = pickableVehicles.first(where: { resolvedVehicleID(for: $0) == vehicleID }),
              let names = vehicle.simulationImageBasenames,
              let image = SimulationDeviceBundleImage.nsImage(firstMatching: names),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    @ViewBuilder
    private func telemetryVehicleBadge(for vehicle: MissionPickableFleetVehicle) -> some View {
        if let names = vehicle.simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func telemetryPill(_ label: String, _ value: String, accent: Color = Color.white.opacity(0.04)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(accent.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func telemetryPrimaryBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var keyboardControlsEnabled: Bool {
        store.hasActiveSession && selectedVehicleID != nil
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        guard keyboardControlsEnabled,
              let action = mappedAction(for: event),
              let vehicleID = selectedVehicleID
        else { return false }

        let manual = ManualControlIntentCommand(
            intent: manualIntent(for: action),
            vehicleClass: selectedVehicleClass,
            stepProfile: manualControlSettings.stepProfile(for: selectedVehicleClass)
        )
        let source = "liveDrive.keyboard.\(action.rawValue)"
        _ = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: .manualControl(manual),
            source: source,
            category: .manualTakeover,
            onPaladinCommandOutcome: { outcome in
                switch outcome {
                case .succeeded:
                    lastKeyboardCommandText = "Keyboard: \(action.title)"
                    lastKeyboardCommandFailed = false
                case .failed(let detail):
                    lastKeyboardCommandText = "Keyboard \(action.title): \(detail)"
                    lastKeyboardCommandFailed = true
                }
            }
        )
        return true
    }

    private func mappedAction(for event: NSEvent) -> ManualControlAction? {
        let token = keyToken(for: event)
        return ManualControlAction.allCases.first {
            manualControlSettings.key(for: $0).caseInsensitiveCompare(token) == .orderedSame
        }
    }

    private func keyToken(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36, 76: return "Return"
        case 51, 117: return "Delete"
        default:
            let s = event.charactersIgnoringModifiers ?? ""
            return String(s.prefix(1)).uppercased()
        }
    }

    private func manualIntent(for action: ManualControlAction) -> ManualControlIntent {
        switch action {
        case .moveForward: return .moveForward
        case .moveLeft: return .moveLeft
        case .moveBackward: return .moveBackward
        case .moveRight: return .moveRight
        case .yawLeft: return .yawLeft
        case .yawRight: return .yawRight
        case .ascend: return .ascend
        case .descend: return .descend
        case .toggleArm: return .toggleArm
        case .engage: return .engage
        case .terminate: return .terminate
        }
    }

    private var selectedVehicleClass: UniversalVehicleClass {
        if let vehicle = selectedPickableVehicle {
            switch vehicle.domain {
            case .aerial:
                return .uav
            case .ground:
                return .ugv
            case .marine:
                return (vehicle.title.lowercased().contains("underwater") || vehicle.title.lowercased().contains("uuv")) ? .uuv : .usv
            }
        }
        if let mode = selectedHub?.flightMode.lowercased() {
            if mode.contains("sub") { return .uuv }
            if mode.contains("boat") || mode.contains("ship") { return .usv }
            if mode.contains("rover") || mode.contains("ground") { return .ugv }
        }
        return .unknown
    }
}

private enum LiveDriveMediaTab {
    case map
    case camera
}

private struct LiveDriveMarkerSignature: Equatable {
    let vehicleID: String?
    let lat: Double?
    let lon: Double?
    let headingDeg: Double?
}

private struct LiveDriveVehiclePickerSidebar: View {
    let vehicles: [MissionPickableFleetVehicle]
    let selectedVehicleID: String?
    let onSelect: (MissionPickableFleetVehicle) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("Select vehicle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))

            if vehicles.isEmpty {
                Spacer()
                Text("No vehicles available.")
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(vehicles) { vehicle in
                            Button {
                                onSelect(vehicle)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    ZStack(alignment: .topTrailing) {
                                        HStack(spacing: 14) {
                                            vehicleThumbnail(vehicle)
                                                .frame(width: 72, height: 56)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(vehicle.title)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .multilineTextAlignment(.leading)
                                                Text(vehicle.lifecycleStatus.mediumLabel)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(vehicle.lifecycleStatus.color.uiColor.opacity(0.95))
                                                    .lineLimit(1)
                                                Text(vehicle.vehicleShortID)
                                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                    .foregroundStyle(.gray)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }

                                        HStack(spacing: 8) {
                                            FleetAutopilotStackBadge(stack: vehicle.autopilotStack)
                                            FleetLiveSimBadge(isSimulation: vehicle.isSimulation)
                                            if isSelected(vehicle) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 0.12, green: 0.12, blue: 0.13))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(vehicle.lifecycleStatus.color.uiColor.opacity(0.7), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func isSelected(_ vehicle: MissionPickableFleetVehicle) -> Bool {
        guard let selectedVehicleID else { return false }
        let normalizedSelected = selectedVehicleID.replacingOccurrences(of: "sysid:", with: "")
        switch vehicle.token {
        case .live:
            return normalizedSelected == vehicle.vehicleIDText
        case .sitl:
            return normalizedSelected == vehicle.vehicleIDText
        }
    }

    @ViewBuilder
    private func vehicleThumbnail(_ vehicle: MissionPickableFleetVehicle) -> some View {
        if let names = vehicle.simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

}
