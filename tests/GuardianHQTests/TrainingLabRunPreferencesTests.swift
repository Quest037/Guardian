import XCTest
@testable import GuardianCore

final class TrainingLabRunPreferencesTests: XCTestCase {
    private let key = TrainingLabRunPreferences.failRunOnFirstSquadFailureKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func test_failRunOnFirstSquadFailure_defaultsTrueWhenUnset() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(TrainingLabRunPreferences.failRunOnFirstSquadFailure)
    }

    func test_failRunOnFirstSquadFailure_persistsFalse() {
        TrainingLabRunPreferences.failRunOnFirstSquadFailure = false
        XCTAssertFalse(TrainingLabRunPreferences.failRunOnFirstSquadFailure)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }
}
