import XCTest
@testable import GuardianCore

final class GuardianGazeboOrphanBlitzTests: XCTestCase {
    func test_pgrepPatterns_includeGzLauncherAndRubySubcommands() {
        let patterns = GuardianGazeboOrphanBlitz.allPgrepPatternsForTesting()
        let joined = patterns.joined(separator: "\n")
        XCTAssertTrue(joined.contains("GazeboRuntime/bin/gz"))
        XCTAssertTrue(joined.contains("GazeboRuntime/lib/ruby/gz"))
        XCTAssertTrue(joined.contains("lib/ruby/gz/cmdsim"))
        XCTAssertTrue(joined.contains("gz sim server"))
        XCTAssertTrue(joined.contains("gz-launch"))
        XCTAssertTrue(joined.contains("libgz-launch-websocket-server"))
        XCTAssertTrue(joined.contains("gz-launch"))
        XCTAssertTrue(joined.contains("libgz-launch-websocket-server"))
    }

    func test_pgrepPatterns_includeResolvedRuntimeRubyPathWhenBundled() {
        guard let root = GazeboLaunchRecipe.runtimeRootPath() else {
            return
        }
        let patterns = GuardianGazeboOrphanBlitz.allPgrepPatternsForTesting()
        XCTAssertTrue(
            patterns.contains(where: { $0.contains(root) && $0.contains("lib/ruby/gz") })
        )
    }
}
