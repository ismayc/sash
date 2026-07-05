import AppKit
import SashKit

/// The "Custom Setup" window. Workflow:
///   1. Pick the target monitor (drag the windows you want onto it first).
///   2. Design zones on the canvas — generate a grid, or add/move/resize freely.
///   3. For each zone, pick which open window goes there.
///   4. Apply (snaps everything into place) and optionally Save the layout for reuse.
final class CustomSetupWindowController: NSWindowController {

    /// Called when the user arms these zones for drag-to-snap on the chosen monitor.
    var onArm: ((Layout, CGDirectDisplayID?) -> Void)?

    private let canvas = ZoneCanvasView()
    private var screens: [NSScreen] = []
    private var currentScreen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var windowsOnScreen: [ManagedWindow] = []
    /// zone.id -> assigned window id
    private var assignments: [UUID: CGWindowID] = [:]

    // Controls we mutate.
    private let monitorPopup = NSPopUpButton()
    private let colStepper = NSStepper()
    private let rowStepper = NSStepper()
    private let colLabel = NSTextField(labelWithString: "3")
    private let rowLabel = NSTextField(labelWithString: "2")
    private let nameField = NSTextField(string: "")
    private let xStepper = NSStepper(), yStepper = NSStepper(), wStepper = NSStepper(), hStepper = NSStepper()
    private let xLabel = NSTextField(labelWithString: "0")
    private let yLabel = NSTextField(labelWithString: "0")
    private let wLabel = NSTextField(labelWithString: "0")
    private let hLabel = NSTextField(labelWithString: "0")
    private let windowPopup = NSPopUpButton()
    private let deleteButton = NSButton()
    private let layoutNameField = NSTextField(string: "My Layout")
    private var canvasAspect: NSLayoutConstraint?

    private let grid = 12

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Custom Setup"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
        reloadScreens()
        refreshWindows()
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let toolbar = buildToolbar()
        let panel = buildRightPanel()

        let canvasContainer = NSView()
        canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.wantsLayer = true
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(canvas)
        canvas.onZonesChange = { [weak self] in self?.zonesChanged() }
        canvas.onSelectionChange = { [weak self] idx in self?.selectionChanged(idx) }
        canvas.gridDivisions = grid

