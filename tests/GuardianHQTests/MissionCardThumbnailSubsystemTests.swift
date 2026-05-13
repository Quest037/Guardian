import XCTest

@testable import GuardianHQ

final class MissionCardThumbnailSubsystemTests: XCTestCase {
    func test_style_foregroundIndex_inRange() {
        for _ in 0 ..< 500 {
            let id = UUID()
            let s = MissionCardThumbnailSubsystem.style(for: id)
            XCTAssertGreaterThanOrEqual(s.foregroundIndex, 0)
            XCTAssertLessThan(s.foregroundIndex, MissionCardForegroundGlyph.allCases.count)
        }
    }

    func test_style_fillAndStroke_passVibrancyGate() {
        for _ in 0 ..< 400 {
            let id = UUID()
            let s = MissionCardThumbnailSubsystem.style(for: id)
            let fill = rgb(from: s.fillHex)
            let stroke = rgb(from: s.strokeHex)
            XCTAssertFalse(
                MissionCardThumbnailSubsystem.isRGBTooDarkOrMutedGrey(fill.0, fill.1, fill.2),
                "fill \(s.fillHex) should not read as black/grey on card well"
            )
            XCTAssertFalse(
                MissionCardThumbnailSubsystem.isRGBTooDarkOrMutedGrey(stroke.0, stroke.1, stroke.2),
                "stroke \(s.strokeHex) should not read as black/grey on card well"
            )
        }
    }

    func test_style_firstByte_selectsGlyphIndex() throws {
        // RFC 4122 string layout: first byte is the high octet of the time-low field (first 8 hex digits).
        let id0 = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(MissionCardThumbnailSubsystem.style(for: id0).foregroundIndex, 0)

        let id6 = try XCTUnwrap(UUID(uuidString: "06000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(MissionCardThumbnailSubsystem.style(for: id6).foregroundIndex, 6)

        let idWrap = try XCTUnwrap(UUID(uuidString: "07000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(MissionCardThumbnailSubsystem.style(for: idWrap).foregroundIndex, 0)
    }

    func test_isRGBTooDarkOrMutedGrey_examples() {
        XCTAssertTrue(MissionCardThumbnailSubsystem.isRGBTooDarkOrMutedGrey(20, 22, 18))
        XCTAssertTrue(MissionCardThumbnailSubsystem.isRGBTooDarkOrMutedGrey(90, 92, 88))
        XCTAssertFalse(MissionCardThumbnailSubsystem.isRGBTooDarkOrMutedGrey(65, 105, 225))
        XCTAssertFalse(MissionCardThumbnailSubsystem.isRGBTooDarkOrMutedGrey(255, 200, 40))
    }

    // MARK: - Helpers

    private func rgb(from hex: String) -> (UInt8, UInt8, UInt8) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            XCTFail("bad hex: \(hex)")
            return (0, 0, 0)
        }
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

}
