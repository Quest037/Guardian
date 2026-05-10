import Foundation
import Mavsdk

// MARK: - Stack identity

/// Autopilot stack a smoke test targets. Mirrors `FleetAutopilotStack` from the main
/// target but is intentionally re-declared here so this executable has zero dependency
/// on `GuardianHQ` — the smoke runner verifies wire-level autopilot behaviour, not our
/// Swift dispatch glue (the catalogue unit tests already cover that).
enum SmokeStack: String, Sendable, CaseIterable {
    case ardupilot
    case px4
}

// MARK: - Outcome

/// Result of one smoke test invocation. `skipped` is a first-class case — the runner
/// reports it distinctly from `passed` and `failed` so an operator can tell at a glance
/// whether coverage gaps are deliberate (`skipped(.stackDoesNotSupport)`) or accidental.
enum SmokeTestOutcome: Sendable {

    enum SkipReason: Sendable {
        /// This test's command surface is not implemented on the given stack
        /// (e.g. MAVSDK Calibration plugin against ArduPilot).
        case stackDoesNotSupport(String)
        /// Preconditions could not be established within the test's budget
        /// (e.g. no GPS fix, autopilot not reachable, parameter not present).
        case preconditionUnmet(String)
        /// Operator opt-out via env var / CLI flag.
        case operatorRequested(String)
    }

    case passed(detail: String?)
    case failed(reason: String)
    case skipped(reason: SkipReason)

    var isPassed: Bool {
        if case .passed = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var isSkipped: Bool {
        if case .skipped = self { return true }
        return false
    }
}

// MARK: - Context

/// Read-only view of the live MAVSDK session the runner hands each test. Tests are
/// pure functions of `(SmokeTestContext) async -> SmokeTestOutcome` so they compose,
/// can be run in any order, and never share global state.
struct SmokeTestContext {
    /// Stack of the autopilot behind ``drone``.
    let stack: SmokeStack
    /// Connected MAVSDK `Drone`. Already past the gRPC handshake.
    let drone: Drone
    /// Per-test wall-clock budget. Tests should bail out of long-running observables
    /// once this expires and return `.failed(reason:)` so a hung autopilot does not
    /// stall the rest of the suite.
    let testTimeout: TimeInterval

    /// Convenience: short label like `"AP"` / `"PX4"` for log lines.
    var stackLabel: String {
        switch stack {
        case .ardupilot: return "AP"
        case .px4:       return "PX4"
        }
    }
}

// MARK: - Protocol

/// Single smoke test. Implementations declare their identity, advertise which stacks
/// they apply to, and produce one ``SmokeTestOutcome`` per invocation.
///
/// Naming convention: `<catalogue-command-family>SmokeTest` — e.g. `ArmDisarmSmokeTest`
/// for `command.fleet.vehicle.do.arm` + `.do.disarm`. Each test header MUST cite the
/// catalogue commands it covers so the smoke suite stays linked to Layer 0.
protocol SmokeTest: Sendable {

    /// Stable identifier (e.g. `"arm.disarm"`). Used by the runner for log lines,
    /// filter flags, and the final summary table.
    var name: String { get }

    /// One-sentence human description that appears in the summary table.
    var description: String { get }

    /// Catalogue command literals this test smoke-covers. Documentation-only — the
    /// runner does not enforce uniqueness here, but reviewers should keep this set
    /// honest so coverage gaps surface in code review.
    var catalogueCoverage: [String] { get }

    /// Stacks this test applies to. The runner skips automatically (with
    /// `.skipped(.stackDoesNotSupport(...))`) when invoked against another stack.
    var supportedStacks: Set<SmokeStack> { get }

    /// Run the test against a live MAVSDK session. Must be safe to call repeatedly
    /// — the runner re-uses the same `Drone` across tests by design.
    func run(context: SmokeTestContext) async -> SmokeTestOutcome
}

extension SmokeTest {
    /// Convenience wrapper for tests that apply to every stack.
    var supportedStacks: Set<SmokeStack> { Set(SmokeStack.allCases) }
}
