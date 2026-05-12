import XCTest
@testable import GuardianHQ

/// `@Sendable` probes for ``OperatorPromptRouter`` tests (avoid capturing `Self` from `XCTestCase`).
private enum OperatorPromptRouterTestProbes {
    static let acceptAll: @MainActor @Sendable (OperatorPromptDeliveryTarget) -> Bool = { _ in true }
    static let rejectAll: @MainActor @Sendable (OperatorPromptDeliveryTarget) -> Bool = { _ in false }
    static let rejectMCRAcceptRest: @MainActor @Sendable (OperatorPromptDeliveryTarget) -> Bool = { target in
        if case .mcrPromptPanel = target { return false }
        return true
    }
    static let inboxArchiveOnly: @MainActor @Sendable (OperatorPromptDeliveryTarget) -> Bool = { $0.isUniversalArchive }
}

private final class OperatorPromptOriginCaptureBox: @unchecked Sendable {
    var observedOrigins: [OperatorPromptOrigin] = []
}

/// Stage D item 5 coverage for ``OperatorPromptRouter`` — the pure routing
/// decision: policy lookup, availability probe classification (primary /
/// mirrors / suppressed), and the v1 inbox-only default availability fallback.
@MainActor
final class OperatorPromptRouterTests: XCTestCase {

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

    // MARK: - Default availability probe

    func test_defaultAvailabilityProbe_onlyAcceptsInbox() {
        let probe = OperatorPromptRouter.defaultAvailabilityProbe
        XCTAssertTrue(probe(.inAppInbox))

        XCTAssertFalse(probe(.mcrPromptPanel(missionRunID: UUID())))
        XCTAssertFalse(probe(.liveDrivePromptPanel(vehicleID: "V")))
        XCTAssertFalse(probe(.vehicleInspectorWizardPanel(vehicleID: "V")))
        XCTAssertFalse(probe(.persistentToast))
        XCTAssertFalse(probe(.userNotification(style: .banner)))
        XCTAssertFalse(probe(.userNotification(style: .mcrCriticalReturn)))
    }

    func test_default_router_routesEverythingToInbox_whenNoHostRegistered() {
        // Boot-time behaviour: no center, no hosts, just the default probe.
        let router = OperatorPromptRouter()
        let runID = UUID()
        let decision = router.route(event(target: OperatorPromptTarget(missionRunID: runID)))

        XCTAssertEqual(decision.primary, .inAppInbox)
        XCTAssertEqual(decision.mirrors, [])
        // Suppressed: everything else policy wanted but the default probe rejected.
        XCTAssertTrue(decision.suppressed.contains(.mcrPromptPanel(missionRunID: runID)))
        XCTAssertTrue(decision.suppressed.contains(.persistentToast))
        XCTAssertFalse(decision.isUnroutable)
    }

    // MARK: - Probe accepts everything

