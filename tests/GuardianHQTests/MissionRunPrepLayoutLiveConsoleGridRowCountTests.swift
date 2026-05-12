import XCTest

@testable import GuardianHQ

final class MissionRunPrepLayoutLiveConsoleGridRowCountTests: XCTestCase {

    func test_zero_items_reserves_one_row_for_placeholder() {
        XCTAssertEqual(
            MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(itemCount: 0, slotsPerColumn: 3),
            1
        )
    }

    func test_one_item_one_row() {
        XCTAssertEqual(
            MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(itemCount: 1, slotsPerColumn: 3),
            1
        )
    }

    func test_two_items_use_two_rows_when_cap_is_three() {
        XCTAssertEqual(
            MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(itemCount: 2, slotsPerColumn: 3),
            2
        )
    }

    func test_three_items_fill_one_column() {
        XCTAssertEqual(
            MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(itemCount: 3, slotsPerColumn: 3),
            3
        )
    }

    func test_four_items_span_two_columns_needing_three_rows() {
        XCTAssertEqual(
            MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(itemCount: 4, slotsPerColumn: 3),
            3
        )
    }
}
