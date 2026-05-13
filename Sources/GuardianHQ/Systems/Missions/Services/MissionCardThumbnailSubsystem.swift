import AppKit
import Foundation

/// Raster mission card art: shield + preset foreground, deterministic colors from mission id → JPEG on disk.
/// Geometry mirrors ``Resources/MissionBadge/shield.svg`` (keep in sync when editing art). Foreground glyphs are
/// authored in Core Graphics here (see ``MissionCardForegroundGlyph``); ``Resources/MissionBadge/foreground_double_chevron.svg`` remains a **reference** for the double-chevron shape only.
///
/// Implemented with Core Graphics (draw paths, set fill/stroke, encode JPEG) — no WebKit, no hidden windows, no SVG parser.
enum MissionCardThumbnailSubsystem {
    private static let renderSize = CGSize(width: 512, height: 512)
    private static let jpegQuality: CGFloat = 0.82

    /// Bump `rasterFileVersion` when badge art/layout changes so old JPEGs are not reused.
    private static let rasterFileVersion = 4

    static func fileURL(forMissionID id: UUID) -> URL {
        MissionStore.missionCardThumbnailsDirectoryURL
            .appendingPathComponent("\(id.uuidString).r\(rasterFileVersion).jpg")
    }

    /// Deterministic glyph index + fill/stroke hex from mission id (vibrant colours; rejects dark / muted greys).
    static func style(for missionID: UUID) -> (foregroundIndex: Int, fillHex: String, strokeHex: String) {
        var uuid = missionID.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0.bindMemory(to: UInt8.self)) }
        let glyphCount = MissionCardForegroundGlyph.allCases.count
        let idx = Int(bytes[0]) % max(1, glyphCount)
        let (rF, gF, bF) = rgbFill(for: bytes)
        let (rS, gS, bS) = strokeRGB(fromFill: (rF, gF, bF), salt: bytes)
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
            dir.appendingPathComponent("\(idStr).r3.jpg"),
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

    // MARK: - Colour (vibrant + blacklist)

    /// Fallback palette when HSB-derived RGB is too dark or too grey for the near-black card well.
    private static let vibrantPalette: [(UInt8, UInt8, UInt8)] = [
        (65, 105, 225), (30, 144, 255), (0, 191, 255), (0, 206, 209), (64, 224, 208),
        (46, 139, 87), (60, 179, 113), (50, 205, 50), (154, 205, 50), (218, 165, 32),
        (255, 215, 0), (255, 165, 0), (255, 140, 0), (255, 69, 0), (255, 99, 71),
        (220, 20, 60), (255, 20, 147), (255, 105, 180), (199, 21, 133), (219, 112, 147),
        (186, 85, 211), (147, 112, 219), (138, 43, 226), (123, 104, 238), (106, 90, 205),
        (72, 209, 204), (0, 250, 154), (50, 205, 153), (32, 178, 170),
    ]

    /// True when RGB would read as **black-on-near-black** or **muted grey** on the mission card well (`#12151c`).
    /// Internal so ``@testable`` unit tests can pin the same policy as production.
    static func isRGBTooDarkOrMutedGrey(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        let maxv = max(r, max(g, b))
        let minv = min(r, min(g, b))
        if maxv < 96 { return true }
        let spread = Int(maxv) - Int(minv)
        let avg = (Int(r) + Int(g) + Int(b)) / 3
        if spread < 32 && avg < 135 { return true }
        return false
    }

    private static func rgbFill(for bytes: [UInt8]) -> (UInt8, UInt8, UInt8) {
        guard bytes.count >= 16 else {
            return vibrantPalette[0]
        }
        let h = CGFloat(bytes[1]) / 255.0
        let s = 0.58 + CGFloat(bytes[2]) / 255.0 * 0.42
        let br = 0.52 + CGFloat(bytes[3]) / 255.0 * 0.38
        let (rf, gf, bf) = rgbFromHSB(h: h, s: s, b: br)
        let r = UInt8(max(0, min(255, Int(round(rf * 255)))))
        let g = UInt8(max(0, min(255, Int(round(gf * 255)))))
        let b = UInt8(max(0, min(255, Int(round(bf * 255)))))
        if isRGBTooDarkOrMutedGrey(r, g, b) {
            let pick = (Int(bytes[4]) << 8 | Int(bytes[5])) % vibrantPalette.count
            return vibrantPalette[pick]
        }
        return (r, g, b)
    }

    /// HSB with h,s,b in 0…1 → linear sRGB components 0…1.
    private static func rgbFromHSB(h: CGFloat, s: CGFloat, b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let hh = (h - floor(h)) * 6
        let i = floor(hh)
        let f = hh - i
        let p = b * (1 - s)
        let q = b * (1 - s * f)
        let t = b * (1 - s * (1 - f))
        switch Int(i) % 6 {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }

    private static func strokeRGB(fromFill fill: (UInt8, UInt8, UInt8), salt: [UInt8]) -> (UInt8, UInt8, UInt8) {
        let drop = 38 + Int(salt[6] % 22)
        func d(_ v: Int) -> UInt8 {
            UInt8(max(28, min(255, v - drop)))
        }
        let r = d(Int(fill.0)), g = d(Int(fill.1)), b = d(Int(fill.2))
        if isRGBTooDarkOrMutedGrey(r, g, b) {
            let drop2 = max(22, drop - 12)
            return (
                UInt8(max(28, Int(fill.0) - drop2)),
                UInt8(max(28, Int(fill.1) - drop2)),
                UInt8(max(28, Int(fill.2) - drop2))
            )
        }
        return (r, g, b)
    }

    // MARK: - Raster

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

        let shieldRect = CGRect(x: (100 - 92) / 2, y: (100 - 92) / 2, width: 92, height: 92)
        drawShield(in: ctx, rect: shieldRect)

        let fgSize: CGFloat = 58
        let fgRect = CGRect(
            x: (100 - fgSize) / 2,
            y: (100 - fgSize) / 2 + 1,
            width: fgSize,
            height: fgSize
        )
        let glyph = MissionCardForegroundGlyph(rawValue: foregroundIndex % MissionCardForegroundGlyph.allCases.count) ?? .doubleChevron
        switch glyph {
        case .doubleChevron:
            drawDoubleChevronForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
        case .singleChevron:
            drawSingleChevronForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
        case .sword:
            drawSwordForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
        case .lightningBolt:
            drawLightningForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
        case .tower:
            drawTowerForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
        case .globe:
            drawGlobeForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
        case .fire:
            drawFireForeground(in: ctx, rect: fgRect, fill: fill, stroke: stroke)
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

        let flipY = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 100)
        let toRect = affineFromUnitSquare(to: rect)
        var combined = toRect.concatenating(flipY)
        let transformed = path.copy(using: &combined) ?? path

        ctx.setFillColor(CGColor(red: 0x1e / 255, green: 0x24 / 255, blue: 0x30 / 255, alpha: 1))
        ctx.setStrokeColor(CGColor(red: 0x3d / 255, green: 0x46 / 255, blue: 0x56 / 255, alpha: 1))
        ctx.setLineWidth(4)
        ctx.addPath(transformed)
        ctx.drawPath(using: .fillStroke)
    }

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
        drawChevronPair(in: ctx, rect: rect, upper: upper, lower: lower, fill: fill, stroke: stroke, lowerAlpha: 0.92)
    }

    private static func drawSingleChevronForeground(in ctx: CGContext, rect: CGRect, fill: NSColor, stroke: NSColor) {
        let ribbon = upwardChevronRibbonPath(
            apex: CGPoint(x: 50, y: 44),
            halfSpan: 14.5,
            baseY: 69.5,
            ribbon: 4.6
        )
        drawChevronPair(in: ctx, rect: rect, upper: ribbon, lower: nil, fill: fill, stroke: stroke, lowerAlpha: 1)
    }

    private static func drawChevronPair(
        in ctx: CGContext,
        rect: CGRect,
        upper: CGPath,
        lower: CGPath?,
        fill: NSColor,
        stroke: NSColor,
        lowerAlpha: CGFloat
    ) {
        let cx: CGFloat = 50
        let cy: CGFloat = 51.5
        let scaleAround = CGAffineTransform(translationX: cx, y: cy)
            .scaledBy(x: 1.26, y: 1.26)
            .translatedBy(x: -cx, y: -cy)
        let toRect = affineFromUnitSquare(to: rect)
        let combinedUpper = toRect.concatenating(scaleAround)

        ctx.setLineWidth(3.5)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(6)
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(stroke.cgColor)

        var cUpper = combinedUpper
        if let pu = upper.copy(using: &cUpper) {
            ctx.addPath(pu)
            ctx.drawPath(using: .fillStroke)
        }
        if let lower {
            ctx.saveGState()
            ctx.setAlpha(lowerAlpha)
            var cLower = combinedUpper
            if let pl = lower.copy(using: &cLower) {
                ctx.addPath(pl)
                ctx.drawPath(using: .fillStroke)
            }
            ctx.restoreGState()
        }
    }

    private static func drawSwordForeground(in ctx: CGContext, rect: CGRect, fill: NSColor, stroke: NSColor) {
        var t = affineFromUnitSquare(to: rect)
        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: 46, y: 24))
        blade.addLine(to: CGPoint(x: 54, y: 24))
        blade.addLine(to: CGPoint(x: 52, y: 72))
        blade.addLine(to: CGPoint(x: 48, y: 72))
        blade.closeSubpath()
        let guardPath = CGMutablePath()
        guardPath.move(to: CGPoint(x: 36, y: 68))
        guardPath.addLine(to: CGPoint(x: 64, y: 68))
        ctx.setLineWidth(3.2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.miter)
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(stroke.cgColor)
        if let pb = blade.copy(using: &t) {
            ctx.addPath(pb)
            ctx.drawPath(using: .fillStroke)
        }
        if let pg = guardPath.copy(using: &t) {
            ctx.addPath(pg)
            ctx.strokePath()
        }
        let pommel = CGMutablePath()
        pommel.addEllipse(in: CGRect(x: 47, y: 18, width: 6, height: 6))
        if let pp = pommel.copy(using: &t) {
            ctx.addPath(pp)
            ctx.drawPath(using: .fillStroke)
        }
    }

    private static func drawLightningForeground(in ctx: CGContext, rect: CGRect, fill: NSColor, stroke: NSColor) {
        let bolt = CGMutablePath()
        bolt.move(to: CGPoint(x: 40, y: 28))
        bolt.addLine(to: CGPoint(x: 52, y: 44))
        bolt.addLine(to: CGPoint(x: 45, y: 44))
        bolt.addLine(to: CGPoint(x: 62, y: 72))
        bolt.addLine(to: CGPoint(x: 48, y: 52))
        bolt.addLine(to: CGPoint(x: 58, y: 52))
        bolt.addLine(to: CGPoint(x: 40, y: 28))
        bolt.closeSubpath()
        var t = affineFromUnitSquare(to: rect)
        if let p = bolt.copy(using: &t) {
            ctx.setLineWidth(3.2)
            ctx.setLineJoin(.miter)
            ctx.setFillColor(fill.cgColor)
            ctx.setStrokeColor(stroke.cgColor)
            ctx.addPath(p)
            ctx.drawPath(using: .fillStroke)
        }
    }

    private static func drawTowerForeground(in ctx: CGContext, rect: CGRect, fill: NSColor, stroke: NSColor) {
        var t = affineFromUnitSquare(to: rect)
        let roof = CGMutablePath()
        roof.move(to: CGPoint(x: 38, y: 42))
        roof.addLine(to: CGPoint(x: 50, y: 24))
        roof.addLine(to: CGPoint(x: 62, y: 42))
        roof.closeSubpath()
        let body = CGMutablePath()
        body.addRect(CGRect(x: 40, y: 42, width: 20, height: 34))
        ctx.setLineWidth(3)
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(stroke.cgColor)
        if let pr = roof.copy(using: &t) {
            ctx.addPath(pr)
            ctx.drawPath(using: .fillStroke)
        }
        if let pb = body.copy(using: &t) {
            ctx.addPath(pb)
            ctx.drawPath(using: .fillStroke)
        }
    }

    private static func drawGlobeForeground(in ctx: CGContext, rect: CGRect, fill: NSColor, stroke: NSColor) {
        var t = affineFromUnitSquare(to: rect)
        let circle = CGMutablePath()
        circle.addEllipse(in: CGRect(x: 32, y: 30, width: 36, height: 36))
        let meridian = CGMutablePath()
        meridian.move(to: CGPoint(x: 50, y: 30))
        meridian.addQuadCurve(to: CGPoint(x: 50, y: 66), control: CGPoint(x: 62, y: 48))
        let lat = CGMutablePath()
        lat.move(to: CGPoint(x: 32, y: 48))
        lat.addQuadCurve(to: CGPoint(x: 68, y: 48), control: CGPoint(x: 50, y: 40))
        ctx.setLineWidth(3)
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(stroke.cgColor)
        if let pc = circle.copy(using: &t) {
            ctx.addPath(pc)
            ctx.drawPath(using: .fillStroke)
        }
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 0))
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(3)
        if let pm = meridian.copy(using: &t) {
            ctx.addPath(pm)
            ctx.strokePath()
        }
        if let pl = lat.copy(using: &t) {
            ctx.addPath(pl)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func drawFireForeground(in ctx: CGContext, rect: CGRect, fill: NSColor, stroke: NSColor) {
        let flame = CGMutablePath()
        flame.move(to: CGPoint(x: 50, y: 72))
        flame.addQuadCurve(to: CGPoint(x: 38, y: 48), control: CGPoint(x: 40, y: 62))
        flame.addQuadCurve(to: CGPoint(x: 42, y: 32), control: CGPoint(x: 34, y: 40))
        flame.addQuadCurve(to: CGPoint(x: 50, y: 26), control: CGPoint(x: 46, y: 28))
        flame.addQuadCurve(to: CGPoint(x: 58, y: 32), control: CGPoint(x: 54, y: 28))
        flame.addQuadCurve(to: CGPoint(x: 62, y: 48), control: CGPoint(x: 66, y: 40))
        flame.addQuadCurve(to: CGPoint(x: 50, y: 72), control: CGPoint(x: 60, y: 62))
        flame.closeSubpath()
        var t = affineFromUnitSquare(to: rect)
        if let p = flame.copy(using: &t) {
            ctx.setLineWidth(3.2)
            ctx.setLineJoin(.round)
            ctx.setFillColor(fill.cgColor)
            ctx.setStrokeColor(stroke.cgColor)
            ctx.addPath(p)
            ctx.drawPath(using: .fillStroke)
        }
    }

    /// Two stacked **upward** rank chevrons (∧∧): filled V-ribbons with inner cut-out, not solid triangles.
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

// MARK: - Foreground glyph set (mission id mod count)

enum MissionCardForegroundGlyph: Int, CaseIterable, Equatable {
    case doubleChevron = 0
    case singleChevron
    case sword
    case lightningBolt
    case tower
    case globe
    case fire
}

private enum MissionCardThumbnailError: Error {
    case jpegEncodeFailed
}
