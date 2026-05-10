import Foundation
import SwiftUI

struct FleetCalibrationMarkerAnchor: Equatable {
    let imageAnchor: UnitPoint
    let labelPoint: UnitPoint
}

enum FleetCalibrationAnchorCatalog {
    private struct RawAnchor: Decodable {
        let anchor: [CGFloat]
        let label: [CGFloat]
    }

    private static let fallbackAnchors: [FleetCalibrationSystemID: FleetCalibrationMarkerAnchor] = [
        .compass: .init(imageAnchor: UnitPoint(x: 0.52, y: 0.22), labelPoint: UnitPoint(x: 0.82, y: 0.16)),
        .accelerometer: .init(imageAnchor: UnitPoint(x: 0.48, y: 0.50), labelPoint: UnitPoint(x: 0.14, y: 0.38)),
        .gyrometer: .init(imageAnchor: UnitPoint(x: 0.55, y: 0.50), labelPoint: UnitPoint(x: 0.86, y: 0.42)),
        .gps: .init(imageAnchor: UnitPoint(x: 0.50, y: 0.16), labelPoint: UnitPoint(x: 0.18, y: 0.14)),
        .localPosition: .init(imageAnchor: UnitPoint(x: 0.42, y: 0.58), labelPoint: UnitPoint(x: 0.14, y: 0.62)),
        .homePosition: .init(imageAnchor: UnitPoint(x: 0.58, y: 0.58), labelPoint: UnitPoint(x: 0.86, y: 0.64)),
        .rc: .init(imageAnchor: UnitPoint(x: 0.64, y: 0.40), labelPoint: UnitPoint(x: 0.86, y: 0.30)),
        .battery: .init(imageAnchor: UnitPoint(x: 0.50, y: 0.68), labelPoint: UnitPoint(x: 0.22, y: 0.84)),
        .barometer: .init(imageAnchor: UnitPoint(x: 0.42, y: 0.44), labelPoint: UnitPoint(x: 0.12, y: 0.24)),
        .ekf: .init(imageAnchor: UnitPoint(x: 0.58, y: 0.44), labelPoint: UnitPoint(x: 0.84, y: 0.82)),
    ]

    private static let loadedAnchors: [FleetVehicleType: [FleetCalibrationSystemID: FleetCalibrationMarkerAnchor]] = {
        guard let data = loadAnchorData(),
              let raw = try? JSONDecoder().decode([String: [String: RawAnchor]].self, from: data)
        else {
            return [:]
        }

        var parsed: [FleetVehicleType: [FleetCalibrationSystemID: FleetCalibrationMarkerAnchor]] = [:]
        for (vehicleTypeRaw, anchorsByID) in raw {
            guard let vehicleType = FleetVehicleType(rawValue: vehicleTypeRaw) else { continue }
            parsed[vehicleType] = anchorsByID.reduce(into: [:]) { result, pair in
                guard pair.value.anchor.count == 2, pair.value.label.count == 2 else { return }
                result[FleetCalibrationSystemID(rawValue: pair.key)] = FleetCalibrationMarkerAnchor(
                    imageAnchor: UnitPoint(x: clamp(pair.value.anchor[0]), y: clamp(pair.value.anchor[1])),
                    labelPoint: UnitPoint(x: clamp(pair.value.label[0]), y: clamp(pair.value.label[1]))
                )
            }
        }
        return parsed
    }()

    static func anchor(for systemID: FleetCalibrationSystemID, vehicleType: FleetVehicleType) -> FleetCalibrationMarkerAnchor {
        loadedAnchors[vehicleType]?[systemID]
            ?? fallbackAnchors[systemID]
            ?? FleetCalibrationMarkerAnchor(imageAnchor: UnitPoint(x: 0.5, y: 0.5), labelPoint: UnitPoint(x: 0.84, y: 0.5))
    }

    private static func loadAnchorData() -> Data? {
        let resource = "FleetCalibrationAnchors.json"
        let bundles = [Bundle.module, Bundle.main]
        for bundle in bundles {
            if let url = bundle.url(forResource: "FleetCalibrationAnchors", withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                return data
            }
            let rootURL = bundle.bundleURL.appendingPathComponent("Resources").appendingPathComponent(resource)
            if let data = try? Data(contentsOf: rootURL) {
                return data
            }
            let directURL = bundle.bundleURL.appendingPathComponent(resource)
            if let data = try? Data(contentsOf: directURL) {
                return data
            }
        }
        return nil
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}
