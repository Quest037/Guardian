import SwiftUI

/// Shared, observable state for a Leaflet-backed `OSMMapView`. One source of truth
/// for tile style, content (home / paths / waypoints / vehicle markers / previews),
/// and recenter requests, so call sites can `pull in` a single model instead of
/// passing ~14 individual arguments to `OSMMapView`.
@MainActor
final class GuardianMapModel: ObservableObject {
    @Published var mapStyle: MapTileStyle
    @Published var preserveView: Bool
    @Published var isEditingPath: Bool

    @Published var home: RouteHome?
    @Published var allPathsCoords: [[RouteCoordinate]]
    @Published var selectedPathWaypoints: [RouteWaypoint]
    @Published var selectedWaypointIndex: Int?
    @Published var vehicleMarkers: [MapVehicleMarker]
    @Published var headingPreview: HeadingPreview?
    @Published var cameraPreview: CameraPreview?

    /// Bumping this nonce asks `OSMMapView`'s JS side to re-fit / recenter on the
    /// next render even when `preserveView` is `true`.
    @Published private(set) var recenterNonce: Int = 0

    init(
        mapStyle: MapTileStyle = .standard,
        preserveView: Bool = true,
        isEditingPath: Bool = false,
        home: RouteHome? = nil,
        allPathsCoords: [[RouteCoordinate]] = [],
        selectedPathWaypoints: [RouteWaypoint] = [],
        selectedWaypointIndex: Int? = nil,
        vehicleMarkers: [MapVehicleMarker] = [],
        headingPreview: HeadingPreview? = nil,
        cameraPreview: CameraPreview? = nil
    ) {
        self.mapStyle = mapStyle
        self.preserveView = preserveView
        self.isEditingPath = isEditingPath
        self.home = home
        self.allPathsCoords = allPathsCoords
        self.selectedPathWaypoints = selectedPathWaypoints
        self.selectedWaypointIndex = selectedWaypointIndex
        self.vehicleMarkers = vehicleMarkers
        self.headingPreview = headingPreview
        self.cameraPreview = cameraPreview
    }

    /// Force the next map update to re-fit bounds / recenter (used by the toolbar
    /// reset button and by callers that change selection, etc.).
    func recenter() { recenterNonce &+= 1 }

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
/// "include certain things by default" pattern from `GuardianModalTemplate`.
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
    var onMapClick: (Double, Double) -> Void
    var onVehicleMarkerMoved: (String, Double, Double) -> Void
    var onWaypointClick: (Int) -> Void
    var onWaypointMoved: (Int, Double, Double) -> Void
    var onWaypointDelete: (Int) -> Void
    var onPathInsert: (Int, Double, Double) -> Void

    init(
        model: GuardianMapModel,
        toolbar: GuardianMapToolbarOptions = GuardianMapToolbarOptions(),
        onMapClick: @escaping (Double, Double) -> Void = { _, _ in },
        onVehicleMarkerMoved: @escaping (String, Double, Double) -> Void = { _, _, _ in },
        onWaypointClick: @escaping (Int) -> Void = { _ in },
        onWaypointMoved: @escaping (Int, Double, Double) -> Void = { _, _, _ in },
        onWaypointDelete: @escaping (Int) -> Void = { _ in },
        onPathInsert: @escaping (Int, Double, Double) -> Void = { _, _, _ in }
    ) {
        self.model = model
        self.toolbar = toolbar
        self.onMapClick = onMapClick
        self.onVehicleMarkerMoved = onVehicleMarkerMoved
        self.onWaypointClick = onWaypointClick
        self.onWaypointMoved = onWaypointMoved
        self.onWaypointDelete = onWaypointDelete
        self.onPathInsert = onPathInsert
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            OSMMapView(
                home: model.home,
                allPathsCoords: model.allPathsCoords,
                selectedPathWaypoints: model.selectedPathWaypoints,
                selectedWaypointIndex: model.selectedWaypointIndex,
                vehicleMarkers: model.vehicleMarkers,
                mapStyle: model.mapStyle,
                recenterNonce: model.recenterNonce,
                headingPreview: model.headingPreview,
                cameraPreview: model.cameraPreview,
                preserveView: model.preserveView,
                isEditingPath: model.isEditingPath,
                onMapClick: onMapClick,
                onVehicleMarkerMoved: onVehicleMarkerMoved,
                onWaypointClick: onWaypointClick,
                onWaypointMoved: onWaypointMoved,
                onWaypointDelete: onWaypointDelete,
                onPathInsert: onPathInsert
            )

            if toolbar.hasAnyVisibleButton {
                GuardianMapToolbarOverlay(model: model, toolbar: toolbar)
                    // Pinned 10pt from the leading edge (matches Leaflet's
                    // top-left margin) and 85pt from the top, which leaves
                    // a 10pt visual gap below the default zoom +/- control
                    // (touch-sized: 2x30 + 1pt divider + 2x2pt border = 65pt,
                    // plus the 10pt outer margin = 75pt zoom-bar bottom) so
                    // the new buttons "carry on" from the same column.
                    .padding(.leading, 10)
                    .padding(.top, 85)
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
                        .font(.system(size: Self.iconSize, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(btn.help)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Self.outerBorderColor, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 1, x: 0, y: 1)
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
