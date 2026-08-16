import Foundation
import CoreGraphics

/// Space on one screen that Sash must leave alone, measured in points in from each edge.
///
/// The Dock and the menu bar reserve their space through `visibleFrame`, so Sash never covers
/// them without being told. Desktop widgets, wallpaper clocks and always-visible HUDs reserve
/// nothing — `visibleFrame` runs straight underneath them — so the only way to stop a tile
/// landing on top of one is to say where it is. Points rather than fractions of the screen,
/// because what's being protected is a fixed-size thing sitting on the desktop: it stays the
/// same size when the resolution changes, and a fraction wouldn't.
///
/// Pure — no AppKit — so the clamping rule is testable without a window server.
public struct ScreenMargins: Codable, Hashable {
    public var top: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat
    public var right: CGFloat

    /// Nothing kept clear: the whole visible frame is Sash's to use.
    public static let none = ScreenMargins()

    /// The smallest share of a screen dimension that stays usable however greedy the margins.
    /// A screen reserved down to a sliver reads as a bug rather than as a setting, and there is
    /// no sane layout to put in what's left.
    public static let minUsableFraction: CGFloat = 0.2

    /// Below this, a margin counts as nothing at all. A fraction of a point picked up when a
    /// drag brushed an edge is not a strip anyone meant to protect, and carrying it around
    /// means a menu that reads "right 0 pt" and a screen that claims to be reserved when it
    /// isn't. One rule, so what's stored, what's shown and what's usable can't disagree.
    public static let minimumMeaningful: CGFloat = 1

    public init(top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    /// Which side of the screen a margin is held against.
    public enum Edge: String, Codable, CaseIterable {
        case top, bottom, left, right

        /// The edge across from this one — the one it has to share the screen's length with.
        public var opposite: Edge {
            switch self {
            case .top: return .bottom
            case .bottom: return .top
            case .left: return .right
            case .right: return .left
            }
        }

        /// Whether this edge eats into a rect's height (rather than its width).
        public var isVertical: Bool { self == .top || self == .bottom }
    }

    public var isEmpty: Bool { edges.allSatisfy { value(for: $0) < Self.minimumMeaningful } }

    public func value(for edge: Edge) -> CGFloat {
        switch edge {
        case .top: return top
        case .bottom: return bottom
        case .left: return left
        case .right: return right
        }
    }

    /// The part of `frame` Sash may actually use. `frame` is an AppKit rect (bottom-left
    /// origin), so the bottom margin lifts the origin and the top margin only shortens it.
    public func applied(to frame: CGRect) -> CGRect {
        let (l, r) = Self.fit(left, right, within: frame.width)
        let (t, b) = Self.fit(top, bottom, within: frame.height)
        return CGRect(x: frame.minX + l, y: frame.minY + b,
                      width: frame.width - l - r, height: frame.height - t - b)
    }

    /// A copy with one edge moved to `points` in from that side, clamped so it can't cross the
    /// screen or squeeze the opposite margin out of its share. Clamping here rather than in
    /// `applied(to:)` keeps a drag honest: the edge stops under the pointer instead of sliding
    /// on while the geometry silently rescales it.
    public func setting(_ edge: Edge, to points: CGFloat, within frame: CGRect) -> ScreenMargins {
        let length = edge.isVertical ? frame.height : frame.width
        let budget = max(length * (1 - Self.minUsableFraction) - value(for: edge.opposite), 0)
        let clamped = min(max(points, 0), budget)
        // A sub-point drag means "nothing", not "a sliver" — see minimumMeaningful.
        let snapped = clamped < Self.minimumMeaningful ? 0 : clamped
        var copy = self
        switch edge {
        case .top: copy.top = snapped
        case .bottom: copy.bottom = snapped
        case .left: copy.left = snapped
        case .right: copy.right = snapped
        }
        return copy
    }

    /// A short human summary for the menu, e.g. "bottom 220 pt" or "top 40 · bottom 220 pt".
    /// Empty when nothing is kept clear, so a caller can test the string rather than deciding
    /// for a second time what "nothing" means.
    public var summary: String {
        let parts = edges.filter { value(for: $0) >= Self.minimumMeaningful }
            .map { "\($0.rawValue) \(Int(value(for: $0).rounded()))" }
        return parts.isEmpty ? "" : parts.joined(separator: " · ") + " pt"
    }

    /// Edge order for display: the two that shorten a screen first, then the two that narrow it.
    private var edges: [Edge] { [.top, .bottom, .left, .right] }

    /// Scale a pair of opposing margins down together until they leave `minUsableFraction` of
    /// the length behind. Proportional rather than first-come, so a rect that has been reserved
    /// past the limit keeps the *balance* the user asked for instead of favouring one side.
    private static func fit(_ a: CGFloat, _ b: CGFloat,
                            within length: CGFloat) -> (CGFloat, CGFloat) {
        let lo = max(a, 0), hi = max(b, 0)
        let budget = max(length * (1 - minUsableFraction), 0)
        let total = lo + hi
        guard total > budget else { return (lo, hi) }
        let scale = budget / total
        return (lo * scale, hi * scale)
    }
}

extension ScreenMargins {
    /// Reserved space for every display that has some, keyed by the display's name.
    ///
    /// Keyed by name, not by `CGDirectDisplayID`: ids are handed out afresh by the window server
    /// and a monitor that sleeps, gets unplugged, or comes back through a KVM can return under a
    /// different one. The strip you protected is a physical fact about that monitor, so it has to
    /// survive that — the same reasoning that has auto-arrange remember a display by name.
    public static func decodeBook(_ data: Data?) -> [String: ScreenMargins] {
        guard let data,
              let book = try? JSONDecoder().decode([String: ScreenMargins].self, from: data)
        else { return [:] }
        return book.filter { !$0.value.isEmpty }
    }

    /// Encode a book for storage, dropping displays with nothing kept clear so the setting
    /// doesn't accumulate an entry for every monitor ever plugged in. Nil means "don't write
    /// anything" — a caller keeps whatever is already stored rather than replacing a good
    /// setting with an empty one.
    public static func encodeBook(_ book: [String: ScreenMargins]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(book.filter { !$0.value.isEmpty })
    }
}
