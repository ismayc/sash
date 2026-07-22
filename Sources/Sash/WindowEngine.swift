import AppKit
import ApplicationServices
import SashKit

/// Reads and writes window frames through the Accessibility API.
enum WindowEngine {

    /// The focused window of the frontmost application, if any.
    static func focusedWindow() -> AXUIElement? {
        // The system-wide element exposes the currently focused app.
        let system = AXUIElementCreateSystemWide()
        guard let app = copyElement(system, kAXFocusedApplicationAttribute) else {
            // Fall back to NSWorkspace's notion of the frontmost app.
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
            let appEl = AXUIElementCreateApplication(pid)
            return copyElement(appEl, kAXFocusedWindowAttribute)
        }
        return copyElement(app, kAXFocusedWindowAttribute)
    }

    /// How long to let a window settle before trusting what it reports back.
    ///
    /// Setting a frame is not synchronous: an app processes the change on its own run loop and
    /// only then reports its new geometry. Electron-based editors are the worst offenders —
    /// read `kAXSize` straight after writing it and you get a mid-flight value, which is
    /// exactly how "it refused the size" gets mistaken for the truth. Everything that inspects
    /// the result of a move has to wait first.
    static let settleDelay: TimeInterval = 0.35

    /// Move + resize a window to an AppKit global rect. Order matters: some apps clamp the
    /// size against the *old* position, so we set position, then size, then position again.
    static func setFrame(_ window: AXUIElement, appKitRect: CGRect) {
        let cg = Geometry.appKitToCG(appKitRect)
        setPosition(window, CGPoint(x: cg.origin.x, y: cg.origin.y))
        setSize(window, CGSize(width: cg.width, height: cg.height))
        setPosition(window, CGPoint(x: cg.origin.x, y: cg.origin.y))
    }

    /// Once the window has settled, slide it back inside `bounds` if it is overhanging — an app
    /// that genuinely won't shrink to its zone should at least stay somewhere you can grab it.
    static func keepOnScreenAfterSettling(_ window: AXUIElement, within bounds: CGRect) {
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            guard let actual = WindowInfo.frame(of: window) else { return }
            let corrected = GeometryMath.containing(actual, within: bounds)
            guard corrected.origin != actual.origin else { return }
            let cg = Geometry.appKitToCG(corrected)
            setPosition(window, CGPoint(x: cg.origin.x, y: cg.origin.y))
        }
    }

    /// Snap a specific window into `zone` on a given screen.
    static func snap(_ window: ManagedWindow, to zone: Zone, on screen: NSScreen) {
        setFrame(window.element, appKitRect: zone.appKitRect(on: screen))
        keepOnScreenAfterSettling(window.element, within: screen.visibleFrame)
    }

    /// Snap the currently focused window into `zone` on the screen under the mouse.
    @discardableResult
    static func snapFocused(to zone: Zone, on screen: NSScreen = Geometry.screenUnderMouse) -> Bool {
        guard let win = focusedWindow() else { return false }
        setFrame(win, appKitRect: zone.appKitRect(on: screen))
        keepOnScreenAfterSettling(win, within: screen.visibleFrame)
        return true
    }

    /// The top-level window currently under the mouse pointer, if any.
    static func windowUnderCursor() -> AXUIElement? {
        let mouse = NSEvent.mouseLocation
        // AXUIElementCopyElementAtPosition wants CG (top-left) coordinates.
        let cgY = Geometry.primaryHeight - mouse.y
        let system = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(mouse.x), Float(cgY), &elementRef) == .success,
              let element = elementRef else { return nil }
        return windowElement(from: element)
    }

    /// A window's current top-left position in CG coordinates (for detecting movement).
    static func position(of window: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &ref) == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(ref as! AXValue, .cgPoint, &point)
        return point
    }

    /// Resolve an arbitrary UI element to its containing window element.
    private static func windowElement(from element: AXUIElement) -> AXUIElement? {
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           (roleRef as? String) == (kAXWindowRole as String) {
            return element
        }
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &winRef) == .success,
           let win = winRef {
            return (win as! AXUIElement)
        }
        return nil
    }

    // MARK: - Low-level AX helpers

    private static func copyElement(_ element: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard err == .success, let v = value else { return nil }
        // AXUIElement is a CFType; this cast is safe when the attribute is an element.
        return (v as! AXUIElement)
    }

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}