    func test_route_acceptAll_primaryIsFirstPolicyTarget_mirrorsAreRest() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.acceptAll)
        let runID = UUID()
        // freeform default policy: mcrPanel → liveDrivePanel → wizard → toast → banner (+ inbox)
        let target = OperatorPromptTarget(missionRunID: runID, affectedVehicleID: "ALPHA-1")
        let decision = router.route(event(target: target))

        XCTAssertEqual(decision.primary, .mcrPromptPanel(missionRunID: runID))
        XCTAssertEqual(decision.mirrors, [
            .liveDrivePromptPanel(missionRunID: runID, vehicleID: "ALPHA-1"),
            .vehicleInspectorWizardPanel(vehicleID: "ALPHA-1", recipeRunID: nil),
            .persistentToast,
            .userNotification(style: .banner),
            .inAppInbox,
        ])
        XCTAssertEqual(decision.suppressed, [])
    }

    func test_route_acceptAll_dispatchedIsPrimaryPlusMirrors() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.acceptAll)
        let runID = UUID()
        let decision = router.route(event(target: OperatorPromptTarget(missionRunID: runID)))
        XCTAssertEqual(decision.dispatched.first, decision.primary)
        XCTAssertEqual(decision.dispatched.count, decision.mirrors.count + 1)
    }

    // MARK: - Probe accepts a subset

    func test_route_probeRejectsMCR_primaryFallsThroughToNextAvailable() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.rejectMCRAcceptRest)
        let runID = UUID()
        let target = OperatorPromptTarget(missionRunID: runID, affectedVehicleID: "ALPHA-1")
        let decision = router.route(event(target: target))

        XCTAssertEqual(decision.primary, .liveDrivePromptPanel(missionRunID: runID, vehicleID: "ALPHA-1"))
        XCTAssertEqual(decision.suppressed, [.mcrPromptPanel(missionRunID: runID)])
        XCTAssertTrue(decision.mirrors.contains(.inAppInbox))
    }

    func test_route_probeAcceptsOnlyInbox_primaryIsInbox_noMirrors() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.inboxArchiveOnly)
        let runID = UUID()
        let target = OperatorPromptTarget(missionRunID: runID, affectedVehicleID: "ALPHA-1")
        let decision = router.route(event(target: target))

        XCTAssertEqual(decision.primary, .inAppInbox)
        XCTAssertEqual(decision.mirrors, [])
        // Every other policy-resolved target is suppressed.
        XCTAssertEqual(decision.suppressed.count, 5) // mcr, liveDrive, wizard, toast, banner
        XCTAssertFalse(decision.isUnroutable)
    }

    // MARK: - Probe rejects everything

    func test_route_probeRejectsAll_isUnroutable() {
        // mirrorToInbox = false so inbox isn't auto-added.
        let router = OperatorPromptRouter(
            policyProvider: { (_: OperatorPromptOrigin) in
                ProcessPromptPolicy(entries: [.persistentToast], mirrorToInbox: false)
            },
            availabilityProbe: OperatorPromptRouterTestProbes.rejectAll
        )
        let decision = router.route(event())

        XCTAssertNil(decision.primary)
        XCTAssertEqual(decision.mirrors, [])
        XCTAssertEqual(decision.suppressed, [.persistentToast])
        XCTAssertTrue(decision.isUnroutable)
        XCTAssertEqual(decision.dispatched, [])
    }

    func test_route_probeRejectsAll_inboxStillSuppressedWhenPolicyMirrorsToInbox() {
        // mirrorToInbox = true (default) but probe also rejects inbox →
        // unroutable.
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.rejectAll)
        let decision = router.route(event(target: OperatorPromptTarget(missionRunID: UUID())))

        XCTAssertNil(decision.primary)
        XCTAssertEqual(decision.mirrors, [])
        XCTAssertTrue(decision.suppressed.contains(.inAppInbox))
        XCTAssertTrue(decision.isUnroutable)
    }

    // MARK: - Policy provider override

    func test_route_customPolicyProviderIsUsed() {
        let captureBox = OperatorPromptOriginCaptureBox()
        let customPolicy = ProcessPromptPolicy(entries: [.persistentToast], mirrorToInbox: false)
        let router = OperatorPromptRouter(
            policyProvider: { origin in
                captureBox.observedOrigins.append(origin)
                return customPolicy
            },
            availabilityProbe: OperatorPromptRouterTestProbes.acceptAll
        )

        let decision = router.route(event(origin: .freeform(source: "custom")))

        XCTAssertEqual(decision.primary, .persistentToast)
        XCTAssertEqual(decision.mirrors, [])
        XCTAssertEqual(captureBox.observedOrigins.count, 1)
        if case .freeform(let source) = captureBox.observedOrigins.first {
            XCTAssertEqual(source, "custom")
        } else {
            XCTFail("Expected freeform origin to be forwarded to policy provider.")
        }
    }

    // MARK: - Per-origin defaults flow through the router

    func test_route_recipeEscalation_runsThroughDefaultRecipePolicy() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.acceptAll)
        let escalation = sampleEscalationEvent(vehicleID: "ALPHA-1")
        let target = OperatorPromptTarget(
            affectedVehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        )
        let decision = router.route(event(
            origin: .recipeEscalation(event: escalation),
            target: target
        ))

        // recipe default: mcr → wizard → liveDrive → toast → banner (+ inbox)
        // No mission run id → mcr skipped; wizard is first bound target.
        XCTAssertEqual(decision.primary, .vehicleInspectorWizardPanel(
            vehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        ))
        XCTAssertTrue(decision.mirrors.contains(.liveDrivePromptPanel(
            missionRunID: nil,
            vehicleID: "ALPHA-1"
        )))
        XCTAssertTrue(decision.mirrors.contains(.persistentToast))
        XCTAssertTrue(decision.mirrors.contains(.userNotification(style: .banner)))
        XCTAssertTrue(decision.mirrors.contains(.inAppInbox))
    }

    func test_route_needsAirframeReplacement_withMissionRunID_omitsVehicleInspectorWizard() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.acceptAll)
        let runID = UUID()
        let escalation = sampleNeedsAirframeEscalationEvent(vehicleID: "ALPHA-1")
        let target = OperatorPromptTarget(
            missionRunID: runID,
            affectedVehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        )
        let decision = router.route(event(
            origin: .recipeEscalation(event: escalation),
            target: target
        ))

        XCTAssertEqual(decision.primary, .mcrPromptPanel(missionRunID: runID))
        XCTAssertFalse(decision.dispatched.contains(where: {
            if case .vehicleInspectorWizardPanel = $0 { return true }
            return false
        }))
        XCTAssertTrue(decision.dispatched.contains(.userNotification(style: .mcrCriticalReturn)))
        XCTAssertTrue(decision.dispatched.contains(.inAppInbox))
    }

    func test_route_needsAirframeReplacement_probeRejectsMCR_skipsWizardToLiveDrive() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.rejectMCRAcceptRest)
        let runID = UUID()
        let escalation = sampleNeedsAirframeEscalationEvent(vehicleID: "ALPHA-1")
        let target = OperatorPromptTarget(
            missionRunID: runID,
            affectedVehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        )
        let decision = router.route(event(
            origin: .recipeEscalation(event: escalation),
            target: target
        ))

        XCTAssertEqual(decision.primary, .liveDrivePromptPanel(missionRunID: runID, vehicleID: "ALPHA-1"))
        XCTAssertEqual(decision.suppressed, [.mcrPromptPanel(missionRunID: runID)])
        XCTAssertFalse(decision.dispatched.contains(where: {
            if case .vehicleInspectorWizardPanel = $0 { return true }
            return false
        }))
    }

    func test_route_needsAirframeReplacement_withoutMissionRunID_usesDefaultRecipePolicy() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.acceptAll)
        let escalation = sampleNeedsAirframeEscalationEvent(vehicleID: "ALPHA-1")
        let target = OperatorPromptTarget(
            affectedVehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        )
        let decision = router.route(event(
            origin: .recipeEscalation(event: escalation),
            target: target
        ))

        XCTAssertEqual(decision.primary, .vehicleInspectorWizardPanel(
            vehicleID: "ALPHA-1",
            recipeRunID: escalation.runID
        ))
        XCTAssertTrue(decision.dispatched.contains(.userNotification(style: .banner)))
    }

    func test_route_mreEngagementAsk_endsWithCriticalReturnNotification() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.acceptAll)
        let runID = UUID()
        let origin = OperatorPromptOrigin.mreEngagementAsk(runID: runID, action: .swapInReserve)
        let decision = router.route(event(
            origin: origin,
            target: OperatorPromptTarget(missionRunID: runID)
        ))

        XCTAssertEqual(decision.primary, .mcrPromptPanel(missionRunID: runID))
        // mcrCriticalReturn appears among mirrors as the OOA tail of the ask policy.
        XCTAssertTrue(decision.dispatched.contains(.userNotification(style: .mcrCriticalReturn)))
    }

    // MARK: - Mutation of injection points after init

    func test_mutatingAvailabilityProbe_takesEffectOnNextRoute() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.rejectAll)
        let decision1 = router.route(event(target: OperatorPromptTarget(missionRunID: UUID())))
        XCTAssertTrue(decision1.isUnroutable)

        router.availabilityProbe = OperatorPromptRouterTestProbes.acceptAll
        let decision2 = router.route(event(target: OperatorPromptTarget(missionRunID: UUID())))
        XCTAssertNotNil(decision2.primary)
    }

    func test_mutatingPolicyProvider_takesEffectOnNextRoute() {
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouterTestProbes.acceptAll)
        let decision1 = router.route(event())
        XCTAssertEqual(decision1.primary, .persistentToast)
        // freeform default starts with mcrPanel (skipped — no runID) → liveDrivePanel (skipped — no addressing) →
        // wizard (skipped — no vehicleID) → persistentToast. So first available is toast.

        router.policyProvider = { (_: OperatorPromptOrigin) in
            ProcessPromptPolicy(entries: [.userNotification(style: .banner)])
        }
        let decision2 = router.route(event())
        let expected: OperatorPromptDeliveryTarget? = .userNotification(style: .banner)
        XCTAssertEqual(decision2.primary, expected)
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

    private func sampleNeedsAirframeEscalationEvent(vehicleID: String = "ALPHA-1") -> FleetRecipeEscalationEvent {
        FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.needsAirframe"),
            vehicleID: vehicleID,
            stepID: .literal("sampleStep"),
            reason: .unrecoverableFailure(kind: .needsAirframeReplacement),
            allowedVerbs: [.acknowledge, .abort],
            lastResponse: .success()
        )
    }
}
