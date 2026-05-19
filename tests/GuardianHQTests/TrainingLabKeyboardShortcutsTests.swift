import XCTest

@testable import GuardianHQ

final class TrainingLabKeyboardShortcutsTests: XCTestCase {
    func test_panelTab_shortcuts_use_command_digits_one_through_four() {
        XCTAssertEqual(TrainingLabKeyboardShortcuts.panelTab(.map).key, KeyEquivalent("1"))
        XCTAssertEqual(TrainingLabKeyboardShortcuts.panelTab(.vehicles).key, KeyEquivalent("2"))
        XCTAssertEqual(TrainingLabKeyboardShortcuts.panelTab(.training).key, KeyEquivalent("3"))
        XCTAssertEqual(TrainingLabKeyboardShortcuts.panelTab(.logs).key, KeyEquivalent("4"))
        XCTAssertTrue(TrainingLabKeyboardShortcuts.panelTab(.map).modifiers.contains(.command))
    }

    func test_catalogSummaryLines_lists_run_escape_and_tabs() {
        let joined = TrainingLabKeyboardShortcuts.catalogSummaryLines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Return"))
        XCTAssertTrue(joined.contains("Escape"))
        XCTAssertTrue(joined.contains("⌘1"))
    }
}
