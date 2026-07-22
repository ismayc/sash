import AppKit
import ApplicationServices
import SashKit

/// Private but long-stable API (used by yabai, Rectangle, etc.) that returns the
/// CoreGraphics window id for an Accessibility element. This is what lets us reliably
/// match an AX window to an on-screen window without fuzzy title/frame heuristics.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: inout CGWindowID) -> AXError

/// A concrete, movable window belonging to some running app.
struct ManagedWindow: Identifiable, Hashable {
    let id: CGWindowID
    let appName: String
    let title: String
    let pid: pid_t
    let element: AXUIElement
    /// Current frame in AppKit global coordinates (bottom-left origin).
    let appKitFrame: CGRect

    /// Human label for pickers, e.g. "Positron — Untitled".
    var label: String {
        title.isEmpty ? appName : "\(appName) — \(title)"
    }

    static func == (lhs: ManagedWindow, rhs: ManagedWindow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum WindowInfo {

    /// All standard, non-minimized windows of regular (Dock-visible) apps.
    static func allWindows() -> [ManagedWindow] {
        var result: [ManagedWindow] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden {
            let pid = app.processIdentifier
            let appEl = AXUIElementCreateApplication(pid)
            guard let windows = copyWindows(appEl) else { continue }
            for win in windows {
                guard isStandardWindow(win), let frame = axFrame(win) else { continue }
                var wid: CGWindowID = 0
                guard _AXUIElementGetWindow(win, &wid) == .success, wid != 0 else { continue }
                result.append(ManagedWindow(
                    id: wid,
                    appName: app.localizedName ?? "App",
                    title: axString(win, kAXTitleAttribute) ?? "",
                    pid: pid,
                    element: win,
                    appKitFrame: cgToAppKit(frame)
                ))
            }
        }
        return result
    }

    /// Windows whose center lies on the given screen.
    static func windows(on screen: NSScreen) -> [ManagedWindow] {
        allWindows().filter { screen.frame.contains(CGPoint(x: $0.appKitFrame.midX, y: $0.appKitFrame.midY)) }
    }

    // MARK: - AX plumbing

    private static func copyWindows(_ appEl: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
              let arr = value as? [AXUIElement] else { return nil }
        return arr
    }

    private static func isStandardWindow(_ win: AXUIElement) -> Bool {
        // Skip minimized windows.
        if let minimized = axBool(win, kAXMinimizedAttribute), minimized { return false }
        // Prefer standard windows (excludes panels/sheets) when a subrole is present.
        if let subrole = axString(win, kAXSubroleAttribute) {
            return subrole == (kAXStandardWindowSubrole as String)
        }
        return true
    }

    /// A window's current frame in AppKit global coordinates — used to check what a window
    /// actually accepted after we asked it to move.
    static func frame(of win: AXUIElement) -> CGRect? {
        axFrame(win).map(cgToAppKit)
    }

    /// A window's frame in CoreGraphics/AX coordinates (top-left origin).
    private static func axFrame(_ win: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    /// Convert a CG/AX rect (top-left origin) back to AppKit global coords (bottom-left).
    private static func cgToAppKit(_ rect: CGRect) -> CGRect {
        let h = Geometry.primaryHeight
        return CGRect(x: rect.origin.x, y: h - rect.origin.y - rect.height,
                      width: rect.width, height: rect.height)
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return (value as? Bool)
    }
}
