import Foundation

/// Harmonic embedded viewer loads gzweb over the network until an offline bundle ships.
@MainActor
enum GuardianGazeboWebViewerPolicy {
    static let offlineToastMessage =
        "3D simulation needs an internet connection. The viewer loads over the network until offline mode is available."

    /// Returns `false` and shows a toast when the product uses Gazebo web viewing and the Mac is offline.
    @discardableResult
    static func guardOnlineOrShowToast(
        productIncludesGazebo: Bool,
        toastCenter: ToastCenter?
    ) -> Bool {
        guard productIncludesGazebo else { return true }
        guard GuardianNetworkReachability.shared.isOnline else {
            toastCenter?.show(offlineToastMessage, style: .warning, duration: 4.5)
            return false
        }
        return true
    }

    static func showOfflineToastIfNeeded(
        productIncludesGazebo: Bool,
        toastCenter: ToastCenter,
        section: AppSection? = nil
    ) {
        guard productIncludesGazebo, !GuardianNetworkReachability.shared.isOnline else { return }
        if let section, !isGazeboSimulationSection(section) { return }
        toastCenter.show(offlineToastMessage, style: .warning, duration: 4.5)
    }

    static func isGazeboSimulationSection(_ section: AppSection) -> Bool {
        switch section {
        case .worlds, .training:
            return true
        default:
            return false
        }
    }
}
