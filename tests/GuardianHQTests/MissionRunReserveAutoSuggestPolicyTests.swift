import XCTest
@testable import GuardianHQ

final class MissionRunReserveAutoSuggestPolicyTests: XCTestCase {

    func test_gating_blocksWhenSessionNotExecuting() {
        let g = MissionRunReserveAutoSuggestGatingSnapshot(
            runStatus: .running,
            sessionPhase: .recovery,
            taskState: .executing,
            taskAttemptState: nil,
            hasClassCompatibleFloatingReserve: true
        )
        XCTAssertFalse(MissionRunReserveAutoSuggestPolicy.gatingAllowsSuggest(g))
    }

    func test_gating_blocksWhenRunNotLive() {
        let g = MissionRunReserveAutoSuggestGatingSnapshot(
            runStatus: .setup,
            sessionPhase: .executing,
            taskState: .executing,
            taskAttemptState: nil,
            hasClassCompatibleFloatingReserve: true
        )
        XCTAssertFalse(MissionRunReserveAutoSuggestPolicy.gatingAllowsSuggest(g))
    }

    func test_gating_blocksWhenTaskWindDownAttemptPresent() {
        let g = MissionRunReserveAutoSuggestGatingSnapshot(
            runStatus: .running,
            sessionPhase: .executing,
            taskState: .executing,
            taskAttemptState: .abortWindDownIssued,
            hasClassCompatibleFloatingReserve: true
        )
        XCTAssertFalse(MissionRunReserveAutoSuggestPolicy.gatingAllowsSuggest(g))
    }

    func test_gating_blocksWhenTaskNotMidMission() {
        let g = MissionRunReserveAutoSuggestGatingSnapshot(
            runStatus: .running,
            sessionPhase: .executing,
            taskState: .recovery,
            taskAttemptState: nil,
            hasClassCompatibleFloatingReserve: true
        )
        XCTAssertFalse(MissionRunReserveAutoSuggestPolicy.gatingAllowsSuggest(g))
    }

    func test_gating_allowsExecutingBetweenWithReserve() {
        for state in [MissionTaskState.executing, .between] {
            let g = MissionRunReserveAutoSuggestGatingSnapshot(
                runStatus: .running,
                sessionPhase: .executing,
                taskState: state,
                taskAttemptState: nil,
                hasClassCompatibleFloatingReserve: true
            )
            XCTAssertTrue(MissionRunReserveAutoSuggestPolicy.gatingAllowsSuggest(g), "\(state)")
        }
    }

    func test_flightModeLooksLikeReturnHome_heuristics() {
        XCTAssertTrue(MissionRunReserveAutoSuggestPolicy.flightModeLooksLikeReturnHome("MAV_MODE.FIXED_WING.RETURN"))
        XCTAssertTrue(MissionRunReserveAutoSuggestPolicy.flightModeLooksLikeReturnHome("RTL"))
        XCTAssertTrue(MissionRunReserveAutoSuggestPolicy.flightModeLooksLikeReturnHome("Smart_RTL"))
        XCTAssertFalse(MissionRunReserveAutoSuggestPolicy.flightModeLooksLikeReturnHome("ALT_HOLD"))
    }

    func test_recentFleetDispatchFailure_scansTemplateKeys() {
        let now = Date()
        let vid = "ALPHA-1"
        let events: [MissionRunEvent] = [
            MissionRunEvent(
                at: now.addingTimeInterval(-10),
                level: .error,
                message: "x",
                templateKey: MissionRunLogTemplateKey.fleetAckFailed,
                templateParams: ["vehicleID": vid, "summary": "arm"]
            ),
        ]
        XCTAssertTrue(
            MissionRunReserveAutoSuggestPolicy.recentFleetDispatchFailure(
                events: events,
                vehicleID: vid,
                lookback: 60,
                now: now
            )
        )
        XCTAssertFalse(
            MissionRunReserveAutoSuggestPolicy.recentFleetDispatchFailure(
                events: events,
                vehicleID: "OTHER",
                lookback: 60,
                now: now
            )
        )
    }

    func test_gating_suggest_requires_floating_even_when_core_allows() {
        XCTAssertTrue(
            MissionRunReserveAutoSuggestPolicy.gatingAllowsReserveDistressAutomationCore(
                runStatus: .running,
                sessionPhase: .executing,
                taskState: .executing,
                taskAttemptState: nil
            )
        )
        let g = MissionRunReserveAutoSuggestGatingSnapshot(
            runStatus: .running,
            sessionPhase: .executing,
            taskState: .executing,
            taskAttemptState: nil,
            hasClassCompatibleFloatingReserve: false
        )
        XCTAssertFalse(MissionRunReserveAutoSuggestPolicy.gatingAllowsSuggest(g))
    }

    func test_first_distress_signal_reason_priority_link_stale_before_battery() {
        let signals = MissionRunReserveAutoSuggestSignalSnapshot(
            batteryTraffic: .critical,
            telemetryAgeS: 99,
            flightModeRaw: "RTL"
        )
        XCTAssertEqual(
            MissionRunReserveAutoSuggestPolicy.firstDistressSignalReason(
                signals: signals,
                recentFleetDispatchFailure: false,
                linkStaleThreshold: 45
            ),
            .linkStale
        )
    }

    func test_firstSuggestReason_priority_linkStaleBeforeBattery() {
        let gating = MissionRunReserveAutoSuggestGatingSnapshot(
            runStatus: .running,
            sessionPhase: .executing,
            taskState: .executing,
            taskAttemptState: nil,
            hasClassCompatibleFloatingReserve: true
        )
        let signals = MissionRunReserveAutoSuggestSignalSnapshot(
            batteryTraffic: .critical,
            telemetryAgeS: 99,
            flightModeRaw: "RTL"
        )
        XCTAssertEqual(
            MissionRunReserveAutoSuggestPolicy.firstSuggestReason(
                gating: gating,
                signals: signals,
                recentFleetDispatchFailure: false,
                linkStaleThreshold: 45
            ),
            .linkStale
        )
    }

    func test_firstSuggestReason_failureBeforeBattery() {
        let gating = MissionRunReserveAutoSuggestGatingSnapshot(
            runStatus: .running,
            sessionPhase: .executing,
            taskState: .executing,
            taskAttemptState: nil,
            hasClassCompatibleFloatingReserve: true
        )
        let signals = MissionRunReserveAutoSuggestSignalSnapshot(
            batteryTraffic: .warn,
            telemetryAgeS: 10,
            flightModeRaw: "ALT_HOLD"
        )
        XCTAssertEqual(
            MissionRunReserveAutoSuggestPolicy.firstSuggestReason(
                gating: gating,
                signals: signals,
                recentFleetDispatchFailure: true
            ),
            .recentFleetDispatchFailure
        )
    }

    func test_debounceAllowsToast_respectsLastFire() {
        let now = Date()
        XCTAssertTrue(
            MissionRunReserveAutoSuggestPolicy.debounceAllowsToast(lastToastAt: nil, debounce: 60, now: now)
        )
        XCTAssertFalse(
            MissionRunReserveAutoSuggestPolicy.debounceAllowsToast(
                lastToastAt: now.addingTimeInterval(-30),
                debounce: 60,
                now: now
            )
        )
        XCTAssertTrue(
            MissionRunReserveAutoSuggestPolicy.debounceAllowsToast(
                lastToastAt: now.addingTimeInterval(-70),
                debounce: 60,
                now: now
            )
        )
    }
}
