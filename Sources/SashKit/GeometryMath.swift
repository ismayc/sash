import Foundation
import CoreGraphics

/// Pure coordinate math, independent of any window server so it can be tested headlessly.
///
/// macOS has two clashing vertical coordinate systems:
///  - AppKit (`NSScreen`): origin bottom-left, +y up. Global origin is the primary screen's
///    bottom-left.
///  - Accessibility / CoreGraphics: origin top-left, +y down, (0,0) at the primary screen's
///    top-left.
///
/// `primaryHeight` is the primary screen's height — the pivot used to flip between them.
public enum GeometryMath {

    /// Convert an AppKit global rect (bottom-left origin) to an AX/CG rect (top-left origin).
    public static func appKitToCG(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Inverse of `appKitToCG` — CG/AX rect (top-left) back to AppKit global (bottom-left).
    public static func cgToAppKit(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Slide `rect` — keeping its size — so it sits inside `bounds`.
    ///
    /// This is the fallback for a window that refuses the size we asked for: some apps have a
    /// minimum (several Electron-based editors won't go below ~720pt tall), so a half-height
    /// zone leaves them overhanging. Sliding beats letting the overhang fall off the screen.
    ///
    /// When the rect is simply too big for `bounds` it is pinned to the top-left instead: an
    /// over-tall window keeps its title bar on screen, which is the edge you need to grab.
    /// Coordinates are AppKit global (bottom-left origin), so "top" is the high-y edge.
    public static func containing(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        let x = max(bounds.minX, min(rect.minX, bounds.maxX - rect.width))
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}
