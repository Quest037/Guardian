import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LiveDriveStore: ObservableObject {
    /// Vehicle currently inspected in Live Drive (map/log/telemetry/camera).
    @Published var activeVehicleID: String?

    /// Session in progress (`endedAt == nil`).
    @Published private(set) var activeSessionRecord: LiveDriveSessionRecord?

    /// Finished sessions on this vehicle, chronological oldest → newest.
    @Published private(set) var completedSessions: [LiveDriveSessionRecord] = []

    var hasActiveSession: Bool {
        guard let activeSessionRecord, activeSessionRecord.isActive else { return false }
        return true
    }

    /// Vehicle IDs currently reserved by an active LD control session (legacy VehiclesView checks).
    var activeControlledVehicleID: String? {
        guard let activeSessionRecord, activeSessionRecord.isActive else { return nil }
        return activeSessionRecord.vehicleID
    }

    func selectVehicle(_ vehicleID: String?) {
        guard vehicleID != activeVehicleID else {
            activeVehicleID = vehicleID
            syncPaladinLiveDriveDomainSnapshot()
            return
        }
        activeVehicleID = vehicleID
        resetAllSessionArtifacts()
        syncPaladinLiveDriveDomainSnapshot()
    }

    /// Clear vehicle row when no session; also drops all in-memory session exports/history.
    func clearActiveVehicleIfIdle() {
        guard activeSessionRecord == nil else { return }
        activeVehicleID = nil
        resetAllSessionArtifacts()
        syncPaladinLiveDriveDomainSnapshot()
    }

    func beginTrackedSession(record: LiveDriveSessionRecord) {
        activeSessionRecord = record
        syncPaladinLiveDriveDomainSnapshot()
    }

    /// Slice vehicle log buffer from `logBufferStartIndex`; merge with any in-memory lines; close record and append to history.
    func finalizeActiveSession(vehicleLogLinesSnapshot: [String]) {
        guard var rec = activeSessionRecord, rec.isActive else {
            activeSessionRecord = nil
            syncPaladinLiveDriveDomainSnapshot()
            return
        }
        rec.endedAt = Date()
        let suffix: [String]
        if rec.logBufferStartIndex <= vehicleLogLinesSnapshot.count {
            suffix = Array(vehicleLogLinesSnapshot.dropFirst(rec.logBufferStartIndex))
        } else {
            suffix = []
        }
        rec.sessionLogLines = suffix
        activeSessionRecord = nil
        completedSessions.append(rec)
        syncPaladinLiveDriveDomainSnapshot()
    }

    func discardActiveSessionRecording() {
        activeSessionRecord = nil
        syncPaladinLiveDriveDomainSnapshot()
    }

    func appendActiveSessionEvent(_ event: LiveDriveSessionEvent) {
        guard var rec = activeSessionRecord, rec.isActive else { return }
        rec.events.append(event)
        activeSessionRecord = rec
        syncPaladinLiveDriveDomainSnapshot()
    }

    /// Export completed sessions for the current vehicle stint to JSON (`NSSavePanel`).
    func promptExportCompletedSessionsToJSON(activeVehicleIDForMeta: String?) -> Bool {
        guard !completedSessions.isEmpty else { return false }
        let env = LiveDriveSessionExportEnvelope(
            exportSchemaVersion: LiveDriveSessionExportEnvelope.currentSchemaVersion,
            exportedAt: Date(),
            activeVehicleID: activeVehicleIDForMeta,
            completedSessions: completedSessions
        )
        guard let data = try? JSONEncoder.guardianLiveDriveEncoder.encode(env) else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "LiveDrive-sessions-\(ISO8601DateFormatter().string(from: Date()).prefix(19)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func resetAllSessionArtifacts() {
        activeSessionRecord = nil
        completedSessions.removeAll()
    }

    private func syncPaladinLiveDriveDomainSnapshot() {
        PaladinEngine.shared.liveDriveDomainBridge().refreshLiveDriveAssistSnapshot(
            hasActiveSession: hasActiveSession,
            takeoverEligibleVehicleCount: activeVehicleID == nil ? 0 : 1
        )
    }
}

extension JSONEncoder {
    static var guardianLiveDriveEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
