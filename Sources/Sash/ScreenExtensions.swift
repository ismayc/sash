import AppKit
import SashKit

/// AppKit-side bridges between the pure Kit geometry and live `NSScreen`s. Not unit-tested
/// (needs a window server); exercised manually.
enum Geometry {

    /// The primary screen owns the global origin; its height is the flip pivot.
    static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        return primary?.frame.height ?? 0
    }

    /// Convert an AppKit global rect to an AX/CG rect using the live primary height.
    static func appKitToCG(_ rect: CGRect) -> CGRect {
        GeometryMath.appKitToCG(rect, primaryHeight: primaryHeight)
    }

    /// Convert an AX/CG rect back to AppKit global coordinates.
    static func cgToAppKit(_ rect: CGRect) -> CGRect {
        GeometryMath.cgToAppKit(rect, primaryHeight: primaryHeight)
    }

    /// The screen currently containing the mouse cursor.
    static var screenUnderMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

extension Zone {
    /// Resolve this zone to an AppKit global rect on the given screen.
    func appKitRect(on screen: NSScreen) -> CGRect {
        rect(inVisibleFrame: screen.visibleFrame)
    }
}

extension NSScreen {
    /// The CoreGraphics display id backing this screen, used to pin drag-snap to one monitor.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Look up a screen by its CoreGraphics display id.
    static func screen(withID id: CGDirectDisplayID?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { $0.displayID == id }
    }

    /// The monitor's own name, e.g. "LG ULTRAWIDE" or "Built-in Retina Display". Falls back to a
    /// positional name for displays that report nothing (some capture cards and KVMs).
    func displayName(index: Int) -> String {
        let name = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Display \(index + 1)" : name
    }

    /// Names for every attached screen, in `NSScreen.screens` order. Identical models — two of the
    /// same LG, say — get a "(1)", "(2)"… suffix so the menu stays unambiguous.
    static var uniqueDisplayNames: [String] {
        let base = screens.enumerated().map { $1.displayName(index: $0) }
        var totals: [String: Int] = [:]
        for name in base { totals[name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return base.map { name in
            guard totals[name, default: 0] > 1 else { return name }
            seen[name, default: 0] += 1
            return "\(name) (\(seen[name, default: 1]))"
        }
    }

    /// The name for this screen, disambiguated against the other attached screens.
    var uniqueDisplayName: String {
        guard let i = NSScreen.screens.firstIndex(of: self) else { return displayName(index: 0) }
        return NSScreen.uniqueDisplayNames[i]
    }

    /// A short human label, e.g. "LG ULTRAWIDE — 3440×1440".
    func label(index: Int) -> String {
        let px = Int(frame.width * backingScaleFactor)
        let py = Int(frame.height * backingScaleFactor)
        let names = NSScreen.uniqueDisplayNames
        let name = index < names.count ? names[index] : displayName(index: index)
        return "\(name) — \(px)×\(py)"
    }
}
