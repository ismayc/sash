import Foundation
import CoreGraphics
import SashKit

func runZoneReflowTests() {

    // A screen split into a top and a bottom half, AppKit coords (y grows up).
    // Bottom tile: y 0…400. Top tile: y 400…800.
    let bottom = CGRect(x: 0, y: 0, width: 1000, height: 400)
    let top = CGRect(x: 0, y: 400, width: 1000, height: 400)

    T.test("tiles that all fit are left exactly alone") {
        let out = ZoneReflow.adjusted(zones: [bottom, top], minimums: [.zero, .zero])
        T.expect(out == [bottom, top])
    }

    T.test("a stubborn window's tile grows and its neighbour gives up the difference") {
        // The bottom window refuses to go below 440 — 40 more than its tile.
        let out = ZoneReflow.adjusted(zones: [bottom, top],
                                      minimums: [CGSize(width: 1000, height: 440), .zero])
        T.expect(T.approx(out[0].height, 440), "grew to what the window insists on")
        T.expect(T.approx(out[0].minY, 0), "still anchored to the bottom edge")
        T.expect(T.approx(out[1].height, 360), "neighbour gave up the difference")
        T.expect(T.approx(out[1].minY, 440), "and moved up to meet it")
        T.expect(T.approx(out[0].maxY, out[1].minY), "the tiling stays watertight")
        let total = out[0].height + out[1].height
        T.expect(T.approx(total, 800), "no space invented or lost")
    }

    T.test("the same works along the horizontal axis") {
        let left = CGRect(x: 0, y: 0, width: 500, height: 800)
        let right = CGRect(x: 500, y: 0, width: 500, height: 800)
        let out = ZoneReflow.adjusted(zones: [left, right],
                                      minimums: [CGSize(width: 560, height: 800), .zero])
        T.expect(T.approx(out[0].width, 560))
        T.expect(T.approx(out[1].minX, 560))
        T.expect(T.approx(out[1].width, 440))
    }

    T.test("a donor never gives up more than its cap, so it can't be squashed flat") {
        // The bottom window demands almost the whole screen; the top tile may only give 25%.
        let out = ZoneReflow.adjusted(zones: [bottom, top],
                                      minimums: [CGSize(width: 1000, height: 790), .zero])
        let cap = 400 * ZoneReflow.maxDonationFraction
        T.expect(T.approx(out[1].height, 400 - cap), "donor kept 75% of itself")
        T.expect(T.approx(out[0].height, 400 + cap), "stubborn tile got what could be spared")
        T.expect(T.approx(out[0].maxY, out[1].minY), "still watertight, just not enough")
    }

    T.test("a donor keeps whatever its own window demands") {
        // Both windows are stubborn: the top one needs 380 of its 400, so only 20 is spare.
        let out = ZoneReflow.adjusted(zones: [bottom, top],
                                      minimums: [CGSize(width: 1000, height: 500),
                                                 CGSize(width: 1000, height: 380)])
        T.expect(T.approx(out[1].height, 380), "donor shrank only to its own minimum")
        T.expect(T.approx(out[0].height, 420))
    }

    T.test("rounding-sized deficits are ignored") {
        let out = ZoneReflow.adjusted(zones: [bottom, top],
                                      minimums: [CGSize(width: 1000, height: 400.4), .zero])
        T.expect(out == [bottom, top], "sub-point differences are not a refusal")
    }

    T.test("an edge with nothing on the far side is left alone") {
        // One tile, floating: its top edge borders nothing that could donate.
        let lonely = CGRect(x: 0, y: 0, width: 500, height: 400)
        let out = ZoneReflow.adjusted(zones: [lonely],
                                      minimums: [CGSize(width: 500, height: 900)])
        T.expect(out == [lonely])
    }

    T.test("a tile whose neighbour has no room to give is left alone") {
        // The top tile is already at its own minimum, so there is nothing to trade.
        let out = ZoneReflow.adjusted(zones: [bottom, top],
                                      minimums: [CGSize(width: 1000, height: 500),
                                                 CGSize(width: 1000, height: 400)])
        T.expect(out == [bottom, top])
    }

    T.test("mismatched inputs are refused rather than guessed at") {
        T.expect(ZoneReflow.adjusted(zones: [bottom, top], minimums: [.zero]) == [bottom, top])
    }

    T.test("a full row of tiles moves together, keeping the grid watertight") {
        // Three across the top, two across the bottom — the computed 5-window ultrawide grid.
        let bottomRow = [CGRect(x: 0, y: 0, width: 500, height: 400),
                         CGRect(x: 500, y: 0, width: 500, height: 400)]
        let topRow = [CGRect(x: 0, y: 400, width: 333, height: 400),
                      CGRect(x: 333, y: 400, width: 334, height: 400),
                      CGRect(x: 667, y: 400, width: 333, height: 400)]
        let zones = bottomRow + topRow
        var minimums = [CGSize](repeating: .zero, count: 5)
        minimums[1] = CGSize(width: 500, height: 450)      // one bottom window is stubborn
        let out = ZoneReflow.adjusted(zones: zones, minimums: minimums)
        T.expect(T.approx(out[0].height, 450), "the whole bottom row grew together")
        T.expect(T.approx(out[1].height, 450))
        for i in 2..<5 {
            T.expect(T.approx(out[i].height, 350), "the whole top row donated together")
            T.expect(T.approx(out[i].minY, 450))
        }
    }

    T.test("an untouched column is not dragged along by a neighbour's split") {
        // "My Layout": full-height columns either side of a column split in two. Only the
        // split should move.
        let leftFull = CGRect(x: 0, y: 0, width: 333, height: 800)
        let midBottom = CGRect(x: 333, y: 0, width: 334, height: 400)
        let midTop = CGRect(x: 333, y: 400, width: 334, height: 400)
        let rightFull = CGRect(x: 667, y: 0, width: 333, height: 800)
        let out = ZoneReflow.adjusted(zones: [leftFull, midBottom, midTop, rightFull],
                                      minimums: [.zero, CGSize(width: 334, height: 460), .zero, .zero])
        T.expect(out[0] == leftFull, "the full-height column is untouched")
        T.expect(out[3] == rightFull)
        T.expect(T.approx(out[1].height, 460))
        T.expect(T.approx(out[2].height, 340))
    }
}
