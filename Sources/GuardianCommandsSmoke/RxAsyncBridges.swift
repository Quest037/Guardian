import Foundation
import Mavsdk
import RxSwift

// MARK: - Errors

enum SmokeBridgeError: Error, CustomStringConvertible {
    case timedOut(after: TimeInterval, doing: String)
    case observableCompletedWithoutValue(doing: String)
    case cancelled(doing: String)

    var description: String {
        switch self {
        case .timedOut(let after, let doing):
            return "timed out after \(String(format: "%.1f", after))s while \(doing)"
        case .observableCompletedWithoutValue(let doing):
            return "observable completed without emitting a value while \(doing)"
        case .cancelled(let doing):
            return "cancelled while \(doing)"
        }
    }
}

// MARK: - Continuation gate

/// Single-fire gate around a checked-throwing continuation. The runner races MAVSDK's
/// RxSwift subscription against a timeout — both branches must be able to resume the
/// continuation, but only the first to fire wins, otherwise Swift traps on double-resume.
private final class BridgeContinuationGate<T>: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()

    func resume(
        _ continuation: CheckedContinuation<T, Error>,
        result: Result<T, Error>
    ) {
        lock.lock()
        let shouldFire = !hasResumed
        if shouldFire { hasResumed = true }
        lock.unlock()
        guard shouldFire else { return }
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

// MARK: - Completable

/// Subscribe to a MAVSDK `Completable`, resolving when it completes or rejecting on its
/// `onError` / the given timeout — whichever fires first. The `disposable` returned by
/// `subscribe` is held by the bridge for the full lifetime so RxSwift does not GC the
/// stream early.
func awaitCompletable(
    _ completable: Completable,
    timeout: TimeInterval,
    doing label: String
) async throws {
    let gate = BridgeContinuationGate<Void>()
    var capturedDisposable: Disposable?

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        capturedDisposable = completable.subscribe(
            onCompleted: { gate.resume(cont, result: .success(())) },
            onError: { gate.resume(cont, result: .failure($0)) }
        )

        Task { [gate, capturedDisposable] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            gate.resume(cont, result: .failure(
                SmokeBridgeError.timedOut(after: timeout, doing: label)
            ))
            capturedDisposable?.dispose()
        }
    }
    capturedDisposable?.dispose()
}

// MARK: - Single<T>

/// Same shape as ``awaitCompletable`` but for `Single<T>` (one-shot value).
func awaitSingle<T>(
    _ single: Single<T>,
    timeout: TimeInterval,
    doing label: String
) async throws -> T {
    let gate = BridgeContinuationGate<T>()
    var capturedDisposable: Disposable?

    let value: T = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
        capturedDisposable = single.subscribe(
            onSuccess: { value in gate.resume(cont, result: .success(value)) },
            onFailure: { error in gate.resume(cont, result: .failure(error)) }
        )

        Task { [gate, capturedDisposable] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            gate.resume(cont, result: .failure(
                SmokeBridgeError.timedOut(after: timeout, doing: label)
            ))
            capturedDisposable?.dispose()
        }
    }
    capturedDisposable?.dispose()
    return value
}

// MARK: - Observable.first(where:) with timeout

/// Subscribe to a long-lived MAVSDK `Observable<T>` (e.g. `drone.telemetry.flightMode`),
/// resolve with the first emitted value satisfying `predicate`, or fail with timeout.
/// Disposes the subscription on either branch.
///
/// Useful for "wait until armed", "wait for flightMode == HOLD", "wait for GPS 3D fix".
func awaitObservableFirst<T>(
    _ observable: Observable<T>,
    timeout: TimeInterval,
    doing label: String,
    where predicate: @escaping (T) -> Bool
) async throws -> T {
    let gate = BridgeContinuationGate<T>()
    var capturedDisposable: Disposable?

    let value: T = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
        capturedDisposable = observable.subscribe(
            onNext: { v in
                if predicate(v) {
                    gate.resume(cont, result: .success(v))
                }
            },
            onError: { error in gate.resume(cont, result: .failure(error)) },
            onCompleted: {
                gate.resume(cont, result: .failure(
                    SmokeBridgeError.observableCompletedWithoutValue(doing: label)
                ))
            }
        )

        Task { [gate, capturedDisposable] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            gate.resume(cont, result: .failure(
                SmokeBridgeError.timedOut(after: timeout, doing: label)
            ))
            capturedDisposable?.dispose()
        }
    }
    capturedDisposable?.dispose()
    return value
}

// MARK: - Observable.next() one-shot

/// Resolve with the first value emitted by an `Observable<T>`. Sugar over
/// ``awaitObservableFirst`` with a permissive predicate.
func awaitObservableNext<T>(
    _ observable: Observable<T>,
    timeout: TimeInterval,
    doing label: String
) async throws -> T {
    try await awaitObservableFirst(observable, timeout: timeout, doing: label, where: { _ in true })
}
