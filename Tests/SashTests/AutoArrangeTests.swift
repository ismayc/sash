import Foundation
import CoreGraphics
import SashKit

func runAutoArrangeTests() {

    // Aspect ratios of the two screens this is tuned against.
    let ultrawide: CGFloat = 3440.0 / 1415   // LG ultrawide, menu bar removed
    let laptop: CGFloat = 1512.0 / 944       // built-in Retina display

    T.test("A wide screen splits into columns") {
        T.expect(AutoArrange.shape(count: 2, aspectRatio: ultrawide) == (cols: 2, rows: 1))
        T.expect(AutoArrange.shape(count: 3, aspectRatio: ultrawide) == (cols: 3, rows: 1))
        T.expect(AutoArrange.shape(count: 4, aspectRatio: ultrawide) == (cols: 4, rows: 1))
    }

    T.test("A wide screen adds a second row once columns get too thin") {
        T.expect(AutoArrange.shape(count: 5, aspectRatio: ultrawide) == (cols: 3, rows: 2))
        T.expect(AutoArrange.shape(count: 6, aspectRatio: ultrawide) == (cols: 3, rows: 2))
    }

    T.test("A laptop screen prefers grids over thin columns") {
        T.expect(AutoArrange.shape(count: 2, aspectRatio: laptop) == (cols: 2, rows: 1))
        T.expect(AutoArrange.shape(count: 3, aspectRatio: laptop) == (cols: 2, rows: 2))
        T.expect(AutoArrange.shape(count: 4, aspectRatio: laptop) == (cols: 2, rows: 2))
        T.expect(AutoArrange.shape(count: 6, aspectRatio: laptop) == (cols: 3, rows: 2))
    }

    T.test("A tall screen stacks rows") {
        T.expect(AutoArrange.shape(count: 2, aspectRatio: 0.5) == (cols: 1, rows: 2))
        T.expect(AutoArrange.shape(count: 3, aspectRatio: 0.5) == (cols: 1, rows: 3))
    }

    T.test("shape survives degenerate input") {
        T.expect(AutoArrange.shape(count: 0, aspectRatio: laptop) == (cols: 1, rows: 1))
        T.expect(AutoArrange.shape(count: -3, aspectRatio: laptop) == (cols: 1, rows: 1))
        // A zero/negative aspect ratio must not produce log(0) = -inf and pick garbage.
        let degenerate = AutoArrange.shape(count: 4, aspectRatio: 0)
        T.expect(degenerate.cols * degenerate.rows >= 4)
    }

    T.test("zones tile the screen exactly, with no gaps or overlap") {
        for count in 1...12 {
            let zones = AutoArrange.zones(count: count, aspectRatio: ultrawide)
            T.expect(zones.count == count, "count \(count) produced \(zones.count) zones")
            let area = zones.reduce(0) { $0 + $1.w * $1.h }
            T.expect(T.approx(area, 1.0), "count \(count) covers \(area) of the screen")
            T.expect(AutoArrange.isTileable(Layout(name: "auto", zones: zones)),
                     "count \(count) produced overlapping zones")
        }
    }

    T.test("zones stretch the last row to fill the width") {
        // 5 on an ultrawide: three across the top, two stretched across the bottom.
        let zones = AutoArrange.zones(count: 5, aspectRatio: ultrawide)
        T.expect(T.approx(zones[0].w, 1.0 / 3))
        T.expect(T.approx(zones[0].h, 0.5))
        T.expect(T.approx(zones[3].w, 0.5))
        T.expect(T.approx(zones[3].y, 0.5))
        T.expect(T.approx(zones[4].x, 0.5))
        T.expect(zones.map(\.name) == ["Auto 1", "Auto 2", "Auto 3", "Auto 4", "Auto 5"])
    }

    T.test("zones for a single window fill the screen") {
        let zones = AutoArrange.zones(count: 1, aspectRatio: laptop)
        T.expect(zones.count == 1)
        T.expect(T.approx(zones[0].w, 1) && T.approx(zones[0].h, 1))
    }

    T.test("zones for no windows are empty") {
        T.expect(AutoArrange.zones(count: 0, aspectRatio: laptop).isEmpty)
    }

    T.test("isTileable rejects overlapping layouts, accepts touching ones") {
        let stacked = Layout(name: "Stacked", zones: [
            Zone(name: "Full A", x: 0, y: 0, w: 1, h: 1),
            Zone(name: "Full B", x: 0, y: 0, w: 1, h: 1),
        ])
        T.expect(!AutoArrange.isTileable(stacked))
        T.expect(AutoArrange.isTileable(Layout(name: "Halves", zones: Layout.grid(cols: 2, rows: 1))))
        T.expect(AutoArrange.isTileable(Layout(name: "Empty", zones: [])))
        T.expect(AutoArrange.isTileable(Layout(name: "One", zones: [Zone(name: "Full", x: 0, y: 0, w: 1, h: 1)])))
        // A gap between zones is the user's business — only overlap disqualifies a layout.
        let gapped = Layout(name: "Gapped", zones: [
            Zone(name: "Left",  x: 0,   y: 0, w: 0.4, h: 1),
            Zone(name: "Right", x: 0.6, y: 0, w: 0.4, h: 1),
        ])
        T.expect(AutoArrange.isTileable(gapped))
        // A hairline overlap is rounding, not stacking.
        let hairline = Layout(name: "Hairline", zones: [
            Zone(name: "Left",  x: 0,     y: 0, w: 0.501, h: 1),
            Zone(name: "Right", x: 0.5,   y: 0, w: 0.5,   h: 1),
        ])
        T.expect(AutoArrange.isTileable(hairline))
    }

    T.test("plan prefers a saved layout with the right number of tileable zones") {
        let mine = Layout(name: "Mine", zones: [
            Zone(name: "Big",   x: 0,    y: 0, w: 0.75, h: 1),
            Zone(name: "Small", x: 0.75, y: 0, w: 0.25, h: 1),
        ])
        let planned = AutoArrange.plan(count: 2, aspectRatio: ultrawide, savedLayouts: [mine])
        T.expect(planned == mine.zones)
    }

    T.test("plan ignores saved layouts of the wrong size or with overlaps") {
        let wrongSize = Layout(name: "Three", zones: Layout.grid(cols: 3, rows: 1))
        let overlapping = Layout(name: "Stacked", zones: [
            Zone(name: "A", x: 0, y: 0, w: 1, h: 1),
            Zone(name: "B", x: 0, y: 0, w: 1, h: 1),
        ])
        let planned = AutoArrange.plan(count: 2, aspectRatio: ultrawide,
                                       savedLayouts: [wrongSize, overlapping])
        let computed = AutoArrange.zones(count: 2, aspectRatio: ultrawide)
        // Compare geometry, not identity — every Zone gets a fresh id.
        T.expect(planned.map(\.x) == computed.map(\.x) && planned.map(\.w) == computed.map(\.w))
    }

    T.test("plan with no windows is empty") {
        T.expect(AutoArrange.plan(count: 0, aspectRatio: laptop, savedLayouts: []).isEmpty)
    }

    T.test("assign keeps windows on the side they are already on") {
        // Two zones, left and right; the windows are given right-first.
        let zones = [CGRect(x: 0, y: 0, width: 50, height: 100),
                     CGRect(x: 50, y: 0, width: 50, height: 100)]
        let windows = [CGRect(x: 70, y: 10, width: 20, height: 20),   // already on the right
                       CGRect(x: 5,  y: 10, width: 20, height: 20)]   // already on the left
        let pairs = AutoArrange.assign(windows: windows, zones: zones)
        T.expect(pairs.count == 2)
        T.expect(pairs[0].zone == 0 && pairs[0].window == 1)
        T.expect(pairs[1].zone == 1 && pairs[1].window == 0)
    }

    T.test("assign is deterministic when windows sit on top of each other") {
        let zones = [CGRect(x: 0, y: 0, width: 50, height: 100),
                     CGRect(x: 50, y: 0, width: 50, height: 100)]
        let identical = CGRect(x: 40, y: 40, width: 20, height: 20)
        let first = AutoArrange.assign(windows: [identical, identical], zones: zones)
        let second = AutoArrange.assign(windows: [identical, identical], zones: zones)
        T.expect(first.map(\.zone) == second.map(\.zone))
        T.expect(first.map(\.window) == second.map(\.window))
        T.expect(Set(first.map(\.window)).count == 2, "each window is used once")
    }

    T.test("assign never uses a window or zone twice, even when counts differ") {
        let zones = [CGRect(x: 0, y: 0, width: 50, height: 50),
                     CGRect(x: 50, y: 0, width: 50, height: 50),
                     CGRect(x: 0, y: 50, width: 100, height: 50)]
        let windows = [CGRect(x: 0, y: 0, width: 10, height: 10),
                       CGRect(x: 90, y: 90, width: 10, height: 10)]
        let pairs = AutoArrange.assign(windows: windows, zones: zones)
        T.expect(pairs.count == 2, "capped at the shorter input")
        T.expect(Set(pairs.map(\.zone)).count == 2)
        T.expect(Set(pairs.map(\.window)).count == 2)
        T.expect(pairs[0].zone < pairs[1].zone, "ordered by zone")
    }

    T.test("assign with nothing to place returns nothing") {
        T.expect(AutoArrange.assign(windows: [], zones: []).isEmpty)
    }
}
