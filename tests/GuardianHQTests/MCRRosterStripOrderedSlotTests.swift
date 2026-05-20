import XCTest
@testable import GuardianCore

final class MCRRosterStripOrderedSlotTests: XCTestCase {
    func test_orderedSlot_identity_isAssignmentUUID() {
        let u = UUID()
        let s = MCRRosterStripOrderedSlot(id: u)
        XCTAssertEqual(s.id, u)
    }
}
