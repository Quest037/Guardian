import Foundation

/// Pushes Training lab squad formation slot overlays into the embedded gzweb viewer.
@MainActor
final class GazeboWebViewportFormationSlotsBridge: ObservableObject {
    @Published private(set) var tick = UUID()
    @Published private(set) var squads: [TrainingLabSquad] = []
    @Published var editSquadID: UUID?
    @Published var zones: WorldBuilderZonesSnapshot = .empty
    @Published var mapHalfExtentM: Double = 500

    func clear() {
        squads = []
        editSquadID = nil
        zones = .empty
        tick = UUID()
    }

    func push(
        squads: [TrainingLabSquad],
        editSquadID: UUID?,
        zones: WorldBuilderZonesSnapshot,
        mapHalfExtentM: Double
    ) {
        self.squads = squads
        self.editSquadID = editSquadID
        self.zones = zones
        self.mapHalfExtentM = mapHalfExtentM
        tick = UUID()
    }

    var javaScriptExpression: String {
        let payload = FormationSlotsJSState(
            mapHalfExtentM: mapHalfExtentM,
            zones: zones,
            editSquadID: editSquadID?.uuidString,
            squads: squads.enumerated().map { index, squad in
                FormationSlotsJSSquad.make(squad: squad, squadIndex: index, zones: zones)
            }
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            return "window.guardianViewer?.setFormationSlotEditorState?.({})"
        }
        let b64 = data.base64EncodedString()
        return """
        (function () {
          if (!window.guardianViewer?.setFormationSlotEditorState) return false;
          const state = JSON.parse(atob('\(b64)'));
          return window.guardianViewer.setFormationSlotEditorState(state);
        })()
        """
    }
}

private struct FormationSlotsJSState: Encodable {
    var mapHalfExtentM: Double
    var zones: WorldBuilderZonesSnapshot
    var editSquadID: String?
    var squads: [FormationSlotsJSSquad]
}

private struct FormationSlotsJSSquad: Encodable {
    var id: String
    var label: String
    var colorHex: String
    var start: FormationSlotsJSGroup?
    var end: FormationSlotsJSGroup?

    static func make(
        squad: TrainingLabSquad,
        squadIndex: Int,
        zones: WorldBuilderZonesSnapshot
    ) -> FormationSlotsJSSquad {
        let colorHex = TrainingLabSquadFormationPalette.colorHex(squadIndex: squadIndex)
        let label = TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex)
        return FormationSlotsJSSquad(
            id: squad.id.uuidString,
            label: label,
            colorHex: colorHex,
            start: zones.start.placed
                ? groupJS(
                    squad: squad,
                    squadIndex: squadIndex,
                    phase: .start,
                    zone: zones.start,
                    anchor: squad.startZoneAnchor ?? .seeded(in: zones.start)
                )
                : nil,
            end: zones.end.placed
                ? groupJS(
                    squad: squad,
                    squadIndex: squadIndex,
                    phase: .end,
                    zone: zones.end,
                    anchor: squad.endZoneAnchor ?? .seeded(in: zones.end)
                )
                : nil
        )
    }

    private static func groupJS(
        squad: TrainingLabSquad,
        squadIndex: Int,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        zone: WorldBuilderZoneState,
        anchor: TrainingLabZoneFormationAnchor
    ) -> FormationSlotsJSGroup {
        let layout = TrainingLabFormationSlotGeometry.groupLayout(
            squad: squad,
            squadIndex: squadIndex,
            phase: phase,
            anchor: anchor
        )
        return FormationSlotsJSGroup(
            centerXM: layout.anchor.centerXM,
            centerYM: layout.anchor.centerYM,
            headingDeg: layout.anchor.headingDeg,
            circleRadiusM: layout.circleRadiusM,
            slots: layout.slots.map {
                FormationSlotsJSSlot(
                    index: $0.slotIndex,
                    isPrimary: $0.isPrimary,
                    centerXM: $0.centerXM,
                    centerYM: $0.centerYM,
                    headingDeg: $0.headingDeg,
                    widthM: $0.widthM,
                    lengthM: $0.lengthM
                )
            }
        )
    }
}

private struct FormationSlotsJSGroup: Encodable {
    var centerXM: Double
    var centerYM: Double
    var headingDeg: Double
    var circleRadiusM: Double
    var slots: [FormationSlotsJSSlot]
}

private struct FormationSlotsJSSlot: Encodable {
    var index: Int
    var isPrimary: Bool
    var centerXM: Double
    var centerYM: Double
    var headingDeg: Double
    var widthM: Double
    var lengthM: Double
}
