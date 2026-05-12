import XCTest

@testable import GuardianHQ

@MainActor
final class GuardianBottomPromptCenterTripleChoiceTests: XCTestCase {

    func test_presentTripleChoice_sets_trio_buttons() {
        let c = GuardianBottomPromptCenter()
        c.presentTripleChoice(
            "Probe failed",
            cancelTitle: "Cancel",
            switchTitle: "Switch",
            inspectTitle: "Inspect",
            onCancel: {},
            onSwitchPoolRow: {},
            onOpenVehicleInspector: {}
        )
        guard let p = c.activePrompt else {
            XCTFail("expected active prompt")
            return
        }
        guard case .trio(let cancel, let sw, let ins) = p.buttons else {
            XCTFail("expected trio buttons, got \(p.buttons)")
            return
        }
        XCTAssertEqual(cancel, "Cancel")
        XCTAssertEqual(sw, "Switch")
        XCTAssertEqual(ins, "Inspect")
    }

    func test_trio_cancel_invokes_callback_and_clears_prompt() {
        let c = GuardianBottomPromptCenter()
        var n = 0
        c.presentTripleChoice(
            "x",
            cancelTitle: "Cancel",
            switchTitle: "Switch",
            inspectTitle: "Inspect",
            onCancel: { n += 1 },
            onSwitchPoolRow: {},
            onOpenVehicleInspector: {}
        )
        c.trioCancelTapped()
        XCTAssertEqual(n, 1)
        XCTAssertNil(c.activePrompt)
    }

    func test_trio_switch_invokes_callback() {
        let c = GuardianBottomPromptCenter()
        var n = 0
        c.presentTripleChoice(
            "x",
            cancelTitle: "Cancel",
            switchTitle: "Switch",
            inspectTitle: "Inspect",
            onCancel: {},
            onSwitchPoolRow: { n += 7 },
            onOpenVehicleInspector: {}
        )
        c.trioSwitchTapped()
        XCTAssertEqual(n, 7)
        XCTAssertNil(c.activePrompt)
    }

    func test_trio_inspect_invokes_callback() {
        let c = GuardianBottomPromptCenter()
        var n = 0
        c.presentTripleChoice(
            "x",
            cancelTitle: "Cancel",
            switchTitle: "Switch",
            inspectTitle: "Inspect",
            onCancel: {},
            onSwitchPoolRow: {},
            onOpenVehicleInspector: { n += 3 }
        )
        c.trioInspectTapped()
        XCTAssertEqual(n, 3)
        XCTAssertNil(c.activePrompt)
    }

    func test_presentChoice_clears_prior_trio_callbacks() {
        let c = GuardianBottomPromptCenter()
        var cancelCalls = 0
        c.presentTripleChoice(
            "t",
            cancelTitle: "Cancel",
            switchTitle: "Switch",
            inspectTitle: "Inspect",
            onCancel: { cancelCalls += 1 },
            onSwitchPoolRow: {},
            onOpenVehicleInspector: {}
        )
        c.presentChoice("pair", confirmTitle: "OK", dismissTitle: "No", onConfirm: {}, onDismiss: nil)
        c.trioCancelTapped()
        XCTAssertEqual(cancelCalls, 0)
    }
}
