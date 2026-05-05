import Foundation

enum TerminalLogFormatting {
    /// Removes common ANSI SGR sequences (e.g. `[34m`, `[0m`) so log lines read cleanly in the UI.
    static func stripANSICodes(_ line: String) -> String {
        guard !line.isEmpty else { return line }
        let pattern = #"\u{1B}\[[0-9;]*m"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        var cleaned = regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
        // Orphan SGR fragments when reads split before ESC (e.g. `[34m` without `\u{1B}`).
        let orphanPattern = #"(?<!\u{1B})\[[0-9;]{1,4}m"#
        if let orphan = try? NSRegularExpression(pattern: orphanPattern, options: []) {
            let r2 = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = orphan.stringByReplacingMatches(in: cleaned, options: [], range: r2, withTemplate: "")
        }
        return cleaned
    }
}
