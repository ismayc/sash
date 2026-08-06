import AppKit
import ServiceManagement
import SashKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let hotkeys = HotkeyManager()
    private var customWindow: CustomSetupWindowController?

    // Drag-to-snap state (persisted in UserDefaults).
    private var activeLayout: Layout?
    private var activeDisplayID: CGDirectDisplayID?
    private var requireShiftHeld = false

    // Auto-arrange state (persisted in UserDefaults).
    /// The screen the user *asked* to keep tiled. Deliberately not cleared when that screen goes
    /// away — a monitor asleep or unplugged pauses auto-arrange, and it resumes by itself once
    /// the screen is back. What is actually running is `autoArrange.displayID`.
    private var autoArrangeDisplayID: CGDirectDisplayID?
    /// The chosen screen's name, kept so the menu can still say which display it is waiting for
    /// after that display has stopped reporting one.
    private var autoArrangeDisplayName: String?
    private var autoArrangeChoices: [Int: AutoArrangeChoice] = [:]

    /// Window counts that get their own layout picker in the menu. Three and four are where
    /// taste actually differs — an asymmetric custom split one day, plain thirds or quarters
    /// the next — so those are the counts worth a standing choice.
    private static let choosableCounts = [3, 4]

    /// Menu title for "ignore saved layouts, just tile evenly".
    private static let evenGridTitle = "Even grid"

    private static func autoArrangeChoiceKey(_ count: Int) -> String {
        "autoArrangeChoice.\(count)"
    }

    /// What a picker entry means, carried on the menu item.
    private struct AutoArrangePick {
        let count: Int
        let choice: AutoArrangeChoice
    }

    private lazy var autoArrange: AutoArrangeController = {
        let controller = AutoArrangeController()
        // The controller has already stopped itself; keep the preference so the screen coming
        // back switches auto-arrange on again, and just let the menu redraw as paused.
        controller.onScreenLost = { [weak self] in
            self?.rebuildMenu()
        }
        controller.choiceForCount = { [weak self] count in
            self?.autoArrangeChoices[count] ?? .automatic
        }
        return controller
    }()

    private lazy var dragSnap = DragSnapController(configProvider: { [weak self] in
        guard let self, let layout = self.activeLayout else { return nil }
        return DragSnapConfig(layout: layout,
                              targetDisplayID: self.activeDisplayID,
                              requireShiftHeld: self.requireShiftHeld)
    })

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadHoldPreference()
        loadAutoArrangeChoices()
        if defaults.object(forKey: "activeDisplayID") != nil {
            activeDisplayID = CGDirectDisplayID(defaults.integer(forKey: "activeDisplayID"))
        }

        setupStatusItem()

        if !Accessibility.isTrusted { Accessibility.requestIfNeeded() }
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu),
            name: LayoutStore.didChange, object: nil)
        // Displays attached, removed, woken, or re-arranged. Without this the monitor pickers
        // keep whatever was plugged in at launch.
        NotificationCenter.default.addObserver(self, selector: #selector(refreshMonitors),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        setupStaticHotkeys()

        // Restore a previously armed drag-snap layout.
        if let name = defaults.string(forKey: "activeLayoutName"),
           let layout = LayoutStore.shared.layout(named: name) {
            armDragSnap(layout, displayID: activeDisplayID, persist: false)
        }

        // Restore auto-arrange. It starts only if that screen is attached right now, and waits
        // for it otherwise rather than dropping the preference.
        if defaults.object(forKey: "autoArrangeDisplayID") != nil {
            autoArrangeDisplayID = CGDirectDisplayID(defaults.integer(forKey: "autoArrangeDisplayID"))
            autoArrangeDisplayName = defaults.string(forKey: "autoArrangeDisplayName")
            reconcileAutoArrange()
            rebuildMenu()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2",
                                   accessibilityDescription: "Sash")
        }
        // One menu object for the app's lifetime, refilled on demand — see `menuNeedsUpdate`.
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    @objc private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Permission status.
        if Accessibility.isTrusted {
            let ok = NSMenuItem(title: "Accessibility: granted", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            let grant = NSMenuItem(title: "⚠︎ Grant Accessibility permission…",
                                   action: #selector(grantPermission), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }
        menu.addItem(.separator())

        // --- Drag-to-snap controls ---
        menu.addItem(dragLayoutMenuItem())
        menu.addItem(monitorMenuItem())

        let holdItem = NSMenuItem(title: "Snap only while holding ⇧ (Shift)",
                                  action: #selector(toggleHoldShift), keyEquivalent: "")
        holdItem.target = self
        holdItem.state = requireShiftHeld ? .on : .off
        menu.addItem(holdItem)

        let hint = NSMenuItem(title: "Tip: press Esc mid-drag to cancel a snap", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        // --- Auto-arrange ---
        menu.addItem(autoArrangeMenuItem())
        for count in Self.choosableCounts {
            menu.addItem(autoArrangeChoiceMenuItem(count: count))
        }
        let autoHint = NSMenuItem(title: "Tip: ⌃⌥⌘A toggles it on the screen under the mouse",
                                  action: nil, keyEquivalent: "")
        autoHint.isEnabled = false
        menu.addItem(autoHint)
        menu.addItem(.separator())

        // Custom Setup.
        let custom = NSMenuItem(title: "Custom Setup…", action: #selector(openCustomSetup), keyEquivalent: "n")
        custom.target = self
        menu.addItem(custom)
        menu.addItem(.separator())

        // Snap the focused window into any layout's zone.
        for layout in LayoutStore.shared.all {
            let item = NSMenuItem(title: layout.name, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for zone in layout.zones {
                let zoneItem = NSMenuItem(title: zone.name, action: #selector(snapToZone(_:)), keyEquivalent: "")
                zoneItem.target = self
                zoneItem.representedObject = zone
                submenu.addItem(zoneItem)
            }
            if LayoutStore.shared.custom.contains(where: { $0.name == layout.name }) {
                submenu.addItem(.separator())
                let del = NSMenuItem(title: "Delete “\(layout.name)”", action: #selector(deleteLayout(_:)), keyEquivalent: "")
                del.target = self
                del.representedObject = layout.name
                submenu.addItem(del)
            }
            item.submenu = submenu
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Preferences.
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit Sash", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func dragLayoutMenuItem() -> NSMenuItem {
        let header = NSMenuItem(title: "Drag windows into:  \(activeLayout?.name ?? "Off")",
                                action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let off = NSMenuItem(title: "Off", action: #selector(armLayout(_:)), keyEquivalent: "")
        off.target = self
        off.state = (activeLayout == nil) ? .on : .off
        submenu.addItem(off)
        submenu.addItem(.separator())
        for layout in LayoutStore.shared.all {
            let item = NSMenuItem(title: layout.name, action: #selector(armLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.name
            item.state = (activeLayout?.name == layout.name) ? .on : .off
            submenu.addItem(item)
        }
        header.submenu = submenu
        return header
    }

    private func monitorMenuItem() -> NSMenuItem {
        let current = NSScreen.screen(withID: activeDisplayID)
        let header = NSMenuItem(title: "Snap on monitor:  \(current?.uniqueDisplayName ?? "Any")",
                                action: nil, keyEquivalent: "")
        header.submenu = monitorSubmenu(noneTitle: "Any monitor", selected: activeDisplayID,
                                        action: #selector(chooseMonitor(_:)))
        return header
    }

    private func autoArrangeMenuItem() -> NSMenuItem {
        let header = NSMenuItem(title: "Auto-arrange windows on:  \(autoArrangeStatus)",
                                action: nil, keyEquivalent: "")
        header.submenu = monitorSubmenu(noneTitle: "Off", selected: autoArrangeDisplayID,
                                        action: #selector(chooseAutoArrangeMonitor(_:)))
        return header
    }

    /// What the auto-arrange header reads. A chosen-but-absent screen says so by name instead of
    /// reading "Off", because the preference is paused, not cancelled — "Off" would be a lie that
    /// invites you to switch it on again.
    private var autoArrangeStatus: String {
        guard let desired = autoArrangeDisplayID else { return "Off" }
        if let screen = NSScreen.screen(withID: desired) { return screen.uniqueDisplayName }
        return "\(autoArrangeDisplayName ?? "Chosen display") — waiting, not connected"
    }

    /// A picker for how auto-arrange should tile exactly `count` windows: the even grid, then
    /// every layout — built-in or custom — that has that many non-overlapping zones.
    ///
    /// The tick sits on whatever is *actually* in force, which before anything is picked is
    /// whatever auto-arrange would have chosen on its own. So the menu always reads as the truth
    /// rather than as an empty preference.
    private func autoArrangeChoiceMenuItem(count: Int) -> NSMenuItem {
        let store = LayoutStore.shared
        let choice = autoArrangeChoices[count] ?? .automatic
        let inForce = AutoArrange.resolvedLayout(count: count, choice: choice,
                                                 savedLayouts: store.custom, pickable: store.all)

        let header = NSMenuItem(title: "When \(count) windows:  \(inForce?.name ?? Self.evenGridTitle)",
                                action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let grid = NSMenuItem(title: Self.evenGridTitle,
                              action: #selector(chooseAutoArrangeLayout(_:)), keyEquivalent: "")
        grid.target = self
        grid.representedObject = AutoArrangePick(count: count, choice: .grid)
        grid.state = (inForce == nil) ? .on : .off
        submenu.addItem(grid)
        submenu.addItem(.separator())

        for layout in AutoArrange.candidates(count: count, from: store.all) {
            let item = NSMenuItem(title: layout.name,
                                  action: #selector(chooseAutoArrangeLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = AutoArrangePick(count: count, choice: .named(layout.name))
            item.state = (inForce?.name == layout.name) ? .on : .off
            submenu.addItem(item)
        }

        header.submenu = submenu
        return header
    }

    /// A monitor picker: an "everything off" entry, then every attached screen. Shared by the
    /// drag-snap and auto-arrange pickers so they stay labelled the same way.
    private func monitorSubmenu(noneTitle: String, selected: CGDirectDisplayID?,
                                action: Selector) -> NSMenu {
        let submenu = NSMenu()
        let none = NSMenuItem(title: noneTitle, action: action, keyEquivalent: "")
        none.target = self
        none.state = (selected == nil) ? .on : .off
        submenu.addItem(none)
        submenu.addItem(.separator())
        for (i, s) in NSScreen.screens.enumerated() {
            let item = NSMenuItem(title: s.label(index: i), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = s.displayID.map { NSNumber(value: $0) }
            item.state = (s.displayID == selected) ? .on : .off
            submenu.addItem(item)
        }
        // A manual re-scan, sitting where you look when the monitor you expected isn't listed.
        submenu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh monitors", action: #selector(refreshMonitors),
                                 keyEquivalent: "")
        refresh.target = self
        submenu.addItem(refresh)
        return submenu
    }

    // MARK: - Snap actions

    @objc private func snapToZone(_ sender: NSMenuItem) {
        guard let zone = sender.representedObject as? Zone else { return }
        WindowEngine.snapFocused(to: zone)
    }

    @objc private func openCustomSetup() {
        if customWindow == nil {
            let controller = CustomSetupWindowController()
            controller.onArm = { [weak self] layout, displayID in
                self?.armDragSnap(layout, displayID: displayID, persist: true)
            }
            customWindow = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        customWindow?.showWindow(nil)
        customWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func deleteLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        if activeLayout?.name == name { armDragSnap(nil, displayID: activeDisplayID, persist: true) }
        LayoutStore.shared.delete(named: name)
    }

    // MARK: - Arming drag-snap

    @objc private func armLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let layout = LayoutStore.shared.layout(named: name) else {
            armDragSnap(nil, displayID: activeDisplayID, persist: true)   // "Off"
            return
        }
        // Default to the main display the first time a layout is armed.
        let display = activeDisplayID ?? NSScreen.main?.displayID
        armDragSnap(layout, displayID: display, persist: true)
    }

    @objc private func chooseMonitor(_ sender: NSMenuItem) {
        let id = (sender.representedObject as? NSNumber)?.uint32Value
        activeDisplayID = id
        defaults.set(id.map { Int($0) }, forKey: "activeDisplayID")
        // Re-arm on the new monitor if a layout is active.
        if let layout = activeLayout {
            armDragSnap(layout, displayID: id, persist: true)
        } else {
            rebuildMenu()
        }
    }

    // MARK: - Auto-arrange

    @objc private func chooseAutoArrangeMonitor(_ sender: NSMenuItem) {
        setAutoArrange(displayID: (sender.representedObject as? NSNumber)?.uint32Value)
    }

    /// Pin how a given window count gets tiled, and re-tile straight away so the pick is visible
    /// without waiting for a window to open or close.
    @objc private func chooseAutoArrangeLayout(_ sender: NSMenuItem) {
        guard let pick = sender.representedObject as? AutoArrangePick else { return }
        autoArrangeChoices[pick.count] = pick.choice
        defaults.set(pick.choice.rawValue, forKey: Self.autoArrangeChoiceKey(pick.count))
        if autoArrange.isRunning { autoArrange.arrangeNow() }
        rebuildMenu()
    }

    private func loadAutoArrangeChoices() {
        for count in Self.choosableCounts {
            guard let raw = defaults.string(forKey: Self.autoArrangeChoiceKey(count)) else { continue }
            autoArrangeChoices[count] = AutoArrangeChoice(rawValue: raw)
        }
    }

    /// ⌃⌥⌘A: flip auto-arrange on for whichever screen the mouse is on, and off again if it
    /// was already watching that screen. The one-keystroke version of the menu picker.
    private func toggleAutoArrangeUnderMouse() {
        let id = Geometry.screenUnderMouse.displayID
        setAutoArrange(displayID: autoArrangeDisplayID == id ? nil : id)
    }

    /// Keep `displayID` tiled (or stop, when nil). This records the user's *choice*; whether it
    /// is running right now follows from that screen being attached.
    private func setAutoArrange(displayID: CGDirectDisplayID?) {
        autoArrangeDisplayID = displayID
        autoArrangeDisplayName = NSScreen.screen(withID: displayID)?.uniqueDisplayName
        defaults.set(displayID.map { Int($0) }, forKey: "autoArrangeDisplayID")
        defaults.set(autoArrangeDisplayName, forKey: "autoArrangeDisplayName")
        reconcileAutoArrange()
        rebuildMenu()
    }

    /// Start or stop auto-arrange so it is running exactly when the screen it was switched on for
    /// is attached. Returns whether that changed anything, so callers can tell a resume from a
    /// screen that was already being watched.
    @discardableResult
    private func reconcileAutoArrange() -> Bool {
        let attached = NSScreen.screens.compactMap(\.displayID)
        let target = DisplayTarget.active(desired: autoArrangeDisplayID, attached: attached)
        guard target != autoArrange.displayID else { return false }
        if let target {
            autoArrange.start(on: target)
        } else {
            autoArrange.stop()
        }
        return true
    }

    /// Re-scan the attached displays: repopulate the monitor pickers, resume auto-arrange on a
    /// screen that has come back, and drop it on one that has gone. Runs both from the menu item
    /// and from `didChangeScreenParametersNotification`.
    @objc private func refreshMonitors() {
        // Already watching the same screen, so nothing started or stopped — but this fires on
        // resolution and arrangement changes too, and the tiles are sized for the old geometry.
        // The window *set* is unchanged, so the watcher would never re-tile on its own.
        if !reconcileAutoArrange(), autoArrange.isRunning {
            autoArrange.arrangeNow()
        }
        rebuildMenu()
    }

    // MARK: - Arming drag-snap

    /// Turn drag-to-snap on for `layout` on `displayID` (or off when layout is nil).
    private func armDragSnap(_ layout: Layout?, displayID: CGDirectDisplayID?, persist: Bool) {
        activeLayout = layout
        activeDisplayID = displayID
        if persist {
            defaults.set(layout?.name, forKey: "activeLayoutName")
            defaults.set(displayID.map { Int($0) }, forKey: "activeDisplayID")
        }
        updateDynamicHotkeys()
        if layout != nil { dragSnap.start() } else { dragSnap.stop() }
        rebuildMenu()
    }

    // MARK: - Preferences

    /// Read the hold-to-snap pref, carrying over the superseded Control and per-modifier settings.
    private func loadHoldPreference() {
        if defaults.object(forKey: "requireShiftHeld") != nil {
            requireShiftHeld = defaults.bool(forKey: "requireShiftHeld")
        } else {
            requireShiftHeld = defaults.string(forKey: "holdModifier") != nil
                || defaults.bool(forKey: "requireControlHeld")
            defaults.set(requireShiftHeld, forKey: "requireShiftHeld")
        }
        defaults.removeObject(forKey: "holdModifier")
        defaults.removeObject(forKey: "requireControlHeld")
    }

    @objc private func toggleHoldShift() {
        requireShiftHeld.toggle()
        defaults.set(requireShiftHeld, forKey: "requireShiftHeld")
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch-at-login toggle failed: \(error)")
        }
        rebuildMenu()
    }

    @objc private func grantPermission() {
        Accessibility.requestIfNeeded()
        Accessibility.openSettingsPane()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Hotkeys

    private func setupStaticHotkeys() {
        func snap(_ layout: String, _ zone: String) -> () -> Void {
            {
                guard let l = LayoutStore.shared.layout(named: layout),
                      let z = l.zones.first(where: { $0.name == zone }) else { return }
                WindowEngine.snapFocused(to: z)
            }
        }
        hotkeys.bind(keyCode: HotkeyManager.arrowLeft,  action: snap("Halves", "Left"))
        hotkeys.bind(keyCode: HotkeyManager.arrowRight, action: snap("Halves", "Right"))
        hotkeys.bind(keyCode: HotkeyManager.arrowUp,    action: snap("Maximize", "Full"))
        hotkeys.bind(keyCode: HotkeyManager.letterA) { [weak self] in
            self?.toggleAutoArrangeUnderMouse()
        }
        hotkeys.start()
    }

    /// ⌃⌥⌘1…9 snap the focused window into the armed layout's zones (on its target monitor).
    private func updateDynamicHotkeys() {
        guard let layout = activeLayout else { hotkeys.setDynamic([]); return }
        let targetID = activeDisplayID
        var bindings: [HotkeyManager.Binding] = []
        for (i, zone) in layout.zones.prefix(HotkeyManager.digits.count).enumerated() {
            let z = zone
            bindings.append(HotkeyManager.Binding(keyCode: HotkeyManager.digits[i], action: {
                let screen = NSScreen.screen(withID: targetID) ?? Geometry.screenUnderMouse
                WindowEngine.snapFocused(to: z, on: screen)
            }))
        }
        hotkeys.setDynamic(bindings)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Refill the menu every time it is opened. A menu-bar agent has no Dock icon and is never
    /// really "activated", so the notifications that would otherwise prompt a rebuild are not
    /// dependable — the only list guaranteed not to be stale is one built as it is shown.
    ///
    /// Deliberately does not re-tile: opening a menu to look at it should never move windows.
    func menuNeedsUpdate(_ menu: NSMenu) {
        reconcileAutoArrange()
        populate(menu)
    }
}
