import Foundation

/// Formation / spacing policy for one Training lab squad (persists on ``TrainingLabSquad/id``, not on the primary row).
struct TrainingLabSquadFormationPolicy: Codable, Equatable, Sendable {
    var startFormation: MissionSquadFormationKind
    var startSpacing: MissionSquadFormationSpacing
    /// `nil` = auto (any formation allowed at end).
    var endFormation: MissionSquadFormationKind?
    /// `nil` = auto (any spacing allowed at end).
    var endSpacing: MissionSquadFormationSpacing?

    static let `default` = TrainingLabSquadFormationPolicy(
        startFormation: .arrowhead,
        startSpacing: .tight,
        endFormation: nil,
        endSpacing: nil
    )
}

/// Picker value for end formation (`auto` ↔ `nil` stored policy).
enum TrainingLabEndFormationChoice: String, CaseIterable, Identifiable, Equatable, Sendable {
    case auto
    case convoy
    case staggeredConvoy
    case chevron
    case arrowhead

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .auto: return "Auto"
        case .convoy: return MissionSquadFormationKind.convoy.displayTitle
        case .staggeredConvoy: return MissionSquadFormationKind.staggeredConvoy.displayTitle
        case .chevron: return MissionSquadFormationKind.chevron.displayTitle
        case .arrowhead: return MissionSquadFormationKind.arrowhead.displayTitle
        }
    }

    var resolved: MissionSquadFormationKind? {
        switch self {
        case .auto: return nil
        case .convoy: return .convoy
        case .staggeredConvoy: return .staggeredConvoy
        case .chevron: return .chevron
        case .arrowhead: return .arrowhead
        }
    }

    init(resolved: MissionSquadFormationKind?) {
        guard let resolved else {
            self = .auto
            return
        }
        self = TrainingLabEndFormationChoice(rawValue: resolved.rawValue) ?? .auto
    }
}

/// Picker value for end spacing (`auto` ↔ `nil` stored policy).
enum TrainingLabEndSpacingChoice: String, CaseIterable, Identifiable, Equatable, Sendable {
    case auto
    case tight
    case normal
    case loose

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .auto: return "Auto"
        case .tight: return MissionSquadFormationSpacing.tight.displayTitle
        case .normal: return MissionSquadFormationSpacing.normal.displayTitle
        case .loose: return MissionSquadFormationSpacing.loose.displayTitle
        }
    }

    var resolved: MissionSquadFormationSpacing? {
        switch self {
        case .auto: return nil
        case .tight: return .tight
        case .normal: return .normal
        case .loose: return .loose
        }
    }

    init(resolved: MissionSquadFormationSpacing?) {
        guard let resolved else {
            self = .auto
            return
        }
        self = TrainingLabEndSpacingChoice(rawValue: resolved.rawValue) ?? .auto
    }
}