        for v in [toolbar, canvasContainer, panel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            canvasContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            canvasContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            canvasContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            panel.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            panel.leadingAnchor.constraint(equalTo: canvasContainer.trailingAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            panel.widthAnchor.constraint(equalToConstant: 250),

            // Canvas centered in its container, fitting within it, keeping monitor aspect.
            canvas.centerXAnchor.constraint(equalTo: canvasContainer.centerXAnchor),
            canvas.centerYAnchor.constraint(equalTo: canvasContainer.centerYAnchor),
            canvas.widthAnchor.constraint(lessThanOrEqualTo: canvasContainer.widthAnchor),
            canvas.heightAnchor.constraint(lessThanOrEqualTo: canvasContainer.heightAnchor),
            canvas.widthAnchor.constraint(equalTo: canvasContainer.widthAnchor).withPriority(.defaultHigh),
            canvas.heightAnchor.constraint(equalTo: canvasContainer.heightAnchor).withPriority(.defaultHigh),
        ])
        applyCanvasAspect()
    }

    private func buildToolbar() -> NSView {
        colStepper.minValue = 1; colStepper.maxValue = 6; colStepper.integerValue = 3
        rowStepper.minValue = 1; rowStepper.maxValue = 6; rowStepper.integerValue = 2
        colStepper.target = self; colStepper.action = #selector(gridStepperChanged)
        rowStepper.target = self; rowStepper.action = #selector(gridStepperChanged)

        monitorPopup.target = self; monitorPopup.action = #selector(monitorChanged)

        let generate = NSButton(title: "Generate Grid", target: self, action: #selector(generateGrid))
        let refresh = NSButton(title: "Refresh Windows", target: self, action: #selector(refreshWindows))

        let stack = NSStackView(views: [
            NSTextField(labelWithString: "Monitor:"), monitorPopup,
            spacer(20),
            NSTextField(labelWithString: "Grid:"), colStepper, colLabel,
            NSTextField(labelWithString: "×"), rowStepper, rowLabel,
            generate,
            spacer(12),
            refresh,
        ])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        return stack
    }

    private func buildRightPanel() -> NSView {
        let header = NSTextField(labelWithString: "Selected Zone")
        header.font = .boldSystemFont(ofSize: 13)

        nameField.placeholderString = "Zone name"
        nameField.target = self; nameField.action = #selector(nameChanged)

        for s in [xStepper, yStepper, wStepper, hStepper] {
            s.minValue = 0; s.maxValue = Double(grid); s.target = self; s.action = #selector(rectStepperChanged)
        }

        let propGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Name:"), nameField],
            [NSTextField(labelWithString: "X:"), row(xStepper, xLabel)],
            [NSTextField(labelWithString: "Y:"), row(yStepper, yLabel)],
            [NSTextField(labelWithString: "Width:"), row(wStepper, wLabel)],
            [NSTextField(labelWithString: "Height:"), row(hStepper, hLabel)],
            [NSTextField(labelWithString: "Window:"), windowPopup],
        ])
        propGrid.rowSpacing = 8
        propGrid.columnSpacing = 8
        windowPopup.target = self; windowPopup.action = #selector(windowAssigned)

        deleteButton.title = "Delete Zone"
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self; deleteButton.action = #selector(deleteZone)

        let hint = NSTextField(wrappingLabelWithString:
            "Double-click canvas to add a zone. Drag to move; drag the corner to resize. Delete key removes the selected zone.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor

        // Primary action: arm these zones so you can drag windows into them.
        let dragHint = NSTextField(wrappingLabelWithString:
            "Then just drag any window — the zones light up and it snaps into place.")
        dragHint.font = .systemFont(ofSize: 10)
        dragHint.textColor = .secondaryLabelColor

        layoutNameField.placeholderString = "Layout name"
        let nameRow = NSStackView(views: [NSTextField(labelWithString: "Name:"), layoutNameField])
        nameRow.orientation = .horizontal
        nameRow.spacing = 6

        let useForDrag = NSButton(title: "Use for Drag-Snap", target: self, action: #selector(useForDragSnap))
        useForDrag.bezelStyle = .rounded
        useForDrag.keyEquivalent = "\r"
        useForDrag.controlSize = .large

        let apply = NSButton(title: "Apply assignments below ↓", target: self, action: #selector(applyLayout))
        apply.bezelStyle = .rounded
        let save = NSButton(title: "Save Only", target: self, action: #selector(saveLayout))
        save.bezelStyle = .rounded
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded

        let stack = NSStackView(views: [
            header, propGrid, deleteButton, hint,
            NSView(), // flexible spacer
            nameRow, useForDrag, dragHint,
            apply, save, close,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    // MARK: - Screens & windows

    private func reloadScreens() {
        screens = NSScreen.screens
        monitorPopup.removeAllItems()
        for (i, s) in screens.enumerated() {
            let px = Int(s.frame.width * (s.backingScaleFactor))
            let py = Int(s.frame.height * (s.backingScaleFactor))
            monitorPopup.addItem(withTitle: "Display \(i + 1) — \(px)×\(py)")
        }
        if let idx = screens.firstIndex(of: currentScreen) {
            monitorPopup.selectItem(at: idx)
        } else {
            currentScreen = screens.first ?? currentScreen
            monitorPopup.selectItem(at: 0)
        }
        applyCanvasAspect()
    }

    @objc private func refreshWindows() {
        windowsOnScreen = WindowInfo.windows(on: currentScreen)
        rebuildWindowPopup()
        refreshAssignmentLabels()
    }

    private func rebuildWindowPopup() {
        windowPopup.removeAllItems()
        windowPopup.addItem(withTitle: "— none —")
        for w in windowsOnScreen { windowPopup.addItem(withTitle: w.label) }
        syncWindowPopupToSelection()
    }

    // MARK: - Canvas sync

    private func applyCanvasAspect() {
        canvasAspect?.isActive = false
        let aspect = currentScreen.frame.width / max(currentScreen.frame.height, 1)
        let c = canvas.widthAnchor.constraint(equalTo: canvas.heightAnchor, multiplier: aspect)
        c.priority = .required
        c.isActive = true
        canvasAspect = c
    }

    private func zonesChanged() {
        refreshAssignmentLabels()
        syncSteppersToSelection()
    }

    private func selectionChanged(_ idx: Int?) {
        let hasSel = idx != nil
        [nameField, xStepper, yStepper, wStepper, hStepper, windowPopup, deleteButton].forEach { $0.isEnabled = hasSel }
        syncSteppersToSelection()
        syncWindowPopupToSelection()
    }

    private func syncSteppersToSelection() {
        guard let i = canvas.selectedIndex, i < canvas.zones.count else { return }
        let z = canvas.zones[i]
        nameField.stringValue = z.name
        xStepper.integerValue = Int((z.x * CGFloat(grid)).rounded())
        yStepper.integerValue = Int((z.y * CGFloat(grid)).rounded())
        wStepper.integerValue = Int((z.w * CGFloat(grid)).rounded())
        hStepper.integerValue = Int((z.h * CGFloat(grid)).rounded())
        xLabel.integerValue = xStepper.integerValue
        yLabel.integerValue = yStepper.integerValue
        wLabel.integerValue = wStepper.integerValue
        hLabel.integerValue = hStepper.integerValue
    }

    private func syncWindowPopupToSelection() {
        guard let i = canvas.selectedIndex, i < canvas.zones.count else { windowPopup.selectItem(at: 0); return }
        let zid = canvas.zones[i].id
        if let wid = assignments[zid], let w = windowsOnScreen.firstIndex(where: { $0.id == wid }) {
            windowPopup.selectItem(at: w + 1)
        } else {
            windowPopup.selectItem(at: 0)
        }
    }

    private func refreshAssignmentLabels() {
        var labels: [Int: String] = [:]
        for (i, z) in canvas.zones.enumerated() {
            if let wid = assignments[z.id], let w = windowsOnScreen.first(where: { $0.id == wid }) {
                labels[i] = w.label
            }
        }
        canvas.assignmentLabels = labels
    }

    // MARK: - Actions

    @objc private func monitorChanged() {
        currentScreen = screens[max(0, monitorPopup.indexOfSelectedItem)]
        applyCanvasAspect()
        refreshWindows()
    }

    @objc private func gridStepperChanged() {
        colLabel.integerValue = colStepper.integerValue
        rowLabel.integerValue = rowStepper.integerValue
    }

    @objc private func generateGrid() {
        let cols = colStepper.integerValue, rows = rowStepper.integerValue
        var zones: [Zone] = []
        for r in 0..<rows {
            for c in 0..<cols {
                zones.append(Zone(name: "R\(r + 1)C\(c + 1)",
                                  x: CGFloat(c) / CGFloat(cols), y: CGFloat(r) / CGFloat(rows),
                                  w: 1 / CGFloat(cols), h: 1 / CGFloat(rows)))
            }
        }
        assignments.removeAll()
        canvas.zones = zones
        canvas.selectedIndex = nil
        refreshAssignmentLabels()
    }

    @objc private func nameChanged() {
        guard let i = canvas.selectedIndex, i < canvas.zones.count else { return }
        canvas.zones[i].name = nameField.stringValue
    }

    @objc private func rectStepperChanged() {
        guard let i = canvas.selectedIndex, i < canvas.zones.count else { return }
        var z = canvas.zones[i]
        let g = CGFloat(grid)
        var x = CGFloat(xStepper.integerValue) / g
        var y = CGFloat(yStepper.integerValue) / g
        var w = max(CGFloat(wStepper.integerValue) / g, 1 / g)
        var h = max(CGFloat(hStepper.integerValue) / g, 1 / g)
        w = min(w, 1); h = min(h, 1)
        x = min(x, 1 - w); y = min(y, 1 - h)
        z.x = x; z.y = y; z.w = w; z.h = h
        canvas.zones[i] = z
        syncSteppersToSelection()
        refreshAssignmentLabels()
    }

    @objc private func windowAssigned() {
        guard let i = canvas.selectedIndex, i < canvas.zones.count else { return }
        let zid = canvas.zones[i].id
        let sel = windowPopup.indexOfSelectedItem
        if sel <= 0 {
            assignments[zid] = nil
        } else {
            let w = windowsOnScreen[sel - 1]
            // A window can only live in one zone; clear any previous assignment of it.
            for (k, v) in assignments where v == w.id { assignments[k] = nil }
            assignments[zid] = w.id
        }
        refreshAssignmentLabels()
    }

    @objc private func deleteZone() {
        guard let i = canvas.selectedIndex, i < canvas.zones.count else { return }
        canvas.zones.remove(at: i)
        canvas.selectedIndex = nil
        refreshAssignmentLabels()
    }

    @objc private func applyLayout() {
        for z in canvas.zones {
            guard let wid = assignments[z.id], let w = windowsOnScreen.first(where: { $0.id == wid }) else { continue }
            WindowEngine.snap(w, to: z, on: currentScreen)
        }
    }

    /// Build a saved, named layout from the current zones.
    private func currentLayout() -> Layout? {
        guard !canvas.zones.isEmpty else { return nil }
        let name = layoutNameField.stringValue.trimmingCharacters(in: .whitespaces)
        return Layout(name: name.isEmpty ? "My Layout" : name, zones: canvas.zones)
    }

    @objc private func saveLayout() {
        guard let layout = currentLayout() else { return }
        LayoutStore.shared.save(layout)
    }

    /// Save these zones and arm them for drag-to-snap on the selected monitor, then close.
    @objc private func useForDragSnap() {
        guard let layout = currentLayout() else { return }
        LayoutStore.shared.save(layout)
        onArm?(layout, currentScreen.displayID)
        window?.close()
    }

    @objc private func closeWindow() {
        window?.close()
    }

    // MARK: - Small builders

    private func spacer(_ width: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }

    private func row(_ stepper: NSStepper, _ label: NSTextField) -> NSView {
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let s = NSStackView(views: [stepper, label])
        s.orientation = .horizontal
        s.spacing = 6
        return s
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ p: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        priority = p
        return self
    }
}
