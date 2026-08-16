import Foundation
import CoreGraphics

/// How wide auto-arrange casts its net: nothing, every display attached, or a chosen few.
///
/// `allDisplays` is deliberately not the same as ticking every monitor by hand. It is a standing
/// choice (plug a screen in later and it is kept tiled too, with no trip back to the menu),
/// where a hand-picked set means *those* monitors and nothing else, however many arrive after.
/// Both survive a display going away: which displays a scope resolves to is worked out fresh
/// from what's plugged in right now, so an absent monitor pauses rather than cancels.
///
/// Pure, so the resolution rule is testable without a window server.
public enum AutoArrangeScope: Equatable {
    /// Auto-arrange is off; nothing is kept tiled.
    case off
    /// Every attached display, including ones plugged in later.
    case allDisplays
    /// Exactly these displays, each kept tiled while it is attached and waited for while it
    /// isn't. An empty set means the same as `off`; `toggling(_:attached:)` never produces one.
    case displays(Set<CGDirectDisplayID>)

    private static let offRawValue = "off"
    private static let allRawValue = "all"
    private static let displaysPrefix = "displays:"
    /// The one-display-only form written by versions before multi-monitor picking.
    private static let legacyDisplayPrefix = "display:"

    /// A string form for UserDefaults. Ids are sorted so the same set always stores identically.
    public var rawValue: String {
        switch self {
        case .off:
            return Self.offRawValue
        case .allDisplays:
            return Self.allRawValue
        case .displays(let ids):
            return Self.displaysPrefix + ids.sorted().map(String.init).joined(separator: ",")
        }
    }

    /// Anything unrecognized reads back as `.off`, so a stale or hand-edited preference leaves
    /// auto-arrange alone rather than tiling a display the user never asked for. The superseded
    /// `display:5` form still reads, so an existing install keeps tiling the screen it had.
    public init(rawValue: String) {
        if rawValue == Self.allRawValue {
            self = .allDisplays
        } else if rawValue.hasPrefix(Self.displaysPrefix) {
            self = Self.parse(rawValue.dropFirst(Self.displaysPrefix.count))
        } else if rawValue.hasPrefix(Self.legacyDisplayPrefix) {
            self = Self.parse(rawValue.dropFirst(Self.legacyDisplayPrefix.count))
        } else {
            self = .off
        }
    }

    private static func parse(_ list: Substring) -> AutoArrangeScope {
        let ids = list.split(separator: ",").compactMap { CGDirectDisplayID($0) }
        return ids.isEmpty ? .off : .displays(Set(ids))
    }

    /// Whether this display is one of the ones being kept tiled, which is what the menu ticks.
    public func includes(_ id: CGDirectDisplayID) -> Bool {
        switch self {
        case .off: return false
        case .allDisplays: return true
        case .displays(let ids): return ids.contains(id)
        }
    }

    /// The displays to keep tiled right now, given what is attached.
    ///
    /// A chosen display that isn't attached resolves away: paused, not canceled, exactly as
    /// `DisplayTarget` describes. The order follows `attached`, so callers see displays in the
    /// system's own order rather than in id order.
    public func active(attached: [CGDirectDisplayID]) -> [CGDirectDisplayID] {
        switch self {
        case .off:
            return []
        case .allDisplays:
            return attached
        case .displays(let ids):
            return attached.filter { ids.contains($0) }
        }
    }

    /// The scope you get by ticking or unticking one display.
    ///
    /// Unticking a display while *all* of them are on means "all the ones I have, except this".
    /// The monitors left over are named explicitly, because "all" has to keep meaning "and
    /// whatever I plug in next". Unticking the last one leaves `off` rather than an empty set.
    public func toggling(_ id: CGDirectDisplayID, attached: [CGDirectDisplayID]) -> AutoArrangeScope {
        var ids: Set<CGDirectDisplayID>
        switch self {
        case .off: ids = []
        case .allDisplays: ids = Set(attached)
        case .displays(let chosen): ids = chosen
        }
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        return ids.isEmpty ? .off : .displays(ids)
    }
}
