import AppKit
import SashKit

/// The view you drag to reserve space on one monitor. It covers that screen, tints the part
/// Sash is allowed to use, and lets you pull any of the four edges inwards.
///
/// The tint sits on the area Sash *will* use, so the reserved strip stays see-through. That's
/// the whole point of doing this on the screen rather than in a number field: you are aiming at
/// a widget sitting on your desktop, so the widget has to stay visible while you aim.
final class ReservedSpaceView: NSView {

    /// The screen's visible frame in window-local coordinates: the area being divided up.
    var visible: CGRect = .zero { didSet { needsDisplay = true } }

    var margins: ScreenMargins = .none {
        didSet {
            needsDisplay = true
            onChange?(margins)
        }
    }

    /// Fired on every change, so the panel's readout keeps up with the drag.
    var onChange: ((ScreenMargins) -> Void)?

    /// How close to an edge counts as grabbing it.
    private let grabTolerance: CGFloat = 44

    private var dragging: ScreenMargins.Edge?

    override var acceptsFirstResponder: Bool { true }

    /// The area Sash may use with the margins as they stand.
    private var usable: CGRect { margins.applied(to: visible) }

    // MARK: - Drawing

    override func draw(_ dirtyRect: CGRect) {
        let area = usable

        // The reserved strips stay unpainted: whatever you are protecting shows through them.
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: area, xRadius: 8, yRadius: 8).fill()

        // Inset by half the line width: an edge sitting on the screen boundary would otherwise
        // have half its stroke clipped away, which is exactly the edge you most want to see.
        let border = NSBezierPath(roundedRect: area.insetBy(dx: 1.5, dy: 1.5), xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.setStroke()
        border.lineWidth = 3
        border.stroke()

        // A dashed line on the outer boundary, so a fully-reserved edge still reads as an edge.
        let outline = NSBezierPath(rect: visible)
        outline.lineWidth = 1
        outline.setLineDash([6, 6], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        outline.stroke()

        for edge in ScreenMargins.Edge.allCases {
            drawGrip(for: edge, on: area)
            drawMeasurement(for: edge, on: area)
        }
    }

    /// The bar you grab, drawn just *inside* the middle of each edge of the usable area rather
    /// than straddling it. An untouched screen has all four edges hard against the display's
    /// own, where a straddling handle would be half off the screen, invisible on the edge you
    /// have not moved yet, which is the one you are about to reach for.
    private func drawGrip(for edge: ScreenMargins.Edge, on area: CGRect) {
        let long: CGFloat = 90, thick: CGFloat = 10, pad: CGFloat = 4
        let rect: CGRect
        switch edge {
        case .top:    rect = CGRect(x: area.midX - long / 2, y: area.maxY - thick - pad, width: long, height: thick)
        case .bottom: rect = CGRect(x: area.midX - long / 2, y: area.minY + pad, width: long, height: thick)
        case .left:   rect = CGRect(x: area.minX + pad, y: area.midY - long / 2, width: thick, height: long)
        case .right:  rect = CGRect(x: area.maxX - thick - pad, y: area.midY - long / 2, width: thick, height: long)
        }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: thick / 2, yRadius: thick / 2).fill()
    }

    /// The size of a reserved strip, printed inside it: the number you'd otherwise have typed.
    private func drawMeasurement(for edge: ScreenMargins.Edge, on area: CGRect) {
        let points = margins.value(for: edge)
        guard points >= 1 else { return }
        let text = "\(Int(points.rounded())) pt"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let inset: CGFloat = 10
        let origin: CGPoint
        switch edge {
        case .top:    origin = CGPoint(x: area.midX - size.width / 2, y: area.maxY + inset)
        case .bottom: origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - inset)
        case .left:   origin = CGPoint(x: area.minX - size.width - inset, y: area.midY - size.height / 2)
        case .right:  origin = CGPoint(x: area.maxX + inset, y: area.midY - size.height / 2)
        }
        let plate = CGRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attrs)
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragging = edge(near: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let edge = dragging else { return }
        margins = margins.setting(edge, to: reach(of: edge, at: convert(event.locationInWindow, from: nil)),
                                  within: visible)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = nil
    }

    /// How far in from `edge` the pointer is, i.e. the margin that edge would have if dropped.
    private func reach(of edge: ScreenMargins.Edge, at point: CGPoint) -> CGFloat {
        switch edge {
        case .top:    return visible.maxY - point.y
        case .bottom: return point.y - visible.minY
        case .left:   return point.x - visible.minX
        case .right:  return visible.maxX - point.x
        }
    }

    /// The nearest grabbable edge of the usable area, or nil if the pointer is nowhere near one.
    /// Nearest rather than first-match so the corners don't favor one axis arbitrarily.
    private func edge(near point: CGPoint) -> ScreenMargins.Edge? {
        let area = usable
        var best: (edge: ScreenMargins.Edge, distance: CGFloat)?
        for edge in ScreenMargins.Edge.allCases {
            let distance: CGFloat
            let alongEdge: Bool
            switch edge {
            case .top:
                distance = abs(point.y - area.maxY)
                alongEdge = point.x >= area.minX - grabTolerance && point.x <= area.maxX + grabTolerance
            case .bottom:
                distance = abs(point.y - area.minY)
                alongEdge = point.x >= area.minX - grabTolerance && point.x <= area.maxX + grabTolerance
            case .left:
                distance = abs(point.x - area.minX)
                alongEdge = point.y >= area.minY - grabTolerance && point.y <= area.maxY + grabTolerance
            case .right:
                distance = abs(point.x - area.maxX)
                alongEdge = point.y >= area.minY - grabTolerance && point.y <= area.maxY + grabTolerance
            }
            guard alongEdge, distance <= grabTolerance else { continue }
            if best == nil || distance < best!.distance { best = (edge, distance) }
        }
        return best?.edge
    }
}

