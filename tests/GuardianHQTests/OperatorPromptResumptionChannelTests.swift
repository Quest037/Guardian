import Combine
import XCTest
@testable import GuardianHQ

/// Stage D item 6 coverage for ``OperatorPromptResumptionChannel`` — the answer
/// transport that carries operator picks back from delivery surfaces to the
/// originating publisher. Tests cover the publisher API (`awaitAnswer(for:)`),
/// host/center submission (`submit(_:)`), expiry handling, task cancellation,
/// audit-stream fan-out, and the ``OperatorPromptEvent/synthesisedTimeoutAnswer(at:)``
/// helper.
@MainActor
final class OperatorPromptResumptionChannelTests: XCTestCase {

    // MARK: - Helpers

    private func event(
        id: UUID = UUID(),
        allowedVerbs: [FleetRecipeResumptionVerb] = [.acknowledge, .abort],
        timeout: TimeInterval = OperatorPromptEvent.defaultTimeout
    ) -> OperatorPromptEvent {
        OperatorPromptEvent(
            id: id,
            origin: .freeform(source: "test"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: allowedVerbs,
            timeout: timeout
        )
    }

    private func operatorAnswer(for id: UUID, verb: FleetRecipeResumptionVerb = .acknowledge) -> OperatorPromptAnswer {
        OperatorPromptAnswer(
            promptID: id,
            selectedOptionID: OperatorPromptOption.standardID(for: verb),
            verb: verb,
            remember: false,
            resolution: .operatorChose
        )
    }

    // MARK: - submit(_:) + awaitAnswer(for:)

    func test_submit_resumesAwaitingPublisher() async {
        let channel = OperatorPromptResumptionChannel()
        let e = event()
        let expected = operatorAnswer(for: e.id, verb: .acknowledge)

        let task = Task { @MainActor in
            await channel.awaitAnswer(for: e)
        }

        // Yield so the awaitAnswer call has time to install its continuation
        // before we submit. A single Task.yield() is enough on the main actor.
        await Task.yield()
        XCTAssertEqual(channel.pendingCount, 1)

        let applied = channel.submit(expected)
        XCTAssertTrue(applied)

        let received = await task.value
        XCTAssertEqual(received.promptID, e.id)
        XCTAssertEqual(received.verb, .acknowledge)
        XCTAssertEqual(received.resolution, .operatorChose)
        XCTAssertEqual(channel.pendingCount, 0)
    }

    func test_submit_unknownPromptID_returnsFalse() {
        let channel = OperatorPromptResumptionChannel()
        let stray = operatorAnswer(for: UUID(), verb: .acknowledge)
        XCTAssertFalse(channel.submit(stray))
    }

    func test_submit_secondCallAfterResolution_returnsFalse() async {
        let channel = OperatorPromptResumptionChannel()
        let e = event()
        let task = Task { @MainActor in await channel.awaitAnswer(for: e) }
        await Task.yield()

        XCTAssertTrue(channel.submit(operatorAnswer(for: e.id)))
        _ = await task.value
        // Second submission for the same id finds no waiter.
        XCTAssertFalse(channel.submit(operatorAnswer(for: e.id, verb: .abort)))
    }

    // MARK: - Expiry

    func test_awaitAnswer_eventAlreadyExpired_resolvesImmediatelyWithTimeoutAnswer() async {
        let channel = OperatorPromptResumptionChannel()
        let e = event(timeout: 0) // expired the moment it's created
        let answer = await channel.awaitAnswer(for: e)

        XCTAssertEqual(answer.promptID, e.id)
        XCTAssertEqual(answer.selectedOptionID, OperatorPromptOption.timeoutOptionID)
        XCTAssertEqual(answer.verb, .abort) // .abort is in default allowedVerbs
        XCTAssertEqual(answer.resolution, .timeoutAborted)
        XCTAssertFalse(answer.remember)
        XCTAssertEqual(channel.pendingCount, 0)
    }

    func test_resolveExpiry_submitsSynthesisedTimeoutAnswer() async {
        let channel = OperatorPromptResumptionChannel()
        let e = event()
        let task = Task { @MainActor in await channel.awaitAnswer(for: e) }
        await Task.yield()

        let applied = channel.resolveExpiry(for: e)
        XCTAssertTrue(applied)

        let answer = await task.value
        XCTAssertEqual(answer.selectedOptionID, OperatorPromptOption.timeoutOptionID)
        XCTAssertEqual(answer.verb, .abort)
        XCTAssertEqual(answer.resolution, .timeoutAborted)
    }

    func test_resolveExpiry_noWaiter_returnsFalse() {
        let channel = OperatorPromptResumptionChannel()
        let e = event()
        XCTAssertFalse(channel.resolveExpiry(for: e))
    }

    // MARK: - Task cancellation

    func test_awaitAnswer_taskCancellation_synthesisesAbortAndCleansUp() async {
        let channel = OperatorPromptResumptionChannel()
        let e = event()
        let task = Task { @MainActor in await channel.awaitAnswer(for: e) }
        await Task.yield()
        XCTAssertEqual(channel.pendingCount, 1)

        task.cancel()
        let answer = await task.value

        XCTAssertEqual(answer.promptID, e.id)
        XCTAssertEqual(answer.verb, .abort)
        XCTAssertEqual(answer.resolution, .timeoutAborted)
        XCTAssertEqual(channel.pendingCount, 0)
    }

    // MARK: - Audit stream

    func test_allAnswers_emitsForEverySubmittedAnswer() async {
        let channel = OperatorPromptResumptionChannel()
        var collected: [OperatorPromptAnswer] = []
        let subscription = channel.allAnswers.sink { collected.append($0) }
        defer { subscription.cancel() }

        let e1 = event()
        let e2 = event()
        let t1 = Task { @MainActor in await channel.awaitAnswer(for: e1) }
        let t2 = Task { @MainActor in await channel.awaitAnswer(for: e2) }
        await Task.yield()

        XCTAssertTrue(channel.submit(operatorAnswer(for: e1.id, verb: .acknowledge)))
        XCTAssertTrue(channel.submit(operatorAnswer(for: e2.id, verb: .abort)))
        _ = await t1.value
        _ = await t2.value

        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected.map(\.verb), [.acknowledge, .abort])
    }

