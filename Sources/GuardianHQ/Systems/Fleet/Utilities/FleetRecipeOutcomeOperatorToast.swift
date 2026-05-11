import Foundation

/// Short ``ToastCenter`` copy for catalogue recipe completion — same shape for Vehicle Inspector, MCR, LiveDrive.
enum FleetRecipeOutcomeOperatorToast {

    struct Presentation: Equatable, Sendable {
        let message: String
        let style: GuardianFeedbackSeverity
        let duration: TimeInterval
    }

    /// One line, no raw runner tails. Use ``FleetRecipeOutcome/trace`` and logs when you need detail.
    static func presentation(recipeHumanLabel: String, outcome: FleetRecipeOutcome) -> Presentation {
        switch outcome {
        case .succeeded:
            return Presentation(message: "\(recipeHumanLabel) — done.", style: .success, duration: 3)

        case .failed(_, _, let detail, _):
            let d = detail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if d == "cancelled" || d.contains("operator aborted") {
                return Presentation(message: "Stopped.", style: .info, duration: 2.8)
            }
            return Presentation(message: "\(recipeHumanLabel) — couldn't complete.", style: .error, duration: 4)
        }
    }
}
