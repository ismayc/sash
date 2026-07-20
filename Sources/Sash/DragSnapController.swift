import AppKit
import ApplicationServices
import SashKit

/// Everything needed to decide whether/where a dragged window should snap.
struct DragSnapConfig {
    let layout: Layout
    /// Restrict snapping to one monitor; nil means any monitor.
    let targetDisplayID: CGDirectDisplayID?
    /// Only snap while Shift is held (opt-in per-drag mode).
    ///
    /// Shift rather than Control: macOS rewrites ⌃-click into a secondary click, so a left-drag
    /// never begins while Control is down and the mouse monitors below see nothing to snap.
    let requireShiftHeld: Bool
}

/// Watches global mouse activity and, while an armed layout is active, snaps whatever window
/// you drag into whichever zone you release it over — FancyZones-style.
///
/// Design notes:
///  - Detecting a *window move* (versus a text selection or scroll) is the crux: we only
///    engage once the window under the cursor has actually moved a few pixels. Non-move drags
///    never shift a window's frame, so that signal is clean.
///  - Per-monitor: if a target display is set, we ignore drags on every other screen, leaving
///    them free to arrange by hand.
///  - Esc cancels the in-progress snap and drops the window wherever it is.
final class DragSnapController {

    private let configProvider: () -> DragSnapConfig?
    private let overlay = SnapOverlayWindow()
    private var monitors: [Any] = []

    // Per-drag state.
    private var candidate: AXUIElement?
    private var startPosition: CGPoint?
    private var engaged = false
    private var cancelled = false
    private var activeScreen: NSScreen?
    private var overlayVisible = false

    private let moveThreshold: CGFloat = 6
    private let escKeyCode: UInt16 = 53

    init(configProvider: @escaping () -> DragSnapConfig?) {
        self.configProvider = configProvider
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        add(.leftMouseDown) { [weak self] _ in self?.mouseDown() }
        add(.leftMouseDragged) { [weak self] _ in self?.mouseDragged() }
        add(.leftMouseUp) { [weak self] _ in self?.mouseUp() }
        add(.keyDown) { [weak self] event in self?.keyDown(event) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        reset()
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(m)
        }
    }

    // MARK: - Drag lifecycle

    private func mouseDown() {
        guard configProvider() != nil else { return }
        candidate = WindowEngine.windowUnderCursor()
        startPosition = candidate.flatMap { WindowEngine.position(of: $0) }
        engaged = false
        cancelled = false
    }

    private func mouseDragged() {
        guard let config = configProvider(), !cancelled,
              let win = candidate, let start = startPosition,
              let now = WindowEngine.position(of: win) else { return }

        let moved = hypot(now.x - start.x, now.y - start.y) >= moveThreshold
        let screen = Geometry.screenUnderMouse
        let onTarget = config.targetDisplayID == nil || screen.displayID == config.targetDisplayID
        // Read the live flags rather than the event's, so pressing Shift mid-drag counts.
        let shiftOK = !config.requireShiftHeld || NSEvent.modifierFlags.contains(.shift)

        guard moved, onTarget, shiftOK else {
            hideOverlay()
            engaged = false
            return
        }

        if screen !== activeScreen || !overlayVisible {
            activeScreen = screen
            overlay.show(on: screen, zones: config.layout.zones)
            overlayVisible = true
        }
        overlay.updateHighlight(zoneIndexUnderMouse(config.layout, on: screen))
        engaged = true
    }

    private func mouseUp() {
        defer { reset() }
        guard engaged, !cancelled,
              let config = configProvider(), let screen = activeScreen,
              let idx = zoneIndexUnderMouse(config.layout, on: screen),
              let win = candidate else { return }
        WindowEngine.setFrame(win, appKitRect: config.layout.zones[idx].appKitRect(on: screen))
    }

    private func keyDown(_ event: NSEvent) {
        // Esc during an active snap cancels it — the window drops where it is.
        if event.keyCode == escKeyCode, engaged {
            cancelled = true
            engaged = false
            hideOverlay()
        }
    }

    // MARK: - Helpers

    private func zoneIndexUnderMouse(_ layout: Layout, on screen: NSScreen) -> Int? {
        let mouse = NSEvent.mouseLocation
        // Topmost (last) zone wins when zones overlap.
        for i in layout.zones.indices.reversed()
        where layout.zones[i].appKitRect(on: screen).contains(mouse) {
            return i
        }
        return nil
    }

    private func hideOverlay() {
        if overlayVisible {
            overlay.hide()
            overlayVisible = false
            activeScreen = nil
        }
    }

    private func reset() {
        candidate = nil
        startPosition = nil
        engaged = false
        cancelled = false
        hideOverlay()
    }
}
