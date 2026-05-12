import SwiftUI

enum GuardianMapMarkerType: String, Codable {
    case vehicle
    case waypoint
    case home
    /// Mission template / map pin (rally, extraction) — distinct from route waypoints.
    case missionPoint
}

enum GuardianMapContextAction: String, Codable, CaseIterable {
    case followVehicle
    case stopFollowingVehicle
    case centerMarker
    case deleteWaypoint
    case deleteMissionPoint

    var title: String {
        switch self {
        case .followVehicle:
            return "Follow marker"
        case .stopFollowingVehicle:
            return "Stop following"
        case .centerMarker:
            return "Center map here"
        case .deleteWaypoint:
            return "Delete waypoint"
        case .deleteMissionPoint:
            return "Delete map point"
        }
    }
}

struct GuardianMapContextActionEvent {
    let action: GuardianMapContextAction
    let markerType: GuardianMapMarkerType
    let markerID: String?
    let lat: Double
    let lon: Double
}

/// Primary (single) click on a vehicle marker decoded from the Leaflet bridge.
struct GuardianMapVehiclePointerEvent: Equatable, Sendable {
    var markerID: String?
    var lat: Double
    var lon: Double
}

/// Primary or double click on a task route polyline when ``GuardianRouteMapGeometry/taskPathIDs`` aligns with ``allTasksCoords``.
struct GuardianMapTaskPathPointerEvent: Equatable, Sendable {
    var taskPathID: UUID
    var lat: Double
    var lon: Double
}

/// Primary or double click on the home circle marker.
struct GuardianMapHomePointerEvent: Equatable, Sendable {
    var lat: Double
    var lon: Double
}

struct GuardianMapContextMenuPolicy {
    var vehicleActions: [GuardianMapContextAction]
    var waypointActions: [GuardianMapContextAction]
    var homeActions: [GuardianMapContextAction]
    var missionPointActions: [GuardianMapContextAction]

    init(
        vehicleActions: [GuardianMapContextAction] = [],
        waypointActions: [GuardianMapContextAction] = [],
        homeActions: [GuardianMapContextAction] = [],
        missionPointActions: [GuardianMapContextAction] = []
    ) {
        self.vehicleActions = vehicleActions
        self.waypointActions = waypointActions
        self.homeActions = homeActions
        self.missionPointActions = missionPointActions
    }

    static let disabled = GuardianMapContextMenuPolicy()
}

/// One rally / extraction pin for Leaflet (mission editor or read-only previews).
struct GuardianMissionPointMapMarker: Equatable, Sendable {
    var id: UUID
    var lat: Double
    var lon: Double
    /// Unselected marker text (e.g. `1`); kind colour conveys rally vs extraction.
    var mapLabelCompact: String
    /// Selected marker text (e.g. `RP:1`).
    var mapLabelFull: String
    var kindRaw: String
    var isClosed: Bool
    var isSelected: Bool
}

/// Home, route polylines, editable waypoint overlay, and heading/camera previews — published as **one**
/// value from ``GuardianMapModel`` so route updates do not fan out into many ``ObservableObject``
/// notifications (each of which re-ran the WKWebView bridge).
struct GuardianRouteMapGeometry: Equatable {
    var home: RouteHome?
    var allTasksCoords: [[RouteCoordinate]]
    /// When `count` equals ``allTasksCoords``, each id labels the matching task polyline for ``GuardianMapView`` path tap callbacks. Otherwise the bridge does not attach path click handlers.
    var taskPathIDs: [UUID]
    var selectedTaskWaypoints: [RouteWaypoint]
    var selectedWaypointIndex: Int?
    var headingPreview: HeadingPreview?
    var cameraPreview: CameraPreview?
    var preserveView: Bool
    var isEditingTask: Bool
    /// Typed map pins (rally / extraction) — orthogonal to route waypoint editing.
    var missionPointMarkers: [GuardianMissionPointMapMarker]
    /// Mission editor: next map tap places a new mission point (mutually exclusive with route edit in UI).
    var missionPointPlacementArmed: Bool

