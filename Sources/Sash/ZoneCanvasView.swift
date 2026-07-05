import AppKit
import SashKit

/// An interactive canvas that draws a monitor to scale and lets you design zones on it:
/// drag a zone's body to move it, drag its bottom-right handle to resize, double-click an
/// empty spot to add one, and press Delete to remove the selection. Everything snaps to a
/// grid so zones tile cleanly. The view is flipped (top-left origin) to match `Zone`'s
/// coordinate convention exactly.
final class ZoneCanvasView: NSView {

    var zones: [Zone] = [] { didSet { needsDisplay = true } }
    /// zone index -> assigned window label, for on-canvas display.
    var assignmentLabels: [Int: String] = [:] { didSet { needsDisplay = true } }
    var selectedIndex: Int? { didSet { needsDisplay = true; onSelectionChange?(selectedIndex) } }
    var gridDivisions: Int = 12

    /// Called when zones change (move/resize/add/delete) and when selection changes.
    var onZonesChange: (() -> Void)?
    var onSelectionChange: ((Int?) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let handleSize: CGFloat = 14

    private enum DragMode { case move, resize }
    private struct DragState {
        var mode: DragMode
        var index: Int
        var startMouse: CGPoint
        var startZone: Zone
    }
    private var drag: DragState?

    // MARK: - Geometry helpers

    private func rect(for zone: Zone) -> CGRect {
        CGRect(x: zone.x * bounds.width, y: zone.y * bounds.height,
               width: zone.w * bounds.width, height: zone.h * bounds.height)
    }

    private func snap(_ fraction: CGFloat) -> CGFloat {
        let d = CGFloat(gridDivisions)
        return (fraction * d).rounded() / d
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: CGRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        // Monitor face + grid.
        NSColor(white: 0.15, alpha: 1).setFill()
        bounds.insetBy(dx: 1, dy: 1).fill()
        NSColor(white: 1, alpha: 0.06).setStroke()
        let grid = NSBezierPath()
        for i in 1..<gridDivisions {
            let x = bounds.width * CGFloat(i) / CGFloat(gridDivisions)
            grid.move(to: CGPoint(x: x, y: 0)); grid.line(to: CGPoint(x: x, y: bounds.height))
            let y = bounds.height * CGFloat(i) / CGFloat(gridDivisions)
            grid.move(to: CGPoint(x: 0, y: y)); grid.line(to: CGPoint(x: bounds.width, y: y))
        }
        grid.lineWidth = 0.5
        grid.stroke()

        // Zones.
        for (i, zone) in zones.enumerated() {
            let r = rect(for: zone).insetBy(dx: 2, dy: 2)
            let selected = (i == selectedIndex)
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            (selected ? NSColor.controlAccentColor.withAlphaComponent(0.35)
                      : NSColor.controlAccentColor.withAlphaComponent(0.18)).setFill()
            path.fill()
            (selected ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.6)).setStroke()
            path.lineWidth = selected ? 2 : 1
            path.stroke()

            // Labels: zone name + assigned window.
            let title = zone.name
            let sub = assignmentLabels[i]
            drawText(title, in: r, sub: sub)

            // Resize handle (bottom-right).
            if selected {
                let h = CGRect(x: r.maxX - handleSize, y: r.maxY - handleSize, width: handleSize, height: handleSize)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: h, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    private func drawText(_ title: String, in r: CGRect, sub: String?) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor(white: 1, alpha: 0.7),
        ]
        let titleSize = title.size(withAttributes: titleAttrs)
        var y = r.midY - (sub == nil ? titleSize.height / 2 : titleSize.height)
        title.draw(at: CGPoint(x: r.midX - titleSize.width / 2, y: y), withAttributes: titleAttrs)
        if let sub {
            let ss = sub.size(withAttributes: subAttrs)
            y += titleSize.height + 2
            sub.draw(at: CGPoint(x: r.midX - min(ss.width, r.width) / 2, y: y), withAttributes: subAttrs)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2, hitZone(at: p) == nil {
            addZone(at: p)
            return
        }
        guard let i = hitZone(at: p) else { selectedIndex = nil; return }
        selectedIndex = i
        let r = rect(for: zones[i]).insetBy(dx: 2, dy: 2)
        let handle = CGRect(x: r.maxX - handleSize, y: r.maxY - handleSize, width: handleSize, height: handleSize)
        drag = DragState(mode: handle.contains(p) ? .resize : .move,
                         index: i, startMouse: p, startZone: zones[i])
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = drag else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = (p.x - state.startMouse.x) / bounds.width
        let dy = (p.y - state.startMouse.y) / bounds.height
        var z = state.startZone

        switch state.mode {
        case .move:
            z.x = clamp(snap(state.startZone.x + dx), max: 1 - z.w)
            z.y = clamp(snap(state.startZone.y + dy), max: 1 - z.h)
        case .resize:
            let unit = 1 / CGFloat(gridDivisions)
            z.w = min(max(snap(state.startZone.w + dx), unit), 1 - z.x)
            z.h = min(max(snap(state.startZone.h + dy), unit), 1 - z.y)
        }
        zones[state.index] = z
        onZonesChange?()
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        onZonesChange?()
    }

    override func keyDown(with event: NSEvent) {
        // 51 = delete, 117 = forward-delete
        if (event.keyCode == 51 || event.keyCode == 117), let i = selectedIndex {
            zones.remove(at: i)
            selectedIndex = nil
            onZonesChange?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Helpers

    private func hitZone(at p: CGPoint) -> Int? {
        // Topmost (last drawn) wins.
        for i in zones.indices.reversed() where rect(for: zones[i]).contains(p) { return i }
        return nil
    }

    private func addZone(at p: CGPoint) {
        let unit: CGFloat = gridDivisions >= 4 ? 1.0 / CGFloat(gridDivisions) : 0.25
        let w = max(0.25, unit * CGFloat(gridDivisions) / 4) // ~quarter width by default
        let h = 0.5
        var x = snap(p.x / bounds.width - w / 2)
        var y = snap(p.y / bounds.height - h / 2)
        x = clamp(x, max: 1 - w)
        y = clamp(y, max: 1 - h)
        zones.append(Zone(name: "Zone \(zones.count + 1)", x: x, y: y, w: w, h: h))
        selectedIndex = zones.count - 1
        onZonesChange?()
    }

    private func clamp(_ v: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(0, v), Swift.max(0, hi))
    }
}
