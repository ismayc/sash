import Foundation

/// Turns the names monitors report about themselves into the labels shown in the menu.
///
/// Kept free of AppKit so it is testable headlessly: the app layer reads `NSScreen.localizedName`
/// and hands the raw strings here. Two problems to solve, both of which produce a menu the user
/// cannot act on if ignored:
///  - a display may report nothing at all (seen with some capture cards and KVMs)
///  - two identical models report the *same* name, so "Snap on monitor: LG ULTRAWIDE" would be
///    ambiguous between them
public enum DisplayNaming {

    /// The name for a single display, falling back to its position when it reports nothing.
    /// `index` is zero-based; the fallback is one-based to match how macOS numbers displays.
    public static func name(reported: String, index: Int) -> String {
        let trimmed = reported.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Display \(index + 1)" : trimmed
    }

    /// Names for every attached display, in order, with duplicates suffixed "(1)", "(2)"…
    /// Names that appear only once are left alone — a lone monitor stays "LG ULTRAWIDE" rather
    /// than becoming "LG ULTRAWIDE (1)".
    public static func uniqueNames(reported: [String]) -> [String] {
        let base = reported.enumerated().map { name(reported: $1, index: $0) }

        var totals: [String: Int] = [:]
        for name in base { totals[name, default: 0] += 1 }

        var seen: [String: Int] = [:]
        return base.map { name in
            guard totals[name, default: 0] > 1 else { return name }
            let n = (seen[name] ?? 0) + 1
            seen[name] = n
            return "\(name) (\(n))"
        }
    }
}