    static let empty = GuardianRouteMapGeometry(
        home: nil,
        allTasksCoords: [],
        taskPathIDs: [],
        selectedTaskWaypoints: [],
        selectedWaypointIndex: nil,
        headingPreview: nil,
        cameraPreview: nil,
        preserveView: true,
        isEditingTask: false,
        missionPointMarkers: [],
        missionPointPlacementArmed: false
    )
}

/// One-shot viewport adjustment for ``OSMMapView`` (pan without zoom change, or fit bounds).
struct GuardianMapViewportNudge: Equatable {
    enum Kind: Equatable {
        /// Leaflet `panTo` — keeps the current zoom level.
        case panRetainZoom(lat: Double, lon: Double)
        /// Fit the map to the given WGS84 points (Leaflet ``fitBounds`` via ``guardianFitBoundsForPoints``).
        case fitBounds(points: [(Double, Double)])

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case (.panRetainZoom(let la, let lo), .panRetainZoom(let ra, let ro)):
                return la == ra && lo == ro
            case (.fitBounds(let lp), .fitBounds(let rp)):
                guard lp.count == rp.count else { return false }
                return zip(lp, rp).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            default:
                return false
            }
        }
    }

    /// Monotonic per-request id so repeating the same coordinate still re-fires JS.
    var sequence: UInt64
    var kind: Kind
}

/// Shared, observable state for a Leaflet-backed `OSMMapView`. One source of truth
/// for tile style, content (home / paths / waypoints / vehicle markers / previews),
/// and recenter requests, so call sites can `pull in` a single model instead of
/// passing ~14 individual arguments to `OSMMapView`.
@MainActor
final class GuardianMapModel: ObservableObject {
    @Published var mapStyle: MapTileStyle
    @Published var routeGeometry: GuardianRouteMapGeometry
    @Published var vehicleMarkers: [MapVehicleMarker]
    @Published var followedVehicleMarkerID: String?

    /// Bumping this nonce asks `OSMMapView`'s JS side to re-fit / recenter on the
    /// next render even when `preserveView` is `true`.
    @Published private(set) var recenterNonce: Int = 0

    /// Optional viewport nudge evaluated in ``OSMMapView`` (does not change ``recenterNonce`` / mission payload).
    @Published private(set) var viewportNudge: GuardianMapViewportNudge?
    private var viewportNudgeSequence: UInt64 = 0

    init(
        mapStyle: MapTileStyle = .standard,
        routeGeometry: GuardianRouteMapGeometry = .empty,
        vehicleMarkers: [MapVehicleMarker] = [],
        followedVehicleMarkerID: String? = nil
    ) {
        self.mapStyle = mapStyle
        self.routeGeometry = routeGeometry
        self.vehicleMarkers = vehicleMarkers
        self.followedVehicleMarkerID = followedVehicleMarkerID
        self.viewportNudge = nil
    }

    /// Convenience for call sites that only need to set ``GuardianRouteMapGeometry/preserveView``.
    convenience init(mapStyle: MapTileStyle = .standard, preserveView: Bool) {
        var geo = GuardianRouteMapGeometry.empty
        geo.preserveView = preserveView
        self.init(mapStyle: mapStyle, routeGeometry: geo)
    }

    /// Force the next map update to re-fit bounds / recenter (used by the toolbar
    /// reset button and by callers that change selection, etc.).
    func recenter() { recenterNonce &+= 1 }

    /// Pan the map centre to ``lat``/``lon`` without changing zoom (MC-R triage shortcuts).
    func focusMapPanRetainZoom(lat: Double, lon: Double) {
        viewportNudgeSequence &+= 1
        viewportNudge = GuardianMapViewportNudge(sequence: viewportNudgeSequence, kind: .panRetainZoom(lat: lat, lon: lon))
    }

