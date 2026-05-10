import AppKit
import Foundation
import SwiftUI

/// Pointed **G** mark in the collapsed rail and wordmark.
///
/// Loads ``Resources/Brand/GuardianMark.svg`` via ``NSImage`` when the system can decode it; otherwise draws the same geometry with ``Canvas`` (even-odd fill) so the on-screen mark always matches the SVG art.
struct GuardianPointedGMark: View {
    var body: some View {
        Group {
            if let image = GuardianBrandMarkResource.cachedRasterFromSVG {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                GuardianMarkVectorCanvas()
            }
        }
        .accessibilityLabel("Guardian")
    }
}

// MARK: - Bundle SVG → NSImage (when supported)

private enum GuardianBrandMarkResource {
    /// Rasterized from bundled SVG when `NSImage` supports it (varies by macOS version).
    static let cachedRasterFromSVG: NSImage? = {
        guard let url = resolveMarkSVGURL() else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }()

    private static func resolveMarkSVGURL() -> URL? {
        let relative = "Brand/GuardianMark.svg"
        var bundles: [Bundle] = [Bundle.module, Bundle.main]

        let moduleName = Bundle.module.bundleURL.lastPathComponent
        if moduleName.hasSuffix(".bundle"),
           let nested = Bundle.main.resourceURL?.appendingPathComponent(moduleName, isDirectory: true),
           FileManager.default.fileExists(atPath: nested.path),
           let nestedBundle = Bundle(url: nested) {
            bundles.append(nestedBundle)
        }

        for bundle in bundles {
            let atBundleRoot = bundle.bundleURL.appendingPathComponent(relative)
            if FileManager.default.isReadableFile(atPath: atBundleRoot.path) {
                return atBundleRoot
            }
            if let resourceURL = bundle.resourceURL {
                let candidate = resourceURL.appendingPathComponent(relative)
                if FileManager.default.isReadableFile(atPath: candidate.path) {
                    return candidate
                }
            }
            if let url = bundle.url(forResource: "GuardianMark", withExtension: "svg", subdirectory: "Brand"),
               FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
            if let url = bundle.url(forResource: "GuardianMark", withExtension: "svg"),
               FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

// MARK: - Vector fallback (matches `Resources/Brand/GuardianMark.svg` paths)

/// Same paths as the bundled SVG (200 × ~173.2 view box); keep in sync when editing the SVG.
private enum GuardianMarkVectorPaths {
    private static let viewWidth: CGFloat = 200
    private static let viewHeight: CGFloat = 173.205_080_756_887_73

    static func path(in size: CGSize) -> Path {
        let s = min(size.width / viewWidth, size.height / viewHeight)
        let dx = (size.width - viewWidth * s) / 2
        let dy = (size.height - viewHeight * s) / 2
        func T(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var p = Path()
        // Outer triangle
        p.move(to: T(0, 0))
        p.addLine(to: T(200, 0))
        p.addLine(to: T(100, viewHeight))
        p.closeSubpath()
        // Cutouts (same geometry as mask paths in GuardianMark.svg; opposite winding to outer for even-odd)
        p.move(to: T(200, 14))
        p.addLine(to: T(200, 44))
        p.addLine(to: T(96, 44))
        p.addLine(to: T(118, 14))
        p.closeSubpath()

        p.move(to: T(200, 50))
        p.addLine(to: T(200, 72))
        p.addLine(to: T(124, 72))
        p.addLine(to: T(124, 50))
        p.closeSubpath()

        p.move(to: T(200, 78))
        p.addLine(to: T(112, 78))
        p.addLine(to: T(84, 120))
        p.addLine(to: T(100, 138))
        p.addLine(to: T(128, 78))
        p.closeSubpath()

        return p
    }
}

private struct GuardianMarkVectorCanvas: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, _ in
                let path = GuardianMarkVectorPaths.path(in: geo.size)
                context.fill(path, with: .color(GuardianBrand.purple), style: FillStyle(eoFill: true))
            }
        }
    }
}
