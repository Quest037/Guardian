import Foundation
import Network

/// Process-wide network path monitor for operator-facing offline checks.
@MainActor
final class GuardianNetworkReachability: ObservableObject {
    static let shared = GuardianNetworkReachability()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.guardian.network-reachability")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
