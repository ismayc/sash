import AppKit
import ServiceManagement
import SashKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let hotkeys = HotkeyManager()
    private var customWindow: CustomSetupWindowController?
    /// Held while the reserved-space editor is up, so it isn't deallocated mid-drag.
    private var reservedSpaceEditor: ReservedSpaceController?

    // Drag-to-snap state (persisted in UserDefaults).
    private var activeLayout: Layout?
    private var activeDisplayID: CGDirectDisplayID?
    private var requireShiftHeld = false

    // Auto-arrange state (persisted in UserDefaults).
    /// What the user *asked* to keep tiled: nothing, one display, or all of them. Deliberately
    /// not cleared when a chosen screen goes away — a monitor asleep or unplugged pauses
    /// auto-arrange, and it resumes by itself once the screen is back. What is actually running
    /// is `autoArrange.displayIDs`.
    private var autoArrangeScope: AutoArrangeScope = .off
    /// The chosen screens' names, kept so the menu can still say which displays it is waiting
    /// for after they have stopped reporting one.
    private var autoArrangeDisplayNames: [CGDirectDisplayID: String] = [:]
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
        loadAutoArrangeScope()
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

        // Restore auto-arrange. A chosen screen that isn't attached right now is waited for
        // rather than dropped; "all monitors" simply resolves to whatever is plugged in.
        reconcileAutoArrange()
        rebuildMenu()
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

        // --- Reserved space (applies to snapping and auto-arrange alike) ---
        menu.addItem(reservedSpaceMenuItem())
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

    /// The auto-arrange picker: off, every monitor at once, or whichever ones you tick.
    ///
    /// The monitors are ticks rather than a one-of-these choice, so two screens out of three is
    /// as easy to say as one. "All monitors" stays a separate entry because it means something
    /// the ticks can't: *and whatever you plug in next*. Each click closes the menu, as menu
    /// clicks do — reopen it to tick the next monitor.
    private func autoArrangeMenuItem() -> NSMenuItem {
        let header = NSMenuItem(title: "Auto-arrange windows on:  \(autoArrangeStatus)",
                                action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(scopeItem(title: "Off", scope: .off))
        submenu.addItem(scopeItem(title: "All monitors", scope: .allDisplays))
        submenu.addItem(.separator())

        let hint = NSMenuItem(title: "…or tick the monitors you want:", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        submenu.addItem(hint)
        for (i, screen) in NSScreen.screens.enumerated() {
            guard let id = screen.displayID else { continue }
            let item = NSMenuItem(title: screen.label(index: i),
                                  action: #selector(toggleAutoArrangeMonitor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: id)
            item.state = autoArrangeScope.includes(id) ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(refreshMonitorsItem())
        header.submenu = submenu
        return header
    }

    private func scopeItem(title: String, scope: AutoArrangeScope) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(chooseAutoArrangeScope(_:)),
                              keyEquivalent: "")
        item.target = self
        item.representedObject = scope
        item.state = (autoArrangeScope == scope) ? .on : .off
        return item
    }

    /// What the auto-arrange header reads. Chosen-but-absent screens say so by name instead of
    /// reading "Off", because the preference is paused, not cancelled — "Off" would be a lie that
    /// invites you to switch it on again.
    private var autoArrangeStatus: String {
        switch autoArrangeScope {
        case .off:
            return "Off"
        case .allDisplays:
            return "All monitors (\(NSScreen.screens.count) connected)"
        case .displays(let ids):
            let present = NSScreen.screens.filter { $0.displayID.map(ids.contains) ?? false }
            let waiting = ids.count - present.count
            guard !present.isEmpty else {
                let names = ids.compactMap { autoArrangeDisplayNames[$0] }.sorted()
                let known = names.isEmpty ? "Chosen displays" : names.joined(separator: " + ")
                return "\(known) — waiting, not connected"
            }
            // Two names still read as names; beyond that a count is kinder than a run-on title.
            let names = present.map(\.uniqueDisplayName)
            let base = names.count <= 2 ? names.joined(separator: " + ") : "\(names.count) monitors"
            return waiting == 0 ? base : "\(base) (+\(waiting) waiting)"
        }
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

    /// A picker for the space Sash must leave alone on each attached screen. Picking a monitor
    /// opens the editor *on that monitor*, because the thing being protected is on the desktop:
    /// the only way to know you've cleared it is to see it.
    private func reservedSpaceMenuItem() -> NSMenuItem {
        let store = ScreenMarginsStore.shared
        let header = NSMenuItem(title: "Keep space clear:  \(reservedSpaceStatus)",
                                action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (i, s) in NSScreen.screens.enumerated() {
            let margins = store.margins(for: s.uniqueDisplayName)
            let suffix = margins.isEmpty ? "" : "  —  \(margins.summary)"
            let item = NSMenuItem(title: s.label(index: i) + suffix,
                                  action: #selector(editReservedSpace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.displayID.map { NSNumber(value: $0) }
            item.state = margins.isEmpty ? .off : .on
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let clear = NSMenuItem(title: "Use the whole of every screen",
                               action: #selector(clearReservedSpace), keyEquivalent: "")
        clear.target = self
        submenu.addItem(clear)
        header.submenu = submenu
        return header
    }

    /// What the reserved-space header reads: the display kept clear, or how many of them. A
    /// display that isn't attached still counts — the setting is remembered by name, so the
    /// strip is still protected when that monitor comes back.
    private var reservedSpaceStatus: String {
        let store = ScreenMarginsStore.shared
        let reserved = NSScreen.screens
            .filter { !store.margins(for: $0.uniqueDisplayName).isEmpty }
        switch reserved.count {
        case 0: return store.isEmpty ? "Nothing" : "Only on a monitor that isn't connected"
        case 1: return "\(reserved[0].uniqueDisplayName) — "
            + store.margins(for: reserved[0].uniqueDisplayName).summary
        default: return "\(reserved.count) monitors"
        }
    }

    /// A monitor picker: an "everything off" entry, then every attached screen. Used by the
    /// drag-snap picker; auto-arrange builds its own because its choices are scopes rather than
    /// display ids, but both share the screen labels and the re-scan below.
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
        submenu.addItem(.separator())
        submenu.addItem(refreshMonitorsItem())
        return submenu
    }

    /// A manual re-scan, sitting where you look when the monitor you expected isn't listed.
    private func refreshMonitorsItem() -> NSMenuItem {
        let refresh = NSMenuItem(title: "Refresh monitors", action: #selector(refreshMonitors),
                                 keyEquivalent: "")
        refresh.target = self
        return refresh
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

    // MARK: - Reserved space

    /// Open the drag-an-edge editor on the chosen screen.
    @objc private func editReservedSpace(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value,
              let screen = NSScreen.screen(withID: id) else { return }
        let controller = ReservedSpaceController(screen: screen) { [weak self] in
            self?.reservedSpaceEditor = nil
            self?.reservedSpaceChanged()
        }
        reservedSpaceEditor = controller
        controller.begin()
    }

    @objc private func clearReservedSpace() {
        ScreenMarginsStore.shared.clearAll()
        reservedSpaceChanged()
    }

    /// Re-tile straight away so a newly-protected strip is cleared now rather than at the next
    /// window change — the same reasoning as picking an auto-arrange layout.
    private func reservedSpaceChanged() {
        if autoArrange.isRunning { autoArrange.arrangeNow() }
        rebuildMenu()
    }

    // MARK: - Auto-arrange

    @objc private func chooseAutoArrangeScope(_ sender: NSMenuItem) {
        guard let scope = sender.representedObject as? AutoArrangeScope else { return }
        setAutoArrange(scope)
    }

    /// Tick or untick one monitor, leaving the others as they are.
    @objc private func toggleAutoArrangeMonitor(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        setAutoArrange(autoArrangeScope.toggling(id, attached: NSScreen.screens.compactMap(\.displayID)))
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

    /// ⌃⌥⌘A: tick the screen the mouse is on in or out of auto-arrange — the one-keystroke
    /// version of ticking it in the menu. Pressed on each of two monitors in turn, it builds
    /// the same pair the menu would; pressed on the last one still on, it switches off.
    private func toggleAutoArrangeUnderMouse() {
        guard let id = Geometry.screenUnderMouse.displayID else { return }
        setAutoArrange(autoArrangeScope.toggling(id, attached: NSScreen.screens.compactMap(\.displayID)))
    }

    /// Record what the user asked to keep tiled. Whether it is running right now follows from
    /// which of those displays are actually attached.
    private func setAutoArrange(_ scope: AutoArrangeScope) {
        autoArrangeScope = scope
        rememberDisplayNames(for: scope)
        defaults.set(scope.rawValue, forKey: "autoArrangeScope")
        reconcileAutoArrange()
        rebuildMenu()
    }

    /// Note the names of the chosen displays while they are attached to report them, so the menu
    /// can still say *which* monitor it is waiting for once that monitor has stopped answering.
    private func rememberDisplayNames(for scope: AutoArrangeScope) {
        guard case .displays(let ids) = scope else { return }
        for screen in NSScreen.screens {
            guard let id = screen.displayID, ids.contains(id) else { continue }
            autoArrangeDisplayNames[id] = screen.uniqueDisplayName
        }
        autoArrangeDisplayNames = autoArrangeDisplayNames.filter { ids.contains($0.key) }
        defaults.set(Dictionary(uniqueKeysWithValues: autoArrangeDisplayNames.map { (String($0.key), $0.value) }),
                     forKey: "autoArrangeDisplayNames")
    }

    /// Read the auto-arrange preference, carrying over the superseded single-display settings so
    /// an existing install keeps tiling the screen it was already tiling.
    private func loadAutoArrangeScope() {
        if let raw = defaults.string(forKey: "autoArrangeScope") {
            autoArrangeScope = AutoArrangeScope(rawValue: raw)
        } else if defaults.object(forKey: "autoArrangeDisplayID") != nil {
            autoArrangeScope = .displays([CGDirectDisplayID(defaults.integer(forKey: "autoArrangeDisplayID"))])
            defaults.set(autoArrangeScope.rawValue, forKey: "autoArrangeScope")
        }
        if let stored = defaults.dictionary(forKey: "autoArrangeDisplayNames") as? [String: String] {
            for (key, name) in stored {
                if let id = CGDirectDisplayID(key) { autoArrangeDisplayNames[id] = name }
            }
        } else if let legacy = defaults.string(forKey: "autoArrangeDisplayName"),
                  case .displays(let ids) = autoArrangeScope, let id = ids.first {
            autoArrangeDisplayNames[id] = legacy
        }
        defaults.removeObject(forKey: "autoArrangeDisplayID")
        defaults.removeObject(forKey: "autoArrangeDisplayName")
    }

    /// Start or stop auto-arrange so it is running on exactly the displays the current scope
    /// resolves to. Returns whether that changed anything, so callers can tell a resume from a
    /// set of screens that were already being watched.
    @discardableResult
    private func reconcileAutoArrange() -> Bool {
        let attached = NSScreen.screens.compactMap(\.displayID)
        let target = Set(autoArrangeScope.active(attached: attached))
        guard target != autoArrange.displayIDs else { return false }
        if target.isEmpty {
            autoArrange.stop()
        } else {
            autoArrange.start(on: target)
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