    /// Fit the map viewport to the bounding box of ``points`` (empty → no-op).
    func focusMapFitBounds(points: [(Double, Double)]) {
        guard !points.isEmpty else { return }
        viewportNudgeSequence &+= 1
        viewportNudge = GuardianMapViewportNudge(sequence: viewportNudgeSequence, kind: .fitBounds(points: points))
    }

    /// Toggle between OSM standard and Esri satellite tiles.
    func toggleStyle() {
        mapStyle = (mapStyle == .standard) ? .satellite : .standard
    }
}

// MARK: - Toolbar configuration

/// One extra button rendered in the vertical map toolbar that sits directly
/// underneath Leaflet's default zoom (+/-) control in the top-left corner.
struct GuardianMapToolbarButton: Identifiable {
    let id: String
    let systemImage: String
    let help: String
    let action: () -> Void
}

/// Flag-driven config for the left-side toolbar overlay. Mirrors the
/// "include certain things by default" pattern from `Modal`.
///
/// The toolbar is **on by default** with the style toggle and recenter/reset
/// buttons enabled — callers can opt out individually (e.g.
/// `GuardianMapToolbarOptions(showResetButton: false)`) or kill the whole
/// toolbar with `GuardianMapToolbarOptions(enabled: false)`.
struct GuardianMapToolbarOptions {
    /// Master switch — when `false` the overlay is never rendered, even if
    /// individual buttons are flagged on.
    var enabled: Bool

    /// Built-in: tile-style toggle (standard ⇄ satellite).
    var showStyleButton: Bool

    /// Built-in: recenter / fit-to-content reset.
    var showResetButton: Bool

    /// Caller-supplied buttons appended after the built-ins.
    var extraButtons: [GuardianMapToolbarButton]

    init(
        enabled: Bool = true,
        showStyleButton: Bool = true,
        showResetButton: Bool = true,
        extraButtons: [GuardianMapToolbarButton] = []
    ) {
        self.enabled = enabled
        self.showStyleButton = showStyleButton
        self.showResetButton = showResetButton
        self.extraButtons = extraButtons
    }

    var hasAnyVisibleButton: Bool {
        enabled && (showStyleButton || showResetButton || !extraButtons.isEmpty)
    }
}

// MARK: - View

/// Shared SwiftUI wrapper around `OSMMapView`. Reads everything from a
/// `GuardianMapModel` so call sites can be written as
/// `GuardianMapView(model: mapModel, toolbar: .standard)` and gain the
/// optional toolbar overlay (style / reset / custom buttons) without
/// rewriting any per-screen plumbing.
struct GuardianMapView: View {
    @ObservedObject var model: GuardianMapModel
    var toolbar: GuardianMapToolbarOptions
    var contextMenuPolicy: GuardianMapContextMenuPolicy
    var onMapClick: (Double, Double) -> Void
    var onVehicleMarkerMoved: (String, Double, Double) -> Void
    var onContextAction: (GuardianMapContextActionEvent) -> Void
    var onWaypointClick: (Int) -> Void
    var onWaypointMoved: (Int, Double, Double) -> Void
    var onWaypointDelete: (Int) -> Void
    var onTaskMapInsert: (Int, Double, Double) -> Void
    var onMissionPointClick: (UUID) -> Void
    var onMissionPointMoved: (UUID, Double, Double) -> Void
    var onMissionPointDoubleClick: (UUID) -> Void
    var onVehicleTap: (GuardianMapVehiclePointerEvent) -> Void
    var onVehicleDoubleTap: (GuardianMapVehiclePointerEvent) -> Void
    var onTaskPathTap: (GuardianMapTaskPathPointerEvent) -> Void
    var onTaskPathDoubleTap: (GuardianMapTaskPathPointerEvent) -> Void
    var onHomeTap: (GuardianMapHomePointerEvent) -> Void
    var onHomeDoubleTap: (GuardianMapHomePointerEvent) -> Void
    /// Fired when the map viewport center changes (debounced on the JS side).
    var onViewportCenterChanged: (Double, Double) -> Void

