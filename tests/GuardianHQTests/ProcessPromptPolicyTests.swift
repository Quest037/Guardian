import XCTest
@testable import GuardianCore

/// Stage D item 4 coverage for ``ProcessPromptPolicy``: the entry catalogue,
/// the resolve-time binding against an event's ``OperatorPromptTarget`` (entries
/// that can't be addressed are dropped), the inbox-mirror flag, and the
/// per-origin default policies.
final class ProcessPromptPolicyTests: XCTestCase {

    // MARK: - Helpers

    private func event(
        origin: OperatorPromptOrigin = .freeform(source: "test"),
        target: OperatorPromptTarget = .unspecified
    ) -> OperatorPromptEvent {
        OperatorPromptEvent(
            origin: origin,
            target: target,
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge]
        )
    }

    // MARK: - Construction

    func test_init_mirrorToInboxDefaultsToTrue() {
        let policy = ProcessPromptPolicy(entries: [.persistentToast])
        XCTAssertTrue(policy.mirrorToInbox)
    }

    func test_init_acceptsEmptyEntriesWithInboxMirrorOn() {
        // Empty entries + inbox mirror still produces a single-target list. Used
        // when a publisher wants "only the inbox" routing (audit-only prompts).
        let policy = ProcessPromptPolicy(entries: [])
        XCTAssertEqual(policy.resolveTargets(for: event()), [.inAppInbox])
    }

    func test_init_emptyEntriesWithInboxMirrorOff_producesEmptyList() {
        let policy = ProcessPromptPolicy(entries: [], mirrorToInbox: false)
        XCTAssertEqual(policy.resolveTargets(for: event()), [])
    }

    // MARK: - Entry binding — MCR

    func test_resolveTargets_mcrPanelBindsRunID() {
        let runID = UUID()
        let policy = ProcessPromptPolicy(entries: [.mcrPanel], mirrorToInbox: false)
        let targets = policy.resolveTargets(for: event(target: OperatorPromptTarget(missionRunID: runID)))
        XCTAssertEqual(targets, [.mcrPromptPanel(missionRunID: runID)])
    }

    func test_resolveTargets_mcrPanelSkippedWhenNoRunID() {
        let policy = ProcessPromptPolicy(entries: [.mcrPanel], mirrorToInbox: false)
        XCTAssertEqual(policy.resolveTargets(for: event()), [])
    }

    // MARK: - Entry binding — LiveDrive

    func test_resolveTargets_liveDrivePanelBindsBothFieldsWhenAvailable() {
        let runID = UUID()
        let policy = ProcessPromptPolicy(entries: [.liveDrivePanel], mirrorToInbox: false)
        let target = OperatorPromptTarget(missionRunID: runID, affectedVehicleID: "ALPHA-1")
        XCTAssertEqual(
            policy.resolveTargets(for: event(target: target)),
            [.liveDrivePromptPanel(missionRunID: runID, vehicleID: "ALPHA-1")]
        )
    }

    func test_resolveTargets_liveDrivePanelBindsVehicleOnly() {
        let policy = ProcessPromptPolicy(entries: [.liveDrivePanel], mirrorToInbox: false)
        let target = OperatorPromptTarget(affectedVehicleID: "ALPHA-1")
        XCTAssertEqual(
            policy.resolveTargets(for: event(target: target)),
            [.liveDrivePromptPanel(missionRunID: nil, vehicleID: "ALPHA-1")]
        )
    }

    func test_resolveTargets_liveDrivePanelBindsRunOnly() {
        let runID = UUID()
        let policy = ProcessPromptPolicy(entries: [.liveDrivePanel], mirrorToInbox: false)
        let target = OperatorPromptTarget(missionRunID: runID)
        XCTAssertEqual(
            policy.resolveTargets(for: event(target: target)),
            [.liveDrivePromptPanel(missionRunID: runID, vehicleID: nil)]
        )
    }

    func test_resolveTargets_liveDrivePanelSkippedWhenNeitherFieldAvailable() {
        let policy = ProcessPromptPolicy(entries: [.liveDrivePanel], mirrorToInbox: false)
        XCTAssertEqual(policy.resolveTargets(for: event()), [])
    }

    // MARK: - Entry binding — Vehicle Inspector wizard

    func test_resolveTargets_wizardBindsVehicleAndForwardsRecipeRunID() {
        let recipeRunID = FleetRecipeRunID()
        let policy = ProcessPromptPolicy(entries: [.vehicleInspectorWizard], mirrorToInbox: false)
        let target = OperatorPromptTarget(affectedVehicleID: "ALPHA-1", recipeRunID: recipeRunID)
        XCTAssertEqual(
            policy.resolveTargets(for: event(target: target)),
            [.vehicleInspectorWizardPanel(vehicleID: "ALPHA-1", recipeRunID: recipeRunID)]
        )
    }

    func test_resolveTargets_wizardBindsVehicleWithoutRecipeRunID() {
        let policy = ProcessPromptPolicy(entries: [.vehicleInspectorWizard], mirrorToInbox: false)
        let target = OperatorPromptTarget(affectedVehicleID: "ALPHA-1")
        XCTAssertEqual(
            policy.resolveTargets(for: event(target: target)),
            [.vehicleInspectorWizardPanel(vehicleID: "ALPHA-1", recipeRunID: nil)]
        )
    }

    func test_resolveTargets_wizardSkippedWhenNoVehicle() {
        let policy = ProcessPromptPolicy(entries: [.vehicleInspectorWizard], mirrorToInbox: false)
        let target = OperatorPromptTarget(missionRunID: UUID())
        XCTAssertEqual(policy.resolveTargets(for: event(target: target)), [])
    }

    // MARK: - Entry binding — broadcast channels

    func test_resolveTargets_persistentToastBindsUnconditionally() {
        let policy = ProcessPromptPolicy(entries: [.persistentToast], mirrorToInbox: false)
        XCTAssertEqual(policy.resolveTargets(for: event()), [.persistentToast])
    }

    func test_resolveTargets_userNotificationForwardsStyle() {
        let banner = ProcessPromptPolicy(entries: [.userNotification(style: .banner)], mirrorToInbox: false)
        XCTAssertEqual(banner.resolveTargets(for: event()), [.userNotification(style: .banner)])

        let critical = ProcessPromptPolicy(
            entries: [.userNotification(style: .mcrCriticalReturn)],
            mirrorToInbox: false
        )
        XCTAssertEqual(critical.resolveTargets(for: event()), [.userNotification(style: .mcrCriticalReturn)])
    }

    // MARK: - Order preservation and inbox mirror

    func test_resolveTargets_preservesDeclaredOrder() {
        let runID = UUID()
        let policy = ProcessPromptPolicy(
            entries: [.persistentToast, .mcrPanel, .userNotification(style: .banner)],
            mirrorToInbox: false
        )
        let target = OperatorPromptTarget(missionRunID: runID)
        XCTAssertEqual(
            policy.resolveTargets(for: event(target: target)),
            [
                .persistentToast,
                .mcrPromptPanel(missionRunID: runID),
                .userNotification(style: .banner),
            ]
        )
    }

    func test_resolveTargets_dropsUnaddressableEntriesButKeepsOrder() {
        // wizard requires vehicleID — drop; toast — keep; mcrPanel requires runID
        // — drop. Result is just the toast.
        let policy = ProcessPromptPolicy(
            entries: [.vehicleInspectorWizard, .persistentToast, .mcrPanel],
            mirrorToInbox: false
        )
        XCTAssertEqual(policy.resolveTargets(for: event()), [.persistentToast])
    }

    func test_resolveTargets_appendsInboxWhenMirrorToInboxIsTrue() {
        let policy = ProcessPromptPolicy(entries: [.persistentToast]) // mirrorToInbox defaults to true
        XCTAssertEqual(policy.resolveTargets(for: event()), [.persistentToast, .inAppInbox])
    }

    func test_resolveTargets_inboxAlwaysLast() {
        let runID = UUID()
        let policy = ProcessPromptPolicy(
            entries: [.mcrPanel, .userNotification(style: .banner), .persistentToast]
        )
        let result = policy.resolveTargets(for: event(target: OperatorPromptTarget(missionRunID: runID)))
        XCTAssertEqual(result.last, .inAppInbox)
        XCTAssertEqual(result.dropLast(), [
            .mcrPromptPanel(missionRunID: runID),
            .userNotification(style: .banner),
            .persistentToast,
        ])
    }

    // MARK: - Default policies per origin

    func test_default_recipeEscalation_prefersMCRThenWizardThenLiveDrive() {
        let escalation = sampleEscalationEvent()
        let origin = OperatorPromptOrigin.recipeEscalation(event: escalation)
        let policy = ProcessPromptPolicy.default(for: origin)

        XCTAssertEqual(policy.entries, [
            .mcrPanel,
            .vehicleInspectorWizard,
            .liveDrivePanel,
            .persistentToast,
            .userNotification(style: .banner),
        ])
        XCTAssertTrue(policy.mirrorToInbox)
    }

    func test_default_mreEngagementAsk_endsWithCriticalReturnNotification() {
        let policy = ProcessPromptPolicy.default(for: .mreEngagementAsk(runID: UUID(), action: .rtl))
        XCTAssertEqual(policy.entries, [
            .mcrPanel,
            .liveDrivePanel,
            .persistentToast,
            .userNotification(style: .mcrCriticalReturn),
        ])
    }

    func test_default_mreEngagementHandoff_prefersLiveDriveThenMCR() {
        let policy = ProcessPromptPolicy.default(for: .mreEngagementHandoff(runID: UUID(), action: .swapInReserve))
        XCTAssertEqual(policy.entries, [
            .liveDrivePanel,
            .mcrPanel,
            .userNotification(style: .mcrCriticalReturn),
        ])
    }

    func test_default_freeform_coversMCRThenLiveDriveThenWizardThenToastThenBanner() {
        let policy = ProcessPromptPolicy.default(for: .freeform(source: "anything"))
        XCTAssertEqual(policy.entries, [
            .mcrPanel,
            .liveDrivePanel,
            .vehicleInspectorWizard,
            .persistentToast,
            .userNotification(style: .banner),
        ])
    }

    func test_default_allOriginsMirrorToInbox() {
        let origins: [OperatorPromptOrigin] = [
            .recipeEscalation(event: sampleEscalationEvent()),
            .mreEngagementAsk(runID: UUID(), action: .land),
            .mreEngagementHandoff(runID: UUID(), action: .rtl),
            .freeform(source: "anywhere"),
        ]
        for origin in origins {
            XCTAssertTrue(
                ProcessPromptPolicy.default(for: origin).mirrorToInbox,
                "Default policy for \(origin) must mirror to inbox."
            )
        }
    }

    // MARK: - Integration with default(for:) + resolveTargets

    func test_default_recipeEscalation_resolvesWizardFirstWhenOnlyVehicleKnown() {
        let escalation = sampleEscalationEvent(vehicleID: "ALPHA-1")
        let origin = OperatorPromptOrigin.recipeEscalation(event: escalation)
        let policy = ProcessPromptPolicy.default(for: origin)

        let target = OperatorPromptTarget(
            affectedVehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        )
        let resolved = policy.resolveTargets(for: event(origin: origin, target: target))

        XCTAssertEqual(resolved.first, .vehicleInspectorWizardPanel(
            vehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        ))
        XCTAssertTrue(resolved.contains(.liveDrivePromptPanel(missionRunID: nil, vehicleID: "ALPHA-1")))
        XCTAssertEqual(resolved.last, .inAppInbox)
        // No mission run id → MCR panel skipped.
        XCTAssertFalse(resolved.contains { if case .mcrPromptPanel = $0 { return true } else { return false } })
    }

    func test_default_recipeEscalation_resolvesMCRFirstWhenMissionRunKnown() {
        let runID = UUID()
        let escalation = sampleEscalationEvent(vehicleID: "ALPHA-1")
        let origin = OperatorPromptOrigin.recipeEscalation(event: escalation)
        let policy = ProcessPromptPolicy.default(for: origin)

        let target = OperatorPromptTarget(
            missionRunID: runID,
            affectedVehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        )
        let resolved = policy.resolveTargets(for: event(origin: origin, target: target))

        XCTAssertEqual(resolved.first, .mcrPromptPanel(missionRunID: runID))
        XCTAssertTrue(resolved.contains(.vehicleInspectorWizardPanel(
            vehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        )))
        XCTAssertEqual(resolved.last, .inAppInbox)
    }

    func test_default_mreEngagementAsk_resolvesMCRFirstWhenRunKnown() {
        let runID = UUID()
        let origin = OperatorPromptOrigin.mreEngagementAsk(runID: runID, action: .swapInReserve)
        let policy = ProcessPromptPolicy.default(for: origin)

        let resolved = policy.resolveTargets(
            for: event(origin: origin, target: OperatorPromptTarget(missionRunID: runID))
        )
        XCTAssertEqual(resolved.first, .mcrPromptPanel(missionRunID: runID))
        XCTAssertEqual(resolved.last, .inAppInbox)
    }

    // MARK: - Sample helpers

    private func sampleEscalationEvent(vehicleID: String = "ALPHA-1") -> FleetRecipeEscalationEvent {
        FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.sample"),
            vehicleID: vehicleID,
            stepID: .literal("sampleStep"),
            reason: .operatorActionRequired(kind: .rotateDrone),
            allowedVerbs: [.acknowledge, .abort],
            lastResponse: .success()
        )
    }
}
