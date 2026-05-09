import AppKit
import Foundation

/// Raster mission card art: shield + preset foreground, deterministic colors from mission id → JPEG on disk.
/// Geometry mirrors ``Resources/MissionBadge/shield.svg`` and ``foreground_double_chevron.svg`` (keep in sync when editing art).
///
/// Implemented with Core Graphics (draw paths, set fill/stroke, encode JPEG) — no WebKit, no hidden windows, no SVG parser.
enum MissionCardThumbnailSubsystem {
    private static let renderSize = CGSize(width: 512, height: 512)
    private static let jpegQuality: CGFloat = 0.82
    private static let foregroundPresetCount = 1

    /// Bump `rasterFileVersion` when badge art/layout changes so old JPEGs are not reused.
    private static let rasterFileVersion = 3

    static func fileURL(forMissionID id: UUID) -> URL {
        MissionStore.missionCardThumbnailsDirectoryURL
            .appendingPathComponent("\(id.uuidString).r\(rasterFileVersion).jpg")
    }

    /// Deterministic colors and foreground index from mission id.
    static func style(for missionID: UUID) -> (foregroundIndex: Int, fillHex: String, strokeHex: String) {
        var uuid = missionID.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0.bindMemory(to: UInt8.self)) }
        let idx = Int(bytes[0]) % max(1, foregroundPresetCount)
        let rF = 90 + Int(bytes[1]) % 166
        let gF = 90 + Int(bytes[2]) % 166
        let bF = 90 + Int(bytes[3]) % 166
        let rS = max(0, rF - 35 - Int(bytes[4]) % 40)
        let gS = max(0, gF - 35 - Int(bytes[5]) % 40)
        let bS = max(0, bF - 35 - Int(bytes[6]) % 40)
        let fillHex = String(format: "#%02X%02X%02X", rF, gF, bF)
        let strokeHex = String(format: "#%02X%02X%02X", rS, gS, bS)
        return (idx, fillHex, strokeHex)
    }

    static func generateAndSave(for missionID: UUID) async throws {
        let data = try await renderJPEG(for: missionID)
        let url = fileURL(forMissionID: missionID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func deleteFileIfPresent(for missionID: UUID) {
        let dir = MissionStore.missionCardThumbnailsDirectoryURL
        let idStr = missionID.uuidString
        let candidates = [
            dir.appendingPathComponent("\(idStr).r\(rasterFileVersion).jpg"),
            dir.appendingPathComponent("\(idStr).r2.jpg"),
            dir.appendingPathComponent("\(idStr).jpg"),
        ]
        for url in candidates {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func renderJPEG(for missionID: UUID) async throws -> Data {
        let style = Self.style(for: missionID)
        return try await MainActor.run {
            try Self.rasterizeBadgeJPEG(foregroundIndex: style.foregroundIndex, fillHex: style.fillHex, strokeHex: style.strokeHex)
        }
    }

    private static func rasterizeBadgeJPEG(foregroundIndex: Int, fillHex: String, strokeHex: String) throws -> Data {
        let fill = nsColor(fromHex: fillHex)
        let stroke = nsColor(fromHex: strokeHex)
        let image = NSImage(size: renderSize, flipped: false) { dst in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawBadge(in: ctx, bounds: dst, foregroundIndex: foregroundIndex, fill: fill, stroke: stroke)
            return true
        }
        return try encodeJPEG(from: image, quality: jpegQuality)
    }

    private static func drawBadge(
        in ctx: CGContext,
        bounds: CGRect,
        foregroundIndex: Int,
        fill: NSColor,
        stroke: NSColor
    ) {
        let scale = bounds.width / 100.0
        ctx.saveGState()
        ctx.translateBy(x: bounds.minX, y: bounds.minY)
        ctx.scaleBy(x: scale, y: scale)

        // Background #12151c
        ctx.setFillColor(CGColor(red: 0x12 / 255, green: 0x15 / 255, blue: 0x1c / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

        // Shield in centered 92×92 (design units 0…100)
        let shieldRect = CGRect(x: (100 - 92) / 2, y: (100 - 92) / 2, width: 92, height: 92)
        drawShield(in: ctx, rect: shieldRect)

        // Foreground: larger square, centered, slight nudge (was 46; bigger chevrons read better on shield).
        let fgSize: CGFloat = 58
        let fgRect = CGRect(
            x: (100 - fgSize) / 2,
            y: (100 - fgSize) / 2 + 1,
            width: fgSize,
            height: fgSize
        )
        switch foregroundIndex % foregroundPresetCount {
        default:
            drawDoubleChevronForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
        }

        ctx.restoreGState()
    }

    private static func drawShield(in ctx: CGContext, rect: CGRect) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 50, y: 6))
        path.addLine(to: CGPoint(x: 88, y: 21))
        path.addLine(to: CGPoint(x: 88, y: 49))
        path.addQuadCurve(to: CGPoint(x: 50, y: 94), control: CGPoint(x: 88, y: 72))
        path.addQuadCurve(to: CGPoint(x: 12, y: 49), control: CGPoint(x: 12, y: 72))
        path.addLine(to: CGPoint(x: 12, y: 21))
        path.closeSubpath()

        // Flip vertically in unit space so the shield point reads correctly on screen (matches SVG asset intent).
        let flipY = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 100)
        let toRect = affineFromUnitSquare(to: rect)
        var combined = toRect.concatenating(flipY)
        let transformed = path.copy(using: &combined) ?? path

        ctx.setFillColor(CGColor(red: 0x1e / 255, green: 0x24 / 255, blue: 0x30 / 255, alpha: 1))
        ctx.setStrokeColor(CGColor(red: 0x3d / 255, green: 0x46 / 255, blue: 0x56 / 255, alpha: 1))
        // SVG stroke-width was 2; increase by 2 for legibility → 4 in design units.
        ctx.setLineWidth(4)
        ctx.addPath(transformed)
        ctx.drawPath(using: .fillStroke)
    }

    /// Two stacked **upward** rank chevrons (∧∧): filled V-ribbons with inner cut-out, not solid triangles.
    private static func drawDoubleChevronForeground(in ctx: CGContext, rect: CGRect, fill: NSColor, stroke: NSColor) {
        let upper = upwardChevronRibbonPath(
            apex: CGPoint(x: 50, y: 33.5),
            halfSpan: 12.2,
            baseY: 49.2,
            ribbon: 4.2
        )
        let lower = upwardChevronRibbonPath(
            apex: CGPoint(x: 50, y: 51.8),
            halfSpan: 12.8,
            baseY: 68.2,
            ribbon: 4.2
        )

        let cx: CGFloat = 50
        let cy: CGFloat = 51.5
        let scaleAround = CGAffineTransform(translationX: cx, y: cy)
            .scaledBy(x: 1.26, y: 1.26)
            .translatedBy(x: -cx, y: -cy)
        let toRect = affineFromUnitSquare(to: rect)
        func combinedTransform() -> CGAffineTransform {
            toRect.concatenating(scaleAround)
        }

        ctx.setLineWidth(3.5)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(6)
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(stroke.cgColor)

        var cUpper = combinedTransform()
        if let pu = upper.copy(using: &cUpper) {
            ctx.addPath(pu)
            ctx.drawPath(using: .fillStroke)
        }
        ctx.saveGState()
        ctx.setAlpha(0.92)
        var cLower = combinedTransform()
        if let pl = lower.copy(using: &cLower) {
            ctx.addPath(pl)
            ctx.drawPath(using: .fillStroke)
        }
        ctx.restoreGState()
    }

    /// Closed path for one sleeve-style chevron: outer ∧ with inner ∧ cut-out (single ribbon polygon).
    private static func upwardChevronRibbonPath(apex: CGPoint, halfSpan: CGFloat, baseY: CGFloat, ribbon: CGFloat) -> CGPath {
        let bl = CGPoint(x: apex.x - halfSpan, y: baseY)
        let br = CGPoint(x: apex.x + halfSpan, y: baseY)

        func innerPoint(from corner: CGPoint, towardApex: CGPoint) -> CGPoint {
            let vx = towardApex.x - corner.x
            let vy = towardApex.y - corner.y
            let len = max(1e-6, hypot(vx, vy))
            let ux = vx / len
            let uy = vy / len
            return CGPoint(x: corner.x + ux * ribbon, y: corner.y + uy * ribbon)
        }

        let innerBL = innerPoint(from: bl, towardApex: apex)
        let innerBR = innerPoint(from: br, towardApex: apex)
        let innerApex = CGPoint(x: apex.x, y: apex.y + ribbon * 1.05)

        let p = CGMutablePath()
        p.move(to: bl)
        p.addLine(to: apex)
        p.addLine(to: br)
        p.addLine(to: innerBR)
        p.addLine(to: innerApex)
        p.addLine(to: innerBL)
        p.closeSubpath()
        return p
    }

    /// Map path defined in SVG viewBox 0…100 into `rect` (pixel-aligned design space).
    private static func affineFromUnitSquare(to rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(a: rect.width / 100, b: 0, c: 0, d: rect.height / 100, tx: rect.minX, ty: rect.minY)
    }

    private static func nsColor(fromHex hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return NSColor(calibratedWhite: 0.5, alpha: 1)
        }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }

    private static func encodeJPEG(from image: NSImage, quality: CGFloat) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        else {
            throw MissionCardThumbnailError.jpegEncodeFailed
        }
        return jpeg
    }
}

private enum MissionCardThumbnailError: Error {
    case jpegEncodeFailed
}
