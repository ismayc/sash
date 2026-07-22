import AppKit
import SashKit

/// Keeps one screen tiled for as long as it is switched on: it arranges every window on that
/// screen straight away, then watches for the *set* of windows changing — one opened, closed,
/// or moved onto or off the screen — and re-tiles.
///
/// Design notes:
///  - Only a change in **which** windows are present re-tiles. Resizing or nudging a window by
///    hand is left alone, so the toggle never fights you over a tweak you made on purpose.
///  - The watch is a 1-second poll of `CGWindowListCopyWindowInfo`, which is a single call for
///    the whole system. Enumerating windows through the Accessibility API — what the actual
///    arrange step does — costs a round-trip per window, too much to run on a timer.
///  - Re-tiling is idempotent: windows already in their tiles get set to the frame they
///    already have, so a spurious wake-up is harmless.
final class AutoArrangeController {

    /// Called when the watched screen disappears (unplugged) and the controller stops itself,
    /// so the menu can drop its checkmark.
    var onScreenLost: (() -> Void)?

    /// The display being kept tiled, or nil when the toggle is off.
    private(set) var displayID: CGDirectDisplayID?

    private var timer: Timer?
    private var lastWindowIDs: Set<CGWindowID> = []

    private let pollInterval: TimeInterval = 1

    var isRunning: Bool { displayID != nil }

    // MARK: - Toggle

    func start(on id: CGDirectDisplayID) {
        stop()
        displayID = id
        arrangeNow()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        displayID = nil
        lastWindowIDs = []
    }

    /// Tile the watched screen right now, whatever the window set looks like.
    func arrangeNow() {
        guard let screen = NSScreen.screen(withID: displayID) else { return }
        lastWindowIDs = onScreenWindowIDs(on: screen)
        arrange(on: screen)
    }

    // MARK: - Watching

    private func tick() {
        guard let screen = NSScreen.screen(withID: displayID) else {
            stop()
            onScreenLost?()
            return
        }
        // Never yank a window out from under a drag or resize in progress.
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let ids = onScreenWindowIDs(on: screen)
        guard ids != lastWindowIDs else { return }
        lastWindowIDs = ids
        arrange(on: screen)
    }

    /// Ids of on-screen, normal-layer windows centred on `screen`. Layer 0 skips the menu bar,
    /// the Dock, overlays and our own snap overlay; the rest is just "is it on this screen".
    private func onScreenWindowIDs(on screen: NSScreen) -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: Set<CGWindowID> = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: bounds) else { continue }
            let frame = Geometry.cgToAppKit(cgRect)
            if screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) { ids.insert(id) }
        }
        return ids
    }

    // MARK: - Arranging

    private func arrange(on screen: NSScreen) {
        let windows = WindowInfo.windows(on: screen)
        guard !windows.isEmpty else { return }

        let visible = screen.visibleFrame
        // Only the user's *own* layouts get to pre-empt the computed grid — the built-ins are
        // starting points, not a statement that three windows should always be thirds.
        let zones = AutoArrange.plan(count: windows.count,
                                     aspectRatio: visible.width / visible.height,
                                     savedLayouts: LayoutStore.shared.custom)
        let rects = zones.map { $0.rect(inVisibleFrame: visible) }
        let pairs = AutoArrange.assign(windows: windows.map(\.appKitFrame), zones: rects)
        for pair in pairs {
            WindowEngine.setFrame(windows[pair.window].element, appKitRect: rects[pair.zone])
        }
        // Let the windows settle before believing what they report — see WindowEngine
        // .settleDelay. Checking immediately reads mid-flight geometry and invents refusals
        // that aren't real.
        DispatchQueue.main.asyncAfter(deadline: .now() + WindowEngine.settleDelay) { [weak self] in
            self?.fitStubbornWindows(windows, pairs: pairs, zones: rects, within: visible)
        }
    }

    /// A window that ends up bigger than the tile it was given has a minimum size it won't go
    /// below (Slack and Music are common examples). Rather than leave it overlapping its
    /// neighbour, grow its tile to the size it insists on and take that space off the tile next
    /// to it — an uneven split that fits beats an even one that doesn't.
    private func fitStubbornWindows(_ windows: [ManagedWindow], pairs: [(zone: Int, window: Int)],
                                    zones: [CGRect], within visible: CGRect) {
        var minimums = [CGSize](repeating: .zero, count: zones.count)
        var anyStubborn = false
        for pair in pairs {
            guard let actual = WindowInfo.frame(of: windows[pair.window].element) else { continue }
            let asked = zones[pair.zone]
            if actual.width > asked.width + 1 || actual.height > asked.height + 1 {
                minimums[pair.zone] = actual.size
                anyStubborn = true
            }
        }
        guard anyStubborn else { return }

        let adjusted = ZoneReflow.adjusted(zones: zones, minimums: minimums)
        for pair in pairs where adjusted[pair.zone] != zones[pair.zone] {
            let element = windows[pair.window].element
            WindowEngine.setFrame(element, appKitRect: adjusted[pair.zone])
            // If even the widened tile wasn't enough, at least keep the window reachable.
            WindowEngine.keepOnScreenAfterSettling(element, within: visible)
        }
    }
}
