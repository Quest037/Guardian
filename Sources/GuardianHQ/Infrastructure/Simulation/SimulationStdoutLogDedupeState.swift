import Foundation

/// Suppresses consecutive identical simulation stdout lines for known noisy patterns (extend `Rule` list as needed).
struct SimulationStdoutLogDedupeState: Sendable {
    private var lastEmittedFingerprintByRuleID: [String: String] = [:]

    mutating func reset() {
        lastEmittedFingerprintByRuleID.removeAll(keepingCapacity: true)
    }

    /// Returns the line to append to the log, or `nil` when this emission should be skipped.
    mutating func lineToAppendOrNil(_ rawLine: String) -> String? {
        let payload = Self.payloadAfterBracketPrefix(rawLine)
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawLine }

        for rule in Self.rules {
            guard let fp = rule.fingerprint(trimmed) else { continue }
            if lastEmittedFingerprintByRuleID[rule.id] == fp {
                return nil
            }
            lastEmittedFingerprintByRuleID[rule.id] = fp
            return rawLine
        }
        return rawLine
    }

    private struct Rule: Sendable {
        let id: String
        let fingerprint: @Sendable (String) -> String?
    }

    /// Strip `[sitl] ` / `[prefix] ` so fingerprints match ArduPilot’s payload regardless of UI prefix.
    private static func payloadAfterBracketPrefix(_ line: String) -> String {
        guard line.first == "[" else { return line }
        guard let close = line.firstIndex(of: "]"), close < line.endIndex else { return line }
        let afterBracket = line.index(after: close)
        return String(line[afterBracket...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let rules: [Rule] = [
        Rule(id: "ardu_flight_battery_percent") { line in
            let lower = line.lowercased()
            guard lower.hasPrefix("flight battery ") else { return nil }
            guard lower.hasSuffix(" percent") else { return nil }
            return lower
        },
    ]
}
