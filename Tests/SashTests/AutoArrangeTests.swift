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
        // A gap between zones is the user's business; only overlap disqualifies a layout.
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
        // Compare geometry, not identity, because every Zone gets a fresh id.
        T.expect(planned.map(\.x) == computed.map(\.x) && planned.map(\.w) == computed.map(\.w))
    }

    T.test("plan with no windows is empty") {
        T.expect(AutoArrange.plan(count: 0, aspectRatio: laptop, savedLayouts: []).isEmpty)
        T.expect(AutoArrange.plan(count: 0, aspectRatio: laptop, choice: .grid,
                                  savedLayouts: [], pickable: []).isEmpty)
    }

    // MARK: - Per-count choice

    // A custom asymmetric three-way split and a plain three-column built-in: the two things the
    // picker exists to choose between.
    let mine = Layout(name: "2 Wide, 1 Tall", zones: [
        Zone(name: "Top",    x: 0,    y: 0,   w: 0.58, h: 0.5),
        Zone(name: "Right",  x: 0.58, y: 0,   w: 0.42, h: 1),
        Zone(name: "Bottom", x: 0,    y: 0.5, w: 0.58, h: 0.5),
    ])
    let thirds = Layout(name: "Thirds", zones: Layout.grid(cols: 3, rows: 1))

    T.test("candidates offers every tileable layout of exactly the right size") {
        let overlapping = Layout(name: "Stacked", zones: [
            Zone(name: "A", x: 0, y: 0, w: 1, h: 1),
            Zone(name: "B", x: 0, y: 0, w: 1, h: 1),
            Zone(name: "C", x: 0, y: 0, w: 1, h: 1),
        ])
        let quarters = Layout(name: "Quarters", zones: Layout.grid(cols: 2, rows: 2))
        let pool = [mine, thirds, overlapping, quarters]
        T.expect(AutoArrange.candidates(count: 3, from: pool).map(\.name) == ["2 Wide, 1 Tall", "Thirds"])
        T.expect(AutoArrange.candidates(count: 4, from: pool).map(\.name) == ["Quarters"])
        T.expect(AutoArrange.candidates(count: 5, from: pool).isEmpty)
    }

    T.test("an explicit choice beats the saved layout that would otherwise win") {
        // Automatic keeps the old behavior: the user's own layout pre-empts the grid.
        T.expect(AutoArrange.plan(count: 3, aspectRatio: ultrawide, choice: .automatic,
                                  savedLayouts: [mine], pickable: [thirds, mine]) == mine.zones)
        // Naming a built-in reaches past the saved layout, the whole point of the picker.
        T.expect(AutoArrange.plan(count: 3, aspectRatio: ultrawide, choice: .named("Thirds"),
                                  savedLayouts: [mine], pickable: [thirds, mine]) == thirds.zones)
        // And the grid can be forced even though a saved layout fits.
        let forced = AutoArrange.plan(count: 3, aspectRatio: ultrawide, choice: .grid,
                                      savedLayouts: [mine], pickable: [thirds, mine])
        T.expect(forced.map(\.x) == AutoArrange.zones(count: 3, aspectRatio: ultrawide).map(\.x))
    }

    T.test("a choice naming a layout that is gone falls back to automatic") {
        // Deleted, renamed, or edited to a different number of zones: all the same to us.
        T.expect(AutoArrange.plan(count: 3, aspectRatio: ultrawide, choice: .named("Deleted"),
                                  savedLayouts: [mine], pickable: [mine]) == mine.zones)
        let noSaved = AutoArrange.plan(count: 3, aspectRatio: ultrawide, choice: .named("Deleted"),
                                       savedLayouts: [], pickable: [])
        T.expect(noSaved.map(\.x) == AutoArrange.zones(count: 3, aspectRatio: ultrawide).map(\.x))
    }

    T.test("resolvedLayout names what is really in force, so a menu can tick it") {
        T.expect(AutoArrange.resolvedLayout(count: 3, choice: .automatic,
                                            savedLayouts: [mine], pickable: [thirds, mine])?.name == "2 Wide, 1 Tall")
        T.expect(AutoArrange.resolvedLayout(count: 3, choice: .named("Thirds"),
                                            savedLayouts: [mine], pickable: [thirds, mine])?.name == "Thirds")
        T.expect(AutoArrange.resolvedLayout(count: 3, choice: .grid,
                                            savedLayouts: [mine], pickable: [thirds, mine]) == nil)
        // Nothing saved for this count: the grid is in force even under .automatic.
        T.expect(AutoArrange.resolvedLayout(count: 4, choice: .automatic,
                                            savedLayouts: [mine], pickable: [thirds, mine]) == nil)
    }

    T.test("a choice survives a round-trip through its stored string") {
        for choice in [AutoArrangeChoice.automatic, .grid, .named("2 Wide, 1 Tall")] {
            T.expect(AutoArrangeChoice(rawValue: choice.rawValue) == choice, "\(choice) round-trip")
        }
        // A layout named like one of the fixed cases still round-trips.
        T.expect(AutoArrangeChoice(rawValue: AutoArrangeChoice.named("grid").rawValue) == .named("grid"))
        // Anything unrecognized degrades to the default rather than failing.
        T.expect(AutoArrangeChoice(rawValue: "nonsense") == .automatic)
        T.expect(AutoArrangeChoice(rawValue: "") == .automatic)
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
