import AppKit

/// Global keyboard shortcuts. Phase 1 uses an `NSEvent` global monitor, which is the
/// simplest path and only needs the Accessibility permission we already require.
///
/// Trade-off: a global monitor observes but does not *consume* the keystroke, so we pick
/// an uncommon modifier stack (⌃⌥⌘) that apps rarely bind. Phase 2 can upgrade to a
/// Carbon `RegisterEventHotKey` / `CGEventTap` if we need to swallow the event.
final class HotkeyManager {

    struct Binding {
        let keyCode: UInt16
        let action: () -> Void
    }

    private var monitor: Any?
    private var bindings: [Binding] = []
    /// Bindings that change when the armed layout changes (e.g. ⌃⌥⌘1–9 → its zones).
    private var dynamicBindings: [Binding] = []

    /// The modifier stack every Sash shortcut shares.
    static let modifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    // Common key codes.
    static let arrowLeft: UInt16 = 123
    static let arrowRight: UInt16 = 124
    static let arrowDown: UInt16 = 125
    static let arrowUp: UInt16 = 126
    static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1...9
    static let letterA: UInt16 = 0

    func bind(keyCode: UInt16, action: @escaping () -> Void) {
        bindings.append(Binding(keyCode: keyCode, action: action))
    }

    /// Replace the layout-dependent bindings (called whenever the armed layout changes).
    func setDynamic(_ newBindings: [Binding]) {
        dynamicBindings = newBindings
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        // Compare only the modifier keys we care about.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == Self.modifiers else { return }
        for binding in bindings + dynamicBindings where binding.keyCode == event.keyCode {
            binding.action()
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
