import CryptoKit
import Foundation

enum GuardianBrainPackCodec {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ pack: GuardianBrainPack) throws -> Data {
        try makeEncoder().encode(pack)
    }

    static func decode(_ data: Data) throws -> GuardianBrainPack {
        let pack = try makeDecoder().decode(GuardianBrainPack.self, from: data)
        try validate(pack)
        return pack
    }

    static func checksumSHA256(forCanonicalBodyData data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func validate(_ pack: GuardianBrainPack) throws {
        guard GuardianBrainPackFormat.supportedFormatVersionRange.contains(pack.manifest.formatVersion) else {
            throw GuardianBrainPackError.unsupportedFormatVersion(pack.manifest.formatVersion)
        }
        var canonical = pack
        canonical.provenance.checksumSHA256 = ""
        let body = try encode(canonical)
        let expected = pack.provenance.checksumSHA256.lowercased()
        let actual = checksumSHA256(forCanonicalBodyData: body).lowercased()
        guard expected == actual else {
            throw GuardianBrainPackError.checksumMismatch
        }
    }

    /// Seal pack for writing: canonical JSON body hash stored in `provenance.checksum_sha256`.
    static func sealedData(for pack: GuardianBrainPack) throws -> Data {
        var draft = pack
        draft.provenance.checksumSHA256 = ""
        let canonicalBody = try encode(draft)
        draft.provenance.checksumSHA256 = checksumSHA256(forCanonicalBodyData: canonicalBody)
        return try encode(draft)
    }

    static func packWithChecksum(_ pack: GuardianBrainPack) throws -> GuardianBrainPack {
        let data = try sealedData(for: pack)
        return try makeDecoder().decode(GuardianBrainPack.self, from: data)
    }
}
