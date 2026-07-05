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
    private var requireControlHeld = false

    private lazy var dragSnap = DragSnapController(configProvider: { [weak self] in
        guard let self, let layout = self.activeLayout else { return nil }
        return DragSnapConfig(layout: layout,
                              targetDisplayID: self.activeDisplayID,
                              requireControlHeld: self.requireControlHeld)
    })

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        requireControlHeld = defaults.bool(forKey: "requireControlHeld")
        if defaults.object(forKey: "activeDisplayID") != nil {
            activeDisplayID = CGDirectDisplayID(defaults.integer(forKey: "activeDisplayID"))
        }

        setupStatusItem()

        if !Accessibility.isTrusted { Accessibility.requestIfNeeded() }
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu),
            name: LayoutStore.didChange, object: nil)

        setupStaticHotkeys()

        // Restore a previously armed drag-snap layout.
        if let name = defaults.string(forKey: "activeLayoutName"),
           let layout = LayoutStore.shared.layout(named: name) {
            armDragSnap(layout, displayID: activeDisplayID, persist: false)
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2",
                                   accessibilityDescription: "Sash")
        }
        rebuildMenu()
    }

    @objc private func rebuildMenu() {
        let menu = NSMenu()

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

        let holdItem = NSMenuItem(title: "Snap only while holding ⌃ (Control)",
                                  action: #selector(toggleHoldControl), keyEquivalent: "")
        holdItem.target = self
        holdItem.state = requireControlHeld ? .on : .off
        menu.addItem(holdItem)

        let hint = NSMenuItem(title: "Tip: press Esc mid-drag to cancel a snap", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
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

        statusItem.menu = menu
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
        let title = "Snap on monitor:  \(current.flatMap { s in NSScreen.screens.firstIndex(of: s).map { "Display \($0 + 1)" } } ?? "Any")"
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let any = NSMenuItem(title: "Any monitor", action: #selector(chooseMonitor(_:)), keyEquivalent: "")
        any.target = self
        any.state = (activeDisplayID == nil) ? .on : .off
        submenu.addItem(any)
        submenu.addItem(.separator())
        for (i, s) in NSScreen.screens.enumerated() {
            let item = NSMenuItem(title: s.label(index: i), action: #selector(chooseMonitor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.displayID.map { NSNumber(value: $0) }
            item.state = (s.displayID == activeDisplayID) ? .on : .off
            submenu.addItem(item)
        }
        header.submenu = submenu
        return header
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

    @objc private func toggleHoldControl() {
        requireControlHeld.toggle()
        defaults.set(requireControlHeld, forKey: "requireControlHeld")
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