    func test_allAnswers_emitsForExpiredEventEarlyResolution() async {
        let channel = OperatorPromptResumptionChannel()
        var collected: [OperatorPromptAnswer] = []
        let subscription = channel.allAnswers.sink { collected.append($0) }
        defer { subscription.cancel() }

        let expired = event(timeout: 0)
        _ = await channel.awaitAnswer(for: expired)

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(collected.first?.resolution, .timeoutAborted)
    }

    // MARK: - synthesisedTimeoutAnswer

    func test_synthesisedTimeoutAnswer_prefersAbortWhenAllowed() {
        let e = event(allowedVerbs: [.acknowledge, .retry, .abort])
        let answer = e.synthesisedTimeoutAnswer()
        XCTAssertEqual(answer.verb, .abort)
        XCTAssertEqual(answer.selectedOptionID, OperatorPromptOption.timeoutOptionID)
        XCTAssertEqual(answer.resolution, .timeoutAborted)
        XCTAssertFalse(answer.remember)
    }

    func test_synthesisedTimeoutAnswer_fallsBackToFirstAllowedVerbWhenAbortMissing() {
        let e = event(allowedVerbs: [.acknowledge, .retry])
        let answer = e.synthesisedTimeoutAnswer()
        XCTAssertEqual(answer.verb, .acknowledge)
    }

    func test_synthesisedTimeoutAnswer_emptyAllowedVerbs_fallsBackToAbort() {
        // The prompt event type does not itself enforce non-empty allowedVerbs;
        // the runner contract does. Guard against the unsafe construction.
        let e = event(allowedVerbs: [])
        let answer = e.synthesisedTimeoutAnswer()
        XCTAssertEqual(answer.verb, .abort)
    }

    func test_synthesisedTimeoutAnswer_carriesProvidedTimestamp() {
        let e = event()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let answer = e.synthesisedTimeoutAnswer(at: when)
        XCTAssertEqual(answer.answeredAt, when)
    }

    // MARK: - Double-await safety

    func test_doubleAwaitForSameEventID_unblocksFirstWaiterWithTimeoutAnswer() async {
        let channel = OperatorPromptResumptionChannel()
        let e = event()

        var first: OperatorPromptAnswer?
        let firstTask = Task { @MainActor in
            first = await channel.awaitAnswer(for: e)
        }
        await Task.yield()

        // Second await for the same id. The channel resolves the first waiter
        // with a synthesised timeout answer and installs the new continuation
        // so the second caller becomes the live one.
        let secondTask = Task { @MainActor in await channel.awaitAnswer(for: e) }
        await Task.yield()
        _ = await firstTask.value

        XCTAssertEqual(first?.resolution, .timeoutAborted)
        XCTAssertEqual(channel.pendingCount, 1)

        // The second await still resolves normally on submit.
        let realAnswer = operatorAnswer(for: e.id, verb: .acknowledge)
        XCTAssertTrue(channel.submit(realAnswer))
        let received = await secondTask.value
        XCTAssertEqual(received.verb, .acknowledge)
        XCTAssertEqual(received.resolution, .operatorChose)
    }
}
