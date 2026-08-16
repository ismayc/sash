import AppKit
import SashKit

/// Keeps a set of screens tiled for as long as it is switched on: it arranges every window on
/// each of them straight away, then watches for the *set* of windows changing (one opened,
/// closed, or moved onto or off a screen) and re-tiles the screens that changed.
///
/// Design notes:
///  - Only a change in **which** windows are present re-tiles. Resizing or nudging a window by
///    hand is left alone, so the toggle never fights you over a tweak you made on purpose.
///  - The watch is a 1-second poll of `CGWindowListCopyWindowInfo`, which is a single call for
///    the whole system. Enumerating windows through the Accessibility API, which is what the
///    arrange step does, costs a round-trip per window: too much to run on a timer.
///  - Watching every monitor costs no more polling than watching one: the window list is
///    system-wide either way, so it is fetched once per tick and sorted by screen. A screen
///    whose windows didn't change isn't touched, so a quiet monitor stays quiet.
///  - Re-tiling is idempotent: windows already in their tiles get set to the frame they
///    already have, so a spurious wake-up is harmless.
final class AutoArrangeController {

    /// Called when a watched screen disappears (unplugged), so the menu can redraw. The
    /// preference itself lives in the app delegate and is deliberately left alone. A display
    /// that goes away pauses, and comes back on its own.
    var onScreenLost: (() -> Void)?

    /// Which arrangement to use for a given number of windows on the screen. Supplied by the app
    /// so the menu's per-count picks are honored; unset means the automatic behavior.
    var choiceForCount: (Int) -> AutoArrangeChoice = { _ in .automatic }

    /// The displays being kept tiled; empty when the toggle is off.
    private(set) var displayIDs: Set<CGDirectDisplayID> = []

    private var timer: Timer?
    private var lastWindowIDs: [CGDirectDisplayID: Set<CGWindowID>] = [:]

    private let pollInterval: TimeInterval = 1

    var isRunning: Bool { !displayIDs.isEmpty }

    // MARK: - Toggle

    func start(on ids: Set<CGDirectDisplayID>) {
        stop()
        guard !ids.isEmpty else { return }
        displayIDs = ids
        arrangeNow()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        displayIDs = []
        lastWindowIDs = [:]
    }

    /// Tile every watched screen right now, whatever the window sets look like.
    func arrangeNow() {
        let screens = watchedScreens()
        let byDisplay = windowIDsByDisplay(screens)
        for screen in screens {
            guard let id = screen.displayID else { continue }
            lastWindowIDs[id] = byDisplay[id] ?? []
            arrange(on: screen)
        }
    }

    // MARK: - Watching

    private func tick() {
        let screens = watchedScreens()
        // A watched display that has gone: forget it, and stop altogether once none are left.
        if screens.count != displayIDs.count {
            let present = Set(screens.compactMap(\.displayID))
            displayIDs = present
            lastWindowIDs = lastWindowIDs.filter { present.contains($0.key) }
            if present.isEmpty { stop() }
            onScreenLost?()
            if present.isEmpty { return }
        }
        // Never yank a window out from under a drag or resize in progress.
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let byDisplay = windowIDsByDisplay(screens)
        for screen in screens {
            guard let id = screen.displayID else { continue }
            let ids = byDisplay[id] ?? []
            guard ids != lastWindowIDs[id] else { continue }
            lastWindowIDs[id] = ids
            arrange(on: screen)
        }
    }

    /// The watched displays that are actually attached, in `NSScreen.screens` order.
    private func watchedScreens() -> [NSScreen] {
        NSScreen.screens.filter { $0.displayID.map(displayIDs.contains) ?? false }
    }

    /// Ids of on-screen, normal-layer windows, bucketed by the screen they sit on. Layer 0 skips
    /// the menu bar, the Dock, overlays and our own snap overlay; the rest is just "which screen
    /// is it on". One system-wide call covers every watched display at once.
    private func windowIDsByDisplay(_ screens: [NSScreen]) -> [CGDirectDisplayID: Set<CGWindowID>] {
        var byDisplay: [CGDirectDisplayID: Set<CGWindowID>] = [:]
        for screen in screens {
            if let id = screen.displayID { byDisplay[id] = [] }
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return byDisplay
        }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: bounds) else { continue }
            let frame = Geometry.cgToAppKit(cgRect)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            for screen in screens where screen.frame.contains(center) {
                if let display = screen.displayID { byDisplay[display, default: []].insert(id) }
                break
            }
        }
        return byDisplay
    }

    // MARK: - Arranging

    private func arrange(on screen: NSScreen) {
        let windows = WindowInfo.windows(on: screen)
        guard !windows.isEmpty else { return }

        // Not the whole visible frame: anything the user reserved on this screen is off limits.
        let usable = screen.workArea
        // Only the user's *own* layouts get to pre-empt the computed grid. The built-ins are
        // starting points, not a statement that three windows should always be thirds. They do
        // become pickable once the menu names one for this count.
        let zones = AutoArrange.plan(count: windows.count,
                                     aspectRatio: usable.width / usable.height,
                                     choice: choiceForCount(windows.count),
                                     savedLayouts: LayoutStore.shared.custom,
                                     pickable: LayoutStore.shared.all)
        let rects = zones.map { $0.rect(inVisibleFrame: usable) }
        let pairs = AutoArrange.assign(windows: windows.map(\.appKitFrame), zones: rects)
        for pair in pairs {
            WindowEngine.setFrame(windows[pair.window].element, appKitRect: rects[pair.zone])
        }
        // Let the windows settle before believing what they report. See WindowEngine
        // .settleDelay. Checking immediately reads mid-flight geometry and invents refusals
        // that aren't real.
        DispatchQueue.main.asyncAfter(deadline: .now() + WindowEngine.settleDelay) { [weak self] in
            self?.fitStubbornWindows(windows, pairs: pairs, zones: rects, within: usable)
        }
    }

    /// A window that ends up bigger than the tile it was given has a minimum size it won't go
    /// below (Slack and Music are common examples). Rather than leave it overlapping its
    /// neighbor, grow its tile to the size it insists on and take that space off the tile next
    /// to it: an uneven split that fits beats an even one that doesn't.
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