    init(
        model: GuardianMapModel,
        toolbar: GuardianMapToolbarOptions = GuardianMapToolbarOptions(),
        contextMenuPolicy: GuardianMapContextMenuPolicy = .disabled,
        onMapClick: @escaping (Double, Double) -> Void = { _, _ in },
        onVehicleMarkerMoved: @escaping (String, Double, Double) -> Void = { _, _, _ in },
        onContextAction: @escaping (GuardianMapContextActionEvent) -> Void = { _ in },
        onWaypointClick: @escaping (Int) -> Void = { _ in },
        onWaypointMoved: @escaping (Int, Double, Double) -> Void = { _, _, _ in },
        onWaypointDelete: @escaping (Int) -> Void = { _ in },
        onTaskMapInsert: @escaping (Int, Double, Double) -> Void = { _, _, _ in },
        onMissionPointClick: @escaping (UUID) -> Void = { _ in },
        onMissionPointMoved: @escaping (UUID, Double, Double) -> Void = { _, _, _ in },
        onMissionPointDoubleClick: @escaping (UUID) -> Void = { _ in },
        onVehicleTap: @escaping (GuardianMapVehiclePointerEvent) -> Void = { _ in },
        onVehicleDoubleTap: @escaping (GuardianMapVehiclePointerEvent) -> Void = { _ in },
        onTaskPathTap: @escaping (GuardianMapTaskPathPointerEvent) -> Void = { _ in },
        onTaskPathDoubleTap: @escaping (GuardianMapTaskPathPointerEvent) -> Void = { _ in },
        onHomeTap: @escaping (GuardianMapHomePointerEvent) -> Void = { _ in },
        onHomeDoubleTap: @escaping (GuardianMapHomePointerEvent) -> Void = { _ in },
        onViewportCenterChanged: @escaping (Double, Double) -> Void = { _, _ in }
    ) {
        self.model = model
        self.toolbar = toolbar
        self.contextMenuPolicy = contextMenuPolicy
        self.onMapClick = onMapClick
        self.onVehicleMarkerMoved = onVehicleMarkerMoved
        self.onContextAction = onContextAction
        self.onWaypointClick = onWaypointClick
        self.onWaypointMoved = onWaypointMoved
        self.onWaypointDelete = onWaypointDelete
        self.onTaskMapInsert = onTaskMapInsert
        self.onMissionPointClick = onMissionPointClick
        self.onMissionPointMoved = onMissionPointMoved
        self.onMissionPointDoubleClick = onMissionPointDoubleClick
        self.onVehicleTap = onVehicleTap
        self.onVehicleDoubleTap = onVehicleDoubleTap
        self.onTaskPathTap = onTaskPathTap
        self.onTaskPathDoubleTap = onTaskPathDoubleTap
        self.onHomeTap = onHomeTap
        self.onHomeDoubleTap = onHomeDoubleTap
        self.onViewportCenterChanged = onViewportCenterChanged
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            OSMMapView(
                home: model.routeGeometry.home,
                allTasksCoords: model.routeGeometry.allTasksCoords,
                taskPathIDs: model.routeGeometry.taskPathIDs,
                selectedTaskWaypoints: model.routeGeometry.selectedTaskWaypoints,
                selectedWaypointIndex: model.routeGeometry.selectedWaypointIndex,
                vehicleMarkers: model.vehicleMarkers,
                mapStyle: model.mapStyle,
                recenterNonce: model.recenterNonce,
                viewportNudge: model.viewportNudge,
                headingPreview: model.routeGeometry.headingPreview,
                cameraPreview: model.routeGeometry.cameraPreview,
                followedVehicleMarkerID: model.followedVehicleMarkerID,
                preserveView: model.routeGeometry.preserveView,
                isEditingTask: model.routeGeometry.isEditingTask,
                missionPointMarkers: model.routeGeometry.missionPointMarkers,
                missionPointPlacementArmed: model.routeGeometry.missionPointPlacementArmed,
                contextMenuPolicy: contextMenuPolicy,
                onMapClick: onMapClick,
                onVehicleMarkerMoved: onVehicleMarkerMoved,
                onContextAction: onContextAction,
                onWaypointClick: onWaypointClick,
                onWaypointMoved: onWaypointMoved,
                onWaypointDelete: onWaypointDelete,
                onTaskMapInsert: onTaskMapInsert,
                onMissionPointClick: onMissionPointClick,
                onMissionPointMoved: onMissionPointMoved,
                onMissionPointDoubleClick: onMissionPointDoubleClick,
                onVehicleTap: onVehicleTap,
                onVehicleDoubleTap: onVehicleDoubleTap,
                onTaskPathTap: onTaskPathTap,
                onTaskPathDoubleTap: onTaskPathDoubleTap,
                onHomeTap: onHomeTap,
                onHomeDoubleTap: onHomeDoubleTap,
                onViewportCenterChanged: onViewportCenterChanged
            )

            if toolbar.hasAnyVisibleButton {
                GuardianMapToolbarOverlay(model: model, toolbar: toolbar)
                    // Pinned 10pt from the leading edge (matches Leaflet's
                    // top-left margin) and 85pt from the top, which leaves
                    // a 10pt visual gap below the default zoom +/- control
                    // (touch-sized: 2x30 + 1pt divider + 2x2pt border = 65pt,
                    // plus the 10pt outer margin = 75pt zoom-bar bottom) so
                    // the new buttons "carry on" from the same column.
                    .padding(.leading, GuardianSpacing.denseGutter)
                    .padding(.top, GuardianSpacing.mapAttributionClearance)
                    .allowsHitTesting(true)
            }
        }
    }
}

