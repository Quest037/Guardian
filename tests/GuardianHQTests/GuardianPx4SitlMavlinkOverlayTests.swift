import XCTest
@testable import GuardianHQ

final class GuardianPx4SitlMavlinkOverlayTests: XCTestCase {
    func test_bundled_px4_rc_mavlink_honors_guardian_env() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "px4-rc",
                withExtension: "mavlink",
                subdirectory: "Px4SitlMavlink"
            )
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("GUARDIAN_PX4_OFFBOARD_PORT_REMOTE"))
        XCTAssertTrue(text.contains("GUARDIAN_PX4_GCS_PORT_LOCAL"))
    }

    func test_px4Spec_env_keys_are_documented_constants() {
        XCTAssertEqual(
            SitlLaunchRecipe.px4OffboardPortRemoteEnvKey,
            "GUARDIAN_PX4_OFFBOARD_PORT_REMOTE"
        )
        XCTAssertEqual(SitlLaunchRecipe.px4GcsPortLocalEnvKey, "GUARDIAN_PX4_GCS_PORT_LOCAL")
    }
}
