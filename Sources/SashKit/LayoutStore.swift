import Foundation

/// Persists user-defined layouts to disk and exposes them alongside the built-ins.
/// The file URL is injectable so tests can point at a temp directory.
public final class LayoutStore {
    public static let shared = LayoutStore()

    public static let didChange = Notification.Name("Sash.LayoutStoreDidChange")

    public private(set) var custom: [Layout] = []

    private let fileURL: URL

    /// Default location: ~/Library/Application Support/Sash/layouts.json
    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sash", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("layouts.json")
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    /// Built-ins first, then the user's saved layouts.
    public var all: [Layout] { Layout.builtins + custom }

    public func layout(named name: String) -> Layout? {
        all.first { $0.name == name }
    }

    /// Add or replace a custom layout by name.
    public func save(_ layout: Layout) {
        if let idx = custom.firstIndex(where: { $0.name == layout.name }) {
            custom[idx] = layout
        } else {
            custom.append(layout)
        }
        persist()
    }

    public func delete(named name: String) {
        custom.removeAll { $0.name == name }
        persist()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Layout].self, from: data) else { return }
        custom = decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(custom) {
            // Ensure the containing directory exists before writing.
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
