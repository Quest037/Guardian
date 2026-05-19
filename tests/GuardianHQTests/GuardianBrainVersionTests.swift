import XCTest

@testable import GuardianHQ

final class GuardianBrainVersionTests: XCTestCase {
    func test_semverString_and_displayLabel() {
        let version = GuardianBrainVersion(major: 0, minor: 3, patch: 45)
        XCTAssertEqual(version.semverString, "0.3.45")
        XCTAssertEqual(version.majorLineCodename, "subodai")
        XCTAssertEqual(version.displayLabel, "subodai · 0.3.45")
    }

    func test_major_line_codenames() {
        XCTAssertEqual(GuardianBrainMajorLines.codename(forMajor: 0), "subodai")
        XCTAssertEqual(GuardianBrainMajorLines.codename(forMajor: 1), "caesar")
        XCTAssertEqual(GuardianBrainMajorLines.codename(forMajor: 2), "sikander")
    }

    func test_bumped_patch_minor_major() {
        let base = GuardianBrainVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(base.bumped(.patch), GuardianBrainVersion(major: 1, minor: 2, patch: 4))
        XCTAssertEqual(base.bumped(.minor), GuardianBrainVersion(major: 1, minor: 3, patch: 0))
        XCTAssertEqual(base.bumped(.major), GuardianBrainVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(base.bumped(.major).majorLineCodename, "sikander")
    }

    func test_decode_legacy_integer_as_subodai_line() throws {
        let data = Data("12".utf8)
        let version = try JSONDecoder().decode(GuardianBrainVersion.self, from: data)
        XCTAssertEqual(version, GuardianBrainVersion(major: 0, minor: 0, patch: 12))
    }

    func test_decode_encode_semver_string() throws {
        let version = GuardianBrainVersion(major: 3, minor: 2, patch: 45)
        let data = try JSONEncoder().encode(version)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"3.2.45\"")
        let decoded = try JSONDecoder().decode(GuardianBrainVersion.self, from: data)
        XCTAssertEqual(decoded, version)
    }

    func test_comparable_orders_semver() {
        XCTAssertTrue(GuardianBrainVersion(major: 0, minor: 9, patch: 99) < GuardianBrainVersion(major: 1, minor: 0, patch: 0))
        XCTAssertTrue(GuardianBrainVersion(major: 1, minor: 2, patch: 3) < GuardianBrainVersion(major: 1, minor: 2, patch: 4))
    }
}
