import AppKit

/// Dock / Finder icon PNG for the active app product (`dock_logo_mission` or `dock_logo_training`).
public enum GuardianDockLogoAsset {
    public static func nsImage(for product: GuardianAppProduct) -> NSImage? {
        GuardianBundledPNGAsset.nsImage(resourceName: product.dockLogoResourceName)
    }
}
