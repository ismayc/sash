import Foundation
import CoreGraphics
import SashKit

func runScreenMarginsTests() {
    // A stand-in for one screen's visible frame, deliberately not at the origin so a margin
    // applied to the wrong corner shows up as a wrong origin rather than a wrong size.
    let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)

    T.test("nothing kept clear leaves the visible frame alone") {
        T.expect(ScreenMargins.none.applied(to: visible) == visible)
        T.expect(ScreenMargins.none.isEmpty)
        T.expect(ScreenMargins.none.summary.isEmpty)
    }

    T.test("a bottom margin lifts the usable area off the bottom edge") {
        // The widgets case: keep the bottom 200 pt clear, use everything above it.
        let area = ScreenMargins(bottom: 200).applied(to: visible)
        T.expect(area.minY == 250, "got minY \(area.minY)")
        T.expect(area.height == 600, "got height \(area.height)")
        T.expect(area.minX == visible.minX && area.width == visible.width)
    }

    T.test("a top margin shortens the usable area without moving its origin") {
        let area = ScreenMargins(top: 150).applied(to: visible)
        T.expect(area.minY == visible.minY, "got minY \(area.minY)")
        T.expect(area.height == 650, "got height \(area.height)")
    }

    T.test("left and right margins narrow the usable area from each side") {
        let area = ScreenMargins(left: 100, right: 50).applied(to: visible)
        T.expect(area.minX == 200, "got minX \(area.minX)")
        T.expect(area.width == 850, "got width \(area.width)")
        T.expect(area.minY == visible.minY && area.height == visible.height)
    }

    T.test("all four edges apply at once") {
        let area = ScreenMargins(top: 10, bottom: 20, left: 30, right: 40).applied(to: visible)
        T.expect(area == CGRect(x: 130, y: 70, width: 930, height: 770), "got \(area)")
    }

    T.test("negative margins are treated as none rather than growing the screen") {
        let area = ScreenMargins(top: -50, bottom: -50, left: -50, right: -50).applied(to: visible)
        T.expect(area == visible, "got \(area)")
    }

    T.test("greedy opposing margins are scaled down together, keeping their balance") {
        // 700 + 700 asked for out of 800; only 640 (80%) may be taken, split in the same 1:1
        // ratio — a screen can never be reserved down to nothing.
        let area = ScreenMargins(top: 700, bottom: 700).applied(to: visible)
        T.expect(T.approx(area.height, 160), "got height \(area.height)")
        T.expect(T.approx(area.minY, visible.minY + 320), "got minY \(area.minY)")
    }

    T.test("scaling keeps an uneven split uneven") {
        // 3:1 asked for, so 3:1 granted out of the 640 pt budget.
        let area = ScreenMargins(top: 900, bottom: 300).applied(to: visible)
        T.expect(T.approx(area.minY, visible.minY + 160), "got minY \(area.minY)")
        T.expect(T.approx(area.height, 160), "got height \(area.height)")
    }

    T.test("a zero-sized screen yields a zero-sized usable area rather than a negative one") {
        let area = ScreenMargins(top: 10, left: 10).applied(to: .zero)
        T.expect(area.width == 0 && area.height == 0, "got \(area)")
    }

    // MARK: - Reading and setting single edges

    T.test("each edge reports its own value") {
        let m = ScreenMargins(top: 1, bottom: 2, left: 3, right: 4)
        T.expect(m.value(for: .top) == 1)
        T.expect(m.value(for: .bottom) == 2)
        T.expect(m.value(for: .left) == 3)
        T.expect(m.value(for: .right) == 4)
        T.expect(!m.isEmpty)
    }

    T.test("edges know their opposite and their axis") {
        T.expect(ScreenMargins.Edge.top.opposite == .bottom)
        T.expect(ScreenMargins.Edge.bottom.opposite == .top)
        T.expect(ScreenMargins.Edge.left.opposite == .right)
        T.expect(ScreenMargins.Edge.right.opposite == .left)
        T.expect(ScreenMargins.Edge.top.isVertical && ScreenMargins.Edge.bottom.isVertical)
        T.expect(!ScreenMargins.Edge.left.isVertical && !ScreenMargins.Edge.right.isVertical)
    }

    T.test("setting an edge changes only that edge") {
        let start = ScreenMargins(top: 5, bottom: 5, left: 5, right: 5)
        for edge in ScreenMargins.Edge.allCases {
            let moved = start.setting(edge, to: 60, within: visible)
            T.expect(moved.value(for: edge) == 60, "\(edge) got \(moved.value(for: edge))")
            for other in ScreenMargins.Edge.allCases where other != edge {
                T.expect(moved.value(for: other) == 5, "\(edge) disturbed \(other)")
            }
        }
    }

    T.test("dragging an edge past the far side stops at the minimum usable share") {
        // Dragging the bottom edge up 5000 pt on an 800 pt screen: it stops at 640, leaving 20%.
        let m = ScreenMargins.none.setting(.bottom, to: 5000, within: visible)
        T.expect(m.bottom == 640, "got \(m.bottom)")
        T.expect(T.approx(m.applied(to: visible).height, 160))
    }

    T.test("an edge is clamped against what the opposite edge already claims") {
        let m = ScreenMargins(top: 240).setting(.bottom, to: 5000, within: visible)
        T.expect(m.bottom == 400, "got \(m.bottom)")   // 640 budget − 240 already taken
    }

    T.test("an edge can never be dragged past its own side into a negative margin") {
        let m = ScreenMargins(left: 100).setting(.left, to: -300, within: visible)
        T.expect(m.left == 0, "got \(m.left)")
    }

    T.test("horizontal edges are clamped against the width, not the height") {
        let m = ScreenMargins.none.setting(.right, to: 5000, within: visible)
        T.expect(m.right == 800, "got \(m.right)")     // 80% of the 1000 pt width
    }

    T.test("an edge with no room left cannot move at all") {
        let m = ScreenMargins(top: 900).setting(.bottom, to: 300, within: visible)
        T.expect(m.bottom == 0, "got \(m.bottom)")
    }

    // MARK: - Summary

    T.test("the summary names only the edges that are actually kept clear") {
        T.expect(ScreenMargins(bottom: 220).summary == "bottom 220 pt",
                 ScreenMargins(bottom: 220).summary)
        T.expect(ScreenMargins(top: 40, bottom: 220).summary == "top 40 · bottom 220 pt",
                 ScreenMargins(top: 40, bottom: 220).summary)
        T.expect(ScreenMargins(left: 10, right: 20).summary == "left 10 · right 20 pt",
                 ScreenMargins(left: 10, right: 20).summary)
    }

    T.test("a margin of less than a point is nothing at all") {
        // Brushing an edge mid-drag once left a screen reading "right 0 pt" in the menu: a
        // reserved strip nobody asked for, printed as zero. A sub-point margin now rounds away
        // everywhere at once — stored, shown and applied.
        let brushed = ScreenMargins(bottom: 385).setting(.right, to: 0.4, within: visible)
        T.expect(brushed.right == 0, "got \(brushed.right)")
        T.expect(brushed.summary == "bottom 385 pt", brushed.summary)
        T.expect(ScreenMargins(right: 0.4).isEmpty, "a sliver still counts as reserved")
        T.expect(ScreenMargins.decodeBook(ScreenMargins.encodeBook(["LG": ScreenMargins(right: 0.4)])).isEmpty)
    }

    T.test("a whole point is still a real margin") {
        let m = ScreenMargins.none.setting(.top, to: 1, within: visible)
        T.expect(m.top == 1 && !m.isEmpty && m.summary == "top 1 pt", m.summary)
    }

    T.test("the summary rounds to whole points") {
        T.expect(ScreenMargins(bottom: 219.6).summary == "bottom 220 pt",
                 ScreenMargins(bottom: 219.6).summary)
    }

    // MARK: - Persistence

    T.test("a book survives a round-trip through storage") {
        let book = ["LG ULTRAWIDE": ScreenMargins(bottom: 220),
                    "Built-in Retina Display": ScreenMargins(top: 12, left: 8)]
        let decoded = ScreenMargins.decodeBook(ScreenMargins.encodeBook(book))
        T.expect(decoded == book, "got \(decoded)")
    }

    T.test("displays with nothing kept clear are not stored") {
        let data = ScreenMargins.encodeBook(["LG": .none, "Studio Display": ScreenMargins(bottom: 5)])
        let decoded = ScreenMargins.decodeBook(data)
        T.expect(decoded.count == 1 && decoded["Studio Display"]?.bottom == 5, "got \(decoded)")
    }

    T.test("an empty book encodes and decodes as nothing reserved") {
        T.expect(ScreenMargins.decodeBook(ScreenMargins.encodeBook([:])).isEmpty)
    }

    T.test("missing or unreadable storage means nothing is kept clear") {
        // Never a crash and never a guess: an unset preference and a corrupted one both mean
        // Sash may use the whole screen.
        T.expect(ScreenMargins.decodeBook(nil).isEmpty)
        T.expect(ScreenMargins.decodeBook(Data("not json".utf8)).isEmpty)
        T.expect(ScreenMargins.decodeBook(Data()).isEmpty)
    }

    T.test("a stored entry with nothing kept clear is ignored on the way back in") {
        let data = Data(#"{"LG":{"top":0,"bottom":0,"left":0,"right":0}}"#.utf8)
        T.expect(ScreenMargins.decodeBook(data).isEmpty)
    }
}
