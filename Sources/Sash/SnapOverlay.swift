import AppKit
import SashKit

/// The view drawn inside the overlay window: the armed layout's zones, with the one under
/// the cursor highlighted. Not flipped (AppKit bottom-left origin) so it lines up directly
/// with `Zone.appKitRect` after subtracting the screen origin.
final class SnapOverlayView: NSView {
    var zones: [Zone] = []
    var screen: NSScreen? { didSet { needsDisplay = true } }
    var highlighted: Int? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: CGRect) {
        guard let screen else { return }
        for (i, zone) in zones.enumerated() {
            let global = zone.appKitRect(on: screen)
            // Window-local: overlay window covers the whole screen frame.
            let r = CGRect(x: global.minX - screen.frame.minX,
                           y: global.minY - screen.frame.minY,
                           width: global.width, height: global.height).insetBy(dx: 6, dy: 6)
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            let isHot = (i == highlighted)
            (isHot ? NSColor.controlAccentColor.withAlphaComponent(0.45)
                   : NSColor.controlAccentColor.withAlphaComponent(0.18)).setFill()
            path.fill()
            (isHot ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.5)).setStroke()
            path.lineWidth = isHot ? 4 : 2
            path.stroke()

            if !zone.name.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: isHot ? 20 : 15),
                    .foregroundColor: NSColor.white.withAlphaComponent(isHot ? 1 : 0.7),
                ]
                let size = zone.name.size(withAttributes: attrs)
                zone.name.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                               withAttributes: attrs)
            }
        }
    }
}

/// A borderless, click-through, always-on-top window used to paint zone hints during a drag.
final class SnapOverlayWindow {
    private let window: NSWindow
    let view = SnapOverlayView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true          // never intercept the drag
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
    }

    func show(on screen: NSScreen, zones: [Zone]) {
        window.setFrame(screen.frame, display: false)
        view.frame = CGRect(origin: .zero, size: screen.frame.size)
        view.screen = screen
        view.zones = zones
        window.orderFrontRegardless()
    }

    func updateHighlight(_ index: Int?) {
        view.highlighted = index
    }

    func hide() {
        view.highlighted = nil
        window.orderOut(nil)
    }
}
