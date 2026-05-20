import XCTest
@testable import GuardianCore

/// Stage D item 3 coverage for the operator-prompt delivery-target catalogue:
/// the closed enum shape, the contextual / broadcast / out-of-app / archive
/// role flags, the `Kind` discriminator round-trip, and the `accepts(eventTarget:)`
/// matching contract every router check funnels through.
final class OperatorPromptDeliveryTargetTests: XCTestCase {

    // MARK: - Kind discriminator

    func test_kind_isStableForEveryCase() {
        let runID = UUID()
        let vehicleID = "ALPHA-1"
        let recipeRunID = FleetRecipeRunID()

        XCTAssertEqual(OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: runID).kind, .mcrPromptPanel)
        XCTAssertEqual(OperatorPromptDeliveryTarget.liveDrivePromptPanel(missionRunID: runID, vehicleID: vehicleID).kind, .liveDrivePromptPanel)
        XCTAssertEqual(
            OperatorPromptDeliveryTarget.vehicleInspectorWizardPanel(vehicleID: vehicleID, recipeRunID: recipeRunID).kind,
            .vehicleInspectorWizardPanel
        )
        XCTAssertEqual(OperatorPromptDeliveryTarget.persistentToast.kind, .persistentToast)
        XCTAssertEqual(OperatorPromptDeliveryTarget.userNotification(style: .banner).kind, .userNotification)
        XCTAssertEqual(OperatorPromptDeliveryTarget.userNotification(style: .mcrCriticalReturn).kind, .userNotification)
        XCTAssertEqual(OperatorPromptDeliveryTarget.inAppInbox.kind, .inAppInbox)
    }

    func test_kind_rawValuesAreStable() {
        // Locked: changing these breaks audit-log indexes.
        XCTAssertEqual(OperatorPromptDeliveryTarget.Kind.mcrPromptPanel.rawValue, "mcrPromptPanel")
        XCTAssertEqual(OperatorPromptDeliveryTarget.Kind.liveDrivePromptPanel.rawValue, "liveDrivePromptPanel")
        XCTAssertEqual(OperatorPromptDeliveryTarget.Kind.vehicleInspectorWizardPanel.rawValue, "vehicleInspectorWizardPanel")
        XCTAssertEqual(OperatorPromptDeliveryTarget.Kind.persistentToast.rawValue, "persistentToast")
        XCTAssertEqual(OperatorPromptDeliveryTarget.Kind.userNotification.rawValue, "userNotification")
        XCTAssertEqual(OperatorPromptDeliveryTarget.Kind.inAppInbox.rawValue, "inAppInbox")
    }

    func test_kind_codableRoundTrip() throws {
        for kind in OperatorPromptDeliveryTarget.Kind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(OperatorPromptDeliveryTarget.Kind.self, from: data)
            XCTAssertEqual(decoded, kind, "Kind \(kind) must round-trip via Codable.")
        }
    }

    // MARK: - Role flags

    func test_isContextual_isTrueForPanels_falseForBroadcastChannels() {
        XCTAssertTrue(OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: UUID()).isContextual)
        XCTAssertTrue(OperatorPromptDeliveryTarget.liveDrivePromptPanel(vehicleID: "V").isContextual)
        XCTAssertTrue(OperatorPromptDeliveryTarget.vehicleInspectorWizardPanel(vehicleID: "V").isContextual)

        XCTAssertFalse(OperatorPromptDeliveryTarget.persistentToast.isContextual)
        XCTAssertFalse(OperatorPromptDeliveryTarget.userNotification(style: .banner).isContextual)
        XCTAssertFalse(OperatorPromptDeliveryTarget.inAppInbox.isContextual)
    }

    func test_isBroadcast_isTheInverseOfIsContextual() {
        let targets: [OperatorPromptDeliveryTarget] = [
            .mcrPromptPanel(missionRunID: UUID()),
            .liveDrivePromptPanel(vehicleID: "V"),
            .vehicleInspectorWizardPanel(vehicleID: "V"),
            .persistentToast,
            .userNotification(style: .banner),
            .inAppInbox,
        ]
        for target in targets {
            XCTAssertEqual(target.isBroadcast, !target.isContextual, "Broadcast must be the inverse of contextual for \(target.kind.rawValue).")
        }
    }

    func test_isOutOfApp_isTrueOnlyForUserNotification() {
        XCTAssertTrue(OperatorPromptDeliveryTarget.userNotification(style: .banner).isOutOfApp)
        XCTAssertTrue(OperatorPromptDeliveryTarget.userNotification(style: .mcrCriticalReturn).isOutOfApp)

        XCTAssertFalse(OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: UUID()).isOutOfApp)
        XCTAssertFalse(OperatorPromptDeliveryTarget.liveDrivePromptPanel(vehicleID: "V").isOutOfApp)
        XCTAssertFalse(OperatorPromptDeliveryTarget.vehicleInspectorWizardPanel(vehicleID: "V").isOutOfApp)
        XCTAssertFalse(OperatorPromptDeliveryTarget.persistentToast.isOutOfApp)
        XCTAssertFalse(OperatorPromptDeliveryTarget.inAppInbox.isOutOfApp)
    }

    func test_isUniversalArchive_isTrueOnlyForInAppInbox() {
        XCTAssertTrue(OperatorPromptDeliveryTarget.inAppInbox.isUniversalArchive)

        XCTAssertFalse(OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: UUID()).isUniversalArchive)
        XCTAssertFalse(OperatorPromptDeliveryTarget.liveDrivePromptPanel(vehicleID: "V").isUniversalArchive)
        XCTAssertFalse(OperatorPromptDeliveryTarget.vehicleInspectorWizardPanel(vehicleID: "V").isUniversalArchive)
        XCTAssertFalse(OperatorPromptDeliveryTarget.persistentToast.isUniversalArchive)
        XCTAssertFalse(OperatorPromptDeliveryTarget.userNotification(style: .banner).isUniversalArchive)
    }

    // MARK: - accepts(eventTarget:) — MCR

    func test_accepts_mcrPanel_requiresMatchingRunID() {
        let runA = UUID()
        let runB = UUID()
        let target = OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: runA)

        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: runA)))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: runB)))
        XCTAssertFalse(target.accepts(eventTarget: .unspecified))
    }

    // MARK: - accepts(eventTarget:) — LiveDrive

    func test_accepts_liveDrive_runOnly_matchesOnRunID() {
        let runID = UUID()
        let target = OperatorPromptDeliveryTarget.liveDrivePromptPanel(missionRunID: runID, vehicleID: nil)

        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: runID)))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID())))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "V")))
    }

    func test_accepts_liveDrive_vehicleOnly_matchesOnVehicleID() {
        let target = OperatorPromptDeliveryTarget.liveDrivePromptPanel(missionRunID: nil, vehicleID: "ALPHA-1")

        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "ALPHA-1")))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "BRAVO-2")))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID())))
    }

    func test_accepts_liveDrive_bothFieldsSet_requiresBothToMatch() {
        let runID = UUID()
        let target = OperatorPromptDeliveryTarget.liveDrivePromptPanel(missionRunID: runID, vehicleID: "ALPHA-1")

        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: runID, affectedVehicleID: "ALPHA-1")))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: runID, affectedVehicleID: "BRAVO-2")))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID(), affectedVehicleID: "ALPHA-1")))
    }

    func test_accepts_liveDrive_bothFieldsNil_refusesEverything() {
        // Type catalogue guards against a fully-unaddressed LiveDrive target
        // silently broadcasting. Router must always supply at least one
        // discriminator.
        let target = OperatorPromptDeliveryTarget.liveDrivePromptPanel(missionRunID: nil, vehicleID: nil)

        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID())))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "V")))
        XCTAssertFalse(target.accepts(eventTarget: .unspecified))
    }

    // MARK: - accepts(eventTarget:) — Vehicle Inspector wizard

    func test_accepts_vehicleInspector_runNil_acceptsAnyRecipeRunForVehicle() {
        let target = OperatorPromptDeliveryTarget.vehicleInspectorWizardPanel(vehicleID: "ALPHA-1", recipeRunID: nil)

        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "ALPHA-1")))
        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(
            affectedVehicleID: "ALPHA-1",
            recipeRunID: FleetRecipeRunID()
        )))
    }

    func test_accepts_vehicleInspector_runSet_requiresMatchingRecipeRunID() {
        let runA = FleetRecipeRunID()
        let runB = FleetRecipeRunID()
        let target = OperatorPromptDeliveryTarget.vehicleInspectorWizardPanel(vehicleID: "ALPHA-1", recipeRunID: runA)

        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "ALPHA-1", recipeRunID: runA)))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "ALPHA-1", recipeRunID: runB)))
        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "ALPHA-1")))
    }

    func test_accepts_vehicleInspector_rejectsMismatchedVehicle() {
        let target = OperatorPromptDeliveryTarget.vehicleInspectorWizardPanel(vehicleID: "ALPHA-1")

        XCTAssertFalse(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "BRAVO-2")))
        XCTAssertFalse(target.accepts(eventTarget: .unspecified))
    }

    // MARK: - accepts(eventTarget:) — broadcast channels

    func test_accepts_persistentToast_acceptsEveryEvent() {
        let target = OperatorPromptDeliveryTarget.persistentToast
        XCTAssertTrue(target.accepts(eventTarget: .unspecified))
        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID())))
    }

    func test_accepts_userNotification_acceptsEveryEvent() {
        let banner = OperatorPromptDeliveryTarget.userNotification(style: .banner)
        let critical = OperatorPromptDeliveryTarget.userNotification(style: .mcrCriticalReturn)

        XCTAssertTrue(banner.accepts(eventTarget: .unspecified))
        XCTAssertTrue(banner.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID())))
        XCTAssertTrue(critical.accepts(eventTarget: .unspecified))
        XCTAssertTrue(critical.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID())))
    }

    func test_accepts_inAppInbox_acceptsEveryEvent() {
        let target = OperatorPromptDeliveryTarget.inAppInbox
        XCTAssertTrue(target.accepts(eventTarget: .unspecified))
        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(missionRunID: UUID())))
        XCTAssertTrue(target.accepts(eventTarget: OperatorPromptTarget(affectedVehicleID: "V")))
    }

    // MARK: - UserNotification style

    func test_userNotificationStyle_codableRoundTripForEveryCase() throws {
        for style in OperatorPromptUserNotificationStyle.allCases {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(OperatorPromptUserNotificationStyle.self, from: data)
            XCTAssertEqual(decoded, style)
        }
    }

    func test_userNotificationStyle_rawValuesAreStable() {
        XCTAssertEqual(OperatorPromptUserNotificationStyle.banner.rawValue, "banner")
        XCTAssertEqual(OperatorPromptUserNotificationStyle.mcrCriticalReturn.rawValue, "mcrCriticalReturn")
    }

    func test_userNotificationStyle_defaultsToBanner() {
        // Verifies the default parameter on `.userNotification(style:)` stays `.banner`.
        let target = OperatorPromptDeliveryTarget.userNotification()
        if case .userNotification(let style) = target {
            XCTAssertEqual(style, .banner)
        } else {
            XCTFail("userNotification(style:) factory must produce a .userNotification case.")
        }
    }

    // MARK: - Equatable / Hashable

    func test_equatable_distinguishesAddressingFields() {
        let runA = UUID()
        let runB = UUID()
        XCTAssertEqual(OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: runA),
                       OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: runA))
        XCTAssertNotEqual(OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: runA),
                          OperatorPromptDeliveryTarget.mcrPromptPanel(missionRunID: runB))

        XCTAssertNotEqual(OperatorPromptDeliveryTarget.persistentToast,
                          OperatorPromptDeliveryTarget.userNotification(style: .banner))
    }

    func test_hashable_canBeUsedAsSetElement() {
        let runID = UUID()
        let set: Set<OperatorPromptDeliveryTarget> = [
            .mcrPromptPanel(missionRunID: runID),
            .mcrPromptPanel(missionRunID: runID),
            .persistentToast,
            .inAppInbox,
        ]
        XCTAssertEqual(set.count, 3)
    }
}
