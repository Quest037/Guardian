import Foundation

internal enum MissionTelemetryGeo {
    static func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dlon = (lon2 - lon1) * .pi / 180
        let y = sin(dlon) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dlon)
        let t = atan2(y, x) * 180 / .pi
        return (t + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDifferenceDeg(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { return d - 360 }
        if d < -180 { return d + 360 }
        return d
    }

    static func horizontalDistanceM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dphi = (lat2 - lat1) * .pi / 180
        let dlam = (lon2 - lon1) * .pi / 180
        let a = sin(dphi / 2) * sin(dphi / 2) + cos(p1) * cos(p2) * sin(dlam / 2) * sin(dlam / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}
