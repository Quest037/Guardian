import XCTest

@testable import GuardianCore

final class MissionRunSimCleanupConcurrencyTests: XCTestCase {

    func test_resolveMaxConcurrent_missingKey_returnsDefault() {
        XCTAssertEqual(
            MissionRunSimCleanupConcurrency.resolveMaxConcurrent([:]),
            MissionRunSimCleanupConcurrency.defaultMaxConcurrentPerWave
        )
    }

    func test_resolveMaxConcurrent_validInteger() {
        let env = [MissionRunSimCleanupConcurrency.envKey: "7"]
        XCTAssertEqual(MissionRunSimCleanupConcurrency.resolveMaxConcurrent(env), 7)
    }

    func test_resolveMaxConcurrent_one_isMinimum() {
        let env = [MissionRunSimCleanupConcurrency.envKey: "1"]
        XCTAssertEqual(MissionRunSimCleanupConcurrency.resolveMaxConcurrent(env), 1)
    }

    func test_resolveMaxConcurrent_zero_fallsBackToDefault() {
        let env = [MissionRunSimCleanupConcurrency.envKey: "0"]
        XCTAssertEqual(
            MissionRunSimCleanupConcurrency.resolveMaxConcurrent(env),
            MissionRunSimCleanupConcurrency.defaultMaxConcurrentPerWave
        )
    }

    func test_resolveMaxConcurrent_negative_fallsBackToDefault() {
        let env = [MissionRunSimCleanupConcurrency.envKey: "-3"]
        XCTAssertEqual(
            MissionRunSimCleanupConcurrency.resolveMaxConcurrent(env),
            MissionRunSimCleanupConcurrency.defaultMaxConcurrentPerWave
        )
    }

    func test_resolveMaxConcurrent_nonNumeric_fallsBackToDefault() {
        let env = [MissionRunSimCleanupConcurrency.envKey: "twenty"]
        XCTAssertEqual(
            MissionRunSimCleanupConcurrency.resolveMaxConcurrent(env),
            MissionRunSimCleanupConcurrency.defaultMaxConcurrentPerWave
        )
    }

    func test_resolveMaxConcurrent_whitespaceTrimmed() {
        let env = [MissionRunSimCleanupConcurrency.envKey: "  4  "]
        XCTAssertEqual(MissionRunSimCleanupConcurrency.resolveMaxConcurrent(env), 4)
    }

    func test_resolveMaxConcurrent_clampsToAbsoluteMax() {
        let env = [MissionRunSimCleanupConcurrency.envKey: "9999"]
        XCTAssertEqual(MissionRunSimCleanupConcurrency.resolveMaxConcurrent(env), MissionRunSimCleanupConcurrency.resolvedWaveCap)
    }
}
