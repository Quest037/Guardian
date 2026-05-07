import SwiftUI

struct VehicleTelemetryInfoSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case raw = "Raw"
        var id: String { rawValue }
    }

    let title: String
    let vehicleID: String?
    /// SITL session id when opened from a sim row; shown in Summary only.
    let sitlSessionUUID: String?
    let model: FleetVehicleModel?
    let hub: FleetHubVehicleTelemetry?
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .summary

    var body: some View {
        GuardianModalTemplate(
            title: title,
            headerActions: {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 170)

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().opacity(0.2)
                    ScrollView {
                        if mode == .summary, let model {
                            VStack(alignment: .leading, spacing: 12) {
                                summarySection("Vehicle", rows: summaryVehicleRows(model: model))
                                summarySection("Flight", rows: summaryFlightRows(model: model))
                                summarySection("Power", rows: summaryPowerRows(model: model))
                                summarySection("Navigation", rows: summaryNavigationRows(model: model))
                                summarySection("Status", rows: summaryStatusRows(model: model))
                            }
                        } else if let hub {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(telemetryRows(from: hub), id: \.0) { row in
                                    telemetryRow(name: row.0, value: row.1)
                                }
                            }
                        } else {
                            Text("No telemetry available for this vehicle stream.")
                                .font(.system(size: 12))
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
        )
        .frame(minWidth: 760, minHeight: 520)
    }

    private func summarySection(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            ForEach(rows, id: \.0) { row in
                telemetryRow(name: row.0, value: row.1)
            }
        }
        .padding(.bottom, 4)
    }

    private func telemetryRow(name: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.gray)
                .frame(width: 240, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
            Spacer(minLength: 0)
        }
    }

    private func summaryVehicleRows(model: FleetVehicleModel) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Autopilot", model.data.telemetry?.autopilotStack.displayName ?? "Unknown"),
            ("Vehicle ID", vehicleID ?? "—"),
            ("System ID", model.data.systemID.map(String.init) ?? "—"),
            ("Last Update", formattedTimestamp(model.data.telemetry?.lastUpdate)),
        ]
        if let sitlSessionUUID, !sitlSessionUUID.isEmpty {
            rows.append(("Session UUID", sitlSessionUUID))
        }
        return rows
    }

    private func summaryFlightRows(model: FleetVehicleModel) -> [(String, String)] {
        let t = model.data.telemetry
        return [
            ("Mode", t?.flightMode.isEmpty == false ? (t?.flightMode ?? "—") : "—"),
            ("Armed", (t?.isArmed ?? false) ? "Yes" : "No"),
            ("Altitude", formattedMeters(t?.absoluteAltM)),
            ("Relative Alt", formattedMeters(t?.relativeAltM)),
        ]
    }

    private func summaryPowerRows(model: FleetVehicleModel) -> [(String, String)] {
        let p = model.collections.operational.battery
        return [
            ("Battery", p.percent0to100.map { "\(Int(round($0)))%" } ?? "—"),
            ("Voltage", p.voltageV.map { String(format: "%.1f V", $0) } ?? "—"),
            ("Current", p.currentA.map { String(format: "%.1f A", $0) } ?? "—"),
            ("Time Left", p.etaText.replacingOccurrences(of: "ETA ", with: "")),
        ]
    }

    private func summaryNavigationRows(model: FleetVehicleModel) -> [(String, String)] {
        let t = model.data.telemetry
        return [
            ("GPS", model.collections.operational.gps.titleText.replacingOccurrences(of: "GPS ", with: "")),
            ("Movement", model.collections.operational.movement.titleText),
            ("Position", formattedLatLon(lat: t?.latitudeDeg, lon: t?.longitudeDeg)),
        ]
    }

    private func summaryStatusRows(model: FleetVehicleModel) -> [(String, String)] {
        let lifecycle = model.collections.lifecycleStatus
        return [
            ("Lifecycle", lifecycle.mediumLabel),
            ("State", lifecycle.shortLabel),
            ("Meaning", lifecycle.sentence),
        ]
    }

    private func formattedMeters(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(round(value))) m"
    }

    private func formattedLatLon(lat: Double?, lon: Double?) -> String {
        guard let lat, let lon, lat.isFinite, lon.isFinite else { return "—" }
        return String(format: "%.5f, %.5f", lat, lon)
    }

    private func formattedTimestamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }

    private func telemetryRows(from hub: FleetHubVehicleTelemetry) -> [(String, String)] {
        Mirror(reflecting: hub).children.compactMap { child in
            guard let label = child.label else { return nil }
            let value = formattedRawValue(child.value)
            if value == "nil" { return nil }
            return (label, value)
        }
        .sorted { $0.0 < $1.0 }
    }

    private func formattedRawValue(_ value: Any) -> String {
        let rendered = String(describing: value)
        if rendered.hasPrefix("Optional("), rendered.hasSuffix(")") {
            let inner = rendered.dropFirst("Optional(".count).dropLast()
            return String(inner)
        }
        return rendered
    }
}
