import Foundation

/// WGS84 point lists for Leaflet ``guardianFitBoundsForPoints`` (MC-R, formations playground, any ``GuardianMapModel`` fit).
enum GuardianMapFitCoordinates {
    /// Drops unset `(0,0)`, non-finite values, and coordinates outside WGS84 so ``fitBounds`` is not stretched world-wide.
    static func isUsableWgs84ForMapFit(lat: Double, lon: Double) -> Bool {
        guard lat.isFinite, lon.isFinite else { return false }
        if lat == 0, lon == 0 { return false }
        return (-85 ... 85).contains(lat) && (-180 ... 180).contains(lon)
    }

    static func filterUsable(_ points: [(Double, Double)]) -> [(Double, Double)] {
        points.filter { isUsableWgs84ForMapFit(lat: $0.0, lon: $0.1) }
    }
}
