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
}
