import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunTelemetryNarrativePolicyTests: XCTestCase {
    func test_hubFlightModeSupportsMissionWaypointProgressNarrative_missionTrue() {
        XCTAssertTrue(MissionRunLoggingSubsystem.hubFlightModeSupportsMissionWaypointProgressNarrative(flightMode: "Mission"))
        XCTAssertTrue(MissionRunLoggingSubsystem.hubFlightModeSupportsMissionWaypointProgressNarrative(flightMode: "mission"))
    }

    func test_hubFlightModeSupportsMissionWaypointProgressNarrative_holdLandFalse() {
        XCTAssertFalse(MissionRunLoggingSubsystem.hubFlightModeSupportsMissionWaypointProgressNarrative(flightMode: "Hold"))
        XCTAssertFalse(MissionRunLoggingSubsystem.hubFlightModeSupportsMissionWaypointProgressNarrative(flightMode: "Land"))
        XCTAssertFalse(MissionRunLoggingSubsystem.hubFlightModeSupportsMissionWaypointProgressNarrative(flightMode: "returnToLaunch"))
    }

    func test_hubFlightModeSupportsMissionWaypointProgressNarrative_emptyFalse() {
        XCTAssertFalse(MissionRunLoggingSubsystem.hubFlightModeSupportsMissionWaypointProgressNarrative(flightMode: ""))
        XCTAssertFalse(MissionRunLoggingSubsystem.hubFlightModeSupportsMissionWaypointProgressNarrative(flightMode: "   "))
    }
}
