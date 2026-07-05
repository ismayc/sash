import Foundation
import SashKit

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sash-tests-\(UUID().uuidString)")
        .appendingPathComponent("layouts.json")
}

func runLayoutStoreTests() {
    T.test("Store starts empty but exposes built-ins via .all") {
        let store = LayoutStore(fileURL: tempURL())
        T.expect(store.custom.isEmpty)
        T.expect(store.all.count == Layout.builtins.count)
    }

    T.test("save() adds, and replaces when the name matches") {
        let store = LayoutStore(fileURL: tempURL())
        store.save(Layout(name: "Work", zones: Layout.grid(cols: 2, rows: 1)))
        T.expect(store.custom.count == 1)
        store.save(Layout(name: "Work", zones: Layout.grid(cols: 3, rows: 1)))
        T.expect(store.custom.count == 1)
        T.expect(store.layout(named: "Work")?.zones.count == 3)
    }

    T.test("layout(named:) finds built-ins and custom, nil otherwise") {
        let store = LayoutStore(fileURL: tempURL())
        T.expect(store.layout(named: "Halves") != nil)
        T.expect(store.layout(named: "Nonexistent") == nil)
        store.save(Layout(name: "Mine", zones: []))
        T.expect(store.layout(named: "Mine") != nil)
    }

    T.test("delete() removes a custom layout") {
        let store = LayoutStore(fileURL: tempURL())
        store.save(Layout(name: "Temp", zones: []))
        store.delete(named: "Temp")
        T.expect(store.custom.isEmpty)
    }

    T.test("Layouts persist across store instances") {
        let url = tempURL()
        let a = LayoutStore(fileURL: url)
        a.save(Layout(name: "Persisted", zones: Layout.grid(cols: 2, rows: 2)))
        let b = LayoutStore(fileURL: url)
        T.expect(b.layout(named: "Persisted")?.zones.count == 4)
    }

    T.test("Default-path store (and shared singleton) construct and expose built-ins") {
        // Exercises defaultFileURL() and the shared singleton. Read-only: never writes.
        T.expect(LayoutStore.shared.all.count >= Layout.builtins.count)
        let def = LayoutStore()
        T.expect(def.all.count >= Layout.builtins.count)
    }

    T.test("A corrupt layouts file is ignored, not fatal") {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: url)
        let store = LayoutStore(fileURL: url)
        T.expect(store.custom.isEmpty)
    }
}