/// A borderless window that can still take the keyboard, so Return and Esc work in the editor.
final class ReservedSpaceWindow: NSWindow {
    var onKey: ((UInt16) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Unhandled keys fall through to the default beep-or-ignore behavior.
        if onKey?(event.keyCode) != true { super.keyDown(with: event) }
    }
}

/// Runs the reserved-space editor for one screen: puts the editor up, and reports back once the
/// user has saved or canceled.
final class ReservedSpaceController {

    private let screen: NSScreen
    private let displayName: String
    private let onFinish: () -> Void

    private var window: ReservedSpaceWindow?
    private let view = ReservedSpaceView()
    private var readout: NSTextField?
    private var screenObserver: NSObjectProtocol?

    init(screen: NSScreen, onFinish: @escaping () -> Void) {
        self.screen = screen
        self.displayName = screen.uniqueDisplayName
        self.onFinish = onFinish
    }

    // MARK: - Lifecycle

    func begin() {
        // Built at zero and moved, never with `screen:` in the initializer: that overload reads
        // the content rect relative to the given screen, so handing it a global frame offsets the
        // window by the screen's origin and the editor covers the wrong pixels. Measured, not
        // guessed: the tint came up 274 pt right and 30 pt down of where it belonged.
        let window = ReservedSpaceWindow(contentRect: .zero, styleMask: .borderless,
                                         backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.modalPanelWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.onKey = { [weak self] code in self?.handleKey(code) ?? false }

        let content = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        // The screen's own visible frame, expressed relative to the window covering that screen.
        view.visible = CGRect(x: screen.visibleFrame.minX - screen.frame.minX,
                              y: screen.visibleFrame.minY - screen.frame.minY,
                              width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        view.margins = ScreenMarginsStore.shared.margins(for: displayName)
        view.onChange = { [weak self] margins in self?.updateReadout(margins) }
        content.addSubview(view)

        let panel = makePanel()
        panel.frame.origin = CGPoint(x: view.visible.midX - panel.frame.width / 2,
                                     y: view.visible.midY - panel.frame.height / 2)
        content.addSubview(panel)

        window.contentView = content
        self.window = window

        // A monitor unplugged or rearranged mid-edit takes its editor with it: the geometry on
        // screen would no longer be the geometry being edited.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil,
            queue: .main) { [weak self] _ in self?.cancelIfScreenChanged() }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        updateReadout(view.margins)
    }

    private func finish() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        window?.orderOut(nil)
        window = nil
        onFinish()
    }

    @objc private func save() {
        ScreenMarginsStore.shared.set(view.margins, for: displayName)
        finish()
    }

    @objc private func cancel() {
        finish()
    }

    /// Hand the whole screen back without leaving the editor, so you can see what you undid.
    @objc private func useWholeScreen() {
        view.margins = .none
    }

    private func handleKey(_ code: UInt16) -> Bool {
        switch code {
        case 36, 76: save()             // Return, Enter
        case 53: cancel()               // Esc
        case 51, 117: useWholeScreen()  // Delete, forward-delete
        default: return false
        }
        return true
    }

    /// Cancel if the screen being edited has gone away or moved. Its own resolution changing is
    /// reason enough: the strip was measured against geometry that no longer exists.
    private func cancelIfScreenChanged() {
        guard let window else { return }
        let stillThere = NSScreen.screens.contains { $0.displayID == screen.displayID }
        if !stillThere || window.frame != screen.frame { cancel() }
    }

    // MARK: - The panel

    private func makePanel() -> NSView {
        let panel = NSView(frame: CGRect(x: 0, y: 0, width: 460, height: 150))
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        panel.layer?.cornerRadius = 14
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.cgColor

        let title = NSTextField(labelWithString: "Keep space clear on \(displayName)")
        title.font = .boldSystemFont(ofSize: 15)

        let readout = NSTextField(labelWithString: "")
        readout.font = .systemFont(ofSize: 12)
        readout.textColor = .secondaryLabelColor
        self.readout = readout

        let hint = NSTextField(labelWithString:
            "Drag any edge of the highlighted area inwards. ⏎ save · esc cancel · ⌫ whole screen")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "Use whole screen", target: self,
                                   action: #selector(useWholeScreen))
        clearButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [clearButton, cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [title, readout, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.frame = panel.bounds.insetBy(dx: 16, dy: 16)
        stack.autoresizingMask = [.width, .height]
        panel.addSubview(stack)
        return panel
    }

    private func updateReadout(_ margins: ScreenMargins) {
        readout?.stringValue = margins.isEmpty
            ? "Nothing kept clear. Sash may use the whole screen."
            : "Keeping clear: \(margins.summary)"
    }
}
