import Foundation

/// App-wide preferences for Training lab **transit runs** (``TrainingLabRunOrchestrator``).
enum TrainingLabRunPreferences {
    /// ``UserDefaults`` / ``AppStorage`` key for ``failRunOnFirstSquadFailure``.
    static let failRunOnFirstSquadFailureKey = "GuardianTraining.failRunOnFirstSquadFailure"

    /// When **true** (default), one squad drive failure ends the whole run and marks other squads aborted.
    /// When **false**, other squads keep driving; the run **succeeds** if the **learning** squad reaches the end formation.
    static var failRunOnFirstSquadFailure: Bool {
        get {
            if UserDefaults.standard.object(forKey: failRunOnFirstSquadFailureKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: failRunOnFirstSquadFailureKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: failRunOnFirstSquadFailureKey)
        }
    }
}
