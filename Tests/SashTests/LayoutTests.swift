import Foundation
import CoreGraphics
import SashKit

func runLayoutTests() {
    T.test("Layout.grid produces cols×rows zones") {
        T.expect(Layout.grid(cols: 3, rows: 2).count == 6)
        T.expect(Layout.grid(cols: 3, rows: 3).count == 9)
    }

    T.test("Layout.grid tiles the screen with no gaps") {
        let zones = Layout.grid(cols: 2, rows: 2)
        for z in zones {
            T.expect(T.approx(z.w, 0.5))
            T.expect(T.approx(z.h, 0.5))
        }
        let area = zones.reduce(0) { $0 + $1.w * $1.h }
        T.expect(T.approx(area, 1.0))
    }

    T.test("Layout.grid clamps non-positive inputs (no NaN, no divide-by-zero)") {
        let zones = Layout.grid(cols: 0, rows: 0)
        T.expect(zones.count == 1)
        T.expect(!zones[0].w.isNaN)
        T.expect(T.approx(zones[0].w, 1))
    }

    T.test("Layout.grid names zones RxCy") {
        T.expect(Layout.grid(cols: 2, rows: 1).map(\.name) == ["R1C1", "R1C2"])
    }

    T.test("Built-in layouts are present and correctly shaped") {
        let names = Layout.builtins.map(\.name)
        T.expect(names.contains("Halves"))
        T.expect(names.contains("Thirds"))
        T.expect(names.contains("Quarters"))
        T.expect(names.contains("3×3 Grid"))
        T.expect(names.contains("Maximize"))
        T.expect(Layout.builtins.first { $0.name == "3×3 Grid" }?.zones.count == 9)
        T.expect(Layout.builtins.first { $0.name == "Quarters" }?.zones.count == 4)
        T.expect(Layout.builtins.first { $0.name == "Thirds" }?.zones.count == 3)
        T.expect(Layout.builtins.first { $0.name == "Maximize" }?.zones.first?.w == 1)
    }

    T.test("Layout Codable round-trips") {
        let layout = Layout(name: "Mine", zones: Layout.grid(cols: 2, rows: 2))
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)
        T.expect(decoded == layout)
    }
}
