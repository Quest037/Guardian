import XCTest
@testable import GuardianHQ

/// Documents hover cursor push/pop balance for ``GuardianPointerHoverCursorModifier`` (logic kept inline in the modifier).
final class GuardianPointerHoverCursorStateTests: XCTestCase {
    private struct HoverCursorState {
        private(set) var isHovering = false

        mutating func hoverChanged(_ hovering: Bool) -> Bool {
            guard hovering != isHovering else { return false }
            isHovering = hovering
            return true
        }

        mutating func disappearWhileHovering() -> Bool {
            guard isHovering else { return false }
            isHovering = false
            return true
        }
    }

    func test_hoverEnterExit_balanced() {
        var state = HoverCursorState()
        XCTAssertTrue(state.hoverChanged(true))
        XCTAssertTrue(state.isHovering)
        XCTAssertTrue(state.hoverChanged(false))
        XCTAssertFalse(state.isHovering)
    }

    func test_disappearWhileHovering_requiresPop() {
        var state = HoverCursorState()
        XCTAssertTrue(state.hoverChanged(true))
        XCTAssertTrue(state.disappearWhileHovering())
        XCTAssertFalse(state.isHovering)
        XCTAssertFalse(state.disappearWhileHovering())
    }
}
