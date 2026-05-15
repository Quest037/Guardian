import Foundation

/// Viewport / recenter rules for hub-driven live maps (MC-R, Live Drive mission overlay, MCS staging).
enum GuardianMapLiveViewportPolicy {
    /// Live maps that receive hub-driven marker motion must keep ``GuardianRouteMapGeometry/preserveView`` `true`
    /// so Leaflet does not auto-fit on every telemetry tick. Use ``GuardianMapModel/focusMapFitBounds``,
    /// ``focusMapPanRetainZoom``, or ``recenter()`` for explicit operator framing.
    static let hubDrivenMapsRequirePreserveView = true

    /// Debug assertion when a live map applies hub markers with auto-fit enabled.
    static func assertHubDrivenPreserveViewIfNeeded(preserveView: Bool, surface: StaticString = #function) {
        #if DEBUG
        if hubDrivenMapsRequirePreserveView, !preserveView {
            assertionFailure(
                "Live map at \(surface) must set preserveView=true for hub-driven marker updates; use focusMapFitBounds/recenter for explicit framing."
            )
        }
        #endif
    }
}