// MARK: - Toolbar overlay

/// Renders the vertical toolbar to look like a second `.leaflet-bar`: 33x33
/// white buttons stacked with 1pt gray dividers, wrapped in a 4pt rounded
/// 2pt-bordered container with a tight drop shadow that matches Leaflet's
/// default `box-shadow: 0 1px 5px rgba(0,0,0,0.65)`.
private struct GuardianMapToolbarOverlay: View {
    @ObservedObject var model: GuardianMapModel
    let toolbar: GuardianMapToolbarOptions

    private static let buttonSize: CGFloat = 33
    private static let iconSize: CGFloat = 13
    private static let cornerRadius: CGFloat = 4
    private static let dividerColor = Color.black.opacity(0.2)
    private static let outerBorderColor = Color.black.opacity(0.2)

    var body: some View {
        VStack(spacing: 0) {
            let visible = visibleButtons
            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, btn in
                if idx > 0 {
                    Rectangle()
                        .fill(Self.dividerColor)
                        .frame(width: Self.buttonSize, height: 1)
                }
                Button(action: btn.action) {
                    Image(systemName: btn.systemImage)
                        .font(GuardianTypography.relativeFixed(size: Self.iconSize, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .help(btn.help)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Self.outerBorderColor, lineWidth: 2)
        )
        .guardianDropShadow(GuardianElevation.mapToolbarBezel)
    }

    private var visibleButtons: [GuardianMapToolbarButton] {
        var out: [GuardianMapToolbarButton] = []
        if toolbar.showStyleButton {
            out.append(
                GuardianMapToolbarButton(
                    id: "style",
                    systemImage: model.mapStyle == .satellite ? "map" : "globe.americas.fill",
                    help: model.mapStyle == .satellite
                        ? "Switch to standard tiles"
                        : "Switch to satellite tiles",
                    action: { [model] in model.toggleStyle() }
                )
            )
        }
        if toolbar.showResetButton {
            out.append(
                GuardianMapToolbarButton(
                    id: "reset",
                    systemImage: "scope",
                    help: "Recenter map",
                    action: { [model] in model.recenter() }
                )
            )
        }
        out.append(contentsOf: toolbar.extraButtons)
        return out
    }
}
