import SwiftUI
import XCTest

@testable import GuardianCore

@MainActor
final class GuardianPulsingSkeletonBlocksTests: XCTestCase {
    func test_skeleton_views_compile_in_test_target() {
        _ = AnyView(GuardianPulsingSkeletonBar(height: 10))
        _ = AnyView(GuardianPulsingSkeletonBlockStack(rows: [(height: 8, widthFraction: 0.5)]))
        _ = AnyView(MissionLiveTaskTriageOverlaySkeleton())
    }
}
