import AppKit
import SashKit

/// Remembers how much of each screen Sash must leave alone.
///
/// Keyed by display *name* rather than id, so the strip you protected on a monitor is still
/// protected after that monitor sleeps, is unplugged, or comes back through a KVM under a
/// freshly-issued display id — see `ScreenMargins.decodeBook`.
final class ScreenMarginsStore {
    static let shared = ScreenMarginsStore()

    static let didChange = Notification.Name("Sash.ScreenMarginsDidChange")

    private static let key = "screenMargins"

    private let defaults: UserDefaults
    private var book: [String: ScreenMargins]

    /// The defaults object is injectable so a future test can point at a scratch suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        book = ScreenMargins.decodeBook(defaults.data(forKey: Self.key))
    }

    /// What is kept clear on the named display — nothing, for a display never configured.
    func margins(for displayName: String) -> ScreenMargins {
        book[displayName] ?? .none
    }

    func set(_ margins: ScreenMargins, for displayName: String) {
        book[displayName] = margins
        persist()
    }

    /// Give every screen back in full.
    func clearAll() {
        book = [:]
        persist()
    }

    /// Whether any display has space reserved on it, including ones not attached right now.
    var isEmpty: Bool { book.isEmpty }

    private func persist() {
        book = book.filter { !$0.value.isEmpty }
        // Nothing to write means something went wrong encoding, not "reserve nothing" — leave
        // the stored setting as it was rather than wiping a screen's margins on the way out.
        if let data = ScreenMargins.encodeBook(book) {
            defaults.set(data, forKey: Self.key)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
