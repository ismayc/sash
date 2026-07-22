import Foundation
import CoreGraphics

/// Adjusts a set of tiles when a window flatly refuses to fit the one it was given.
///
/// Some apps enforce a minimum window size — several Electron-based editors will not go below
/// roughly 720pt tall — so a half-height tile leaves one overhanging its neighbour. Rather than
/// accept the overlap, the shared edge moves: the stubborn window's tile grows to the size the
/// window insists on, and the tile on the other side of that edge gives up the difference.
///
/// The result is a slightly uneven split instead of an exact one, which is the better trade —
/// uneven tiles that don't overlap beat even tiles that do. A donor never gives up more than
/// `maxDonationFraction` of itself, so one stubborn window can't squash its neighbour flat.
///
/// This type is pure — no AppKit — so it is fully unit-testable.
public enum ZoneReflow {

    /// Differences below this are rounding, not a refusal.
    static let tolerance: CGFloat = 1

    /// The most of itself a tile will give up to the tile next to it.
    public static let maxDonationFraction: CGFloat = 0.25

    /// Grow the tiles whose windows refused to fit, taking the space from whatever tile shares
    /// that edge. `minimums[i]` is the size window *i* insisted on, or `.zero` when it fitted
    /// fine and so tells us nothing about its limits.
    ///
    /// Rects are AppKit global (bottom-left origin). Both axes are adjusted — minimum heights
    /// are the common case, but minimum widths bite on narrow columns just the same.
    public static func adjusted(zones: [CGRect], minimums: [CGSize]) -> [CGRect] {
        guard zones.count == minimums.count else { return zones }
        let afterVertical = shiftEdges(in: zones, minimums: minimums, vertical: true)
        return shiftEdges(in: afterVertical, minimums: minimums, vertical: false)
    }

    /// One axis of the adjustment.
    ///
    /// A *cut* is a coordinate where one tile ends and another begins; shifting it trades
    /// length between the two sides. Which tiles sit on a cut is read from the tiles as they
    /// came in, while the space available to trade is read from the run so far — a tile that
    /// already donated to one edge won't over-donate to the next.
    ///
    /// Every tile touching a cut moves together, which keeps the tiling watertight. Where two
    /// unrelated columns happen to split at the same coordinate both shift, which is more than
    /// strictly needed but never leaves a gap or an overlap.
    private static func shiftEdges(in zones: [CGRect], minimums: [CGSize], vertical: Bool) -> [CGRect] {
        var result = zones
        let cuts = Set(zones.map { end($0, vertical) }).sorted()

        for cut in cuts {
            // Below/left of the edge: tiles that end here, and grow by moving it along.
            let below = zones.indices.filter { abs(end(zones[$0], vertical) - cut) < 0.001 }
            // Above/right of it: tiles that start here, and give up the same amount.
            let above = zones.indices.filter { abs(start(zones[$0], vertical) - cut) < 0.001 }
            guard !below.isEmpty, !above.isEmpty else { continue }

            // Accumulated with plain loops rather than map/min/max, whose `?? default` would
            // be dead code that the coverage floor then can't reach.
            var deficit = -CGFloat.greatestFiniteMagnitude
            for i in below {
                deficit = max(deficit, need(minimums[i], vertical) - length(result[i], vertical))
            }
            guard deficit > tolerance else { continue }

            // A donor keeps whatever its own window demanded, and never gives up more than
            // its share of the cap.
            var capped = CGFloat.greatestFiniteMagnitude
            var spare = CGFloat.greatestFiniteMagnitude
            for i in above {
                capped = min(capped, length(result[i], vertical) * maxDonationFraction)
                spare = min(spare, length(result[i], vertical) - need(minimums[i], vertical))
            }
            let shift = min(deficit, capped, max(0, spare))
            guard shift > tolerance else { continue }

            for i in below {
                result[i] = withLength(result[i], length(result[i], vertical) + shift, vertical)
            }
            for i in above {
                result[i] = withLength(result[i], length(result[i], vertical) - shift, vertical)
                result[i] = withStart(result[i], start(result[i], vertical) + shift, vertical)
            }
        }
        return result
    }

    // MARK: - Axis accessors

    private static func start(_ r: CGRect, _ vertical: Bool) -> CGFloat { vertical ? r.minY : r.minX }
    private static func end(_ r: CGRect, _ vertical: Bool) -> CGFloat { vertical ? r.maxY : r.maxX }
    private static func length(_ r: CGRect, _ vertical: Bool) -> CGFloat { vertical ? r.height : r.width }
    private static func need(_ s: CGSize, _ vertical: Bool) -> CGFloat { vertical ? s.height : s.width }

    private static func withLength(_ r: CGRect, _ value: CGFloat, _ vertical: Bool) -> CGRect {
        vertical ? CGRect(x: r.minX, y: r.minY, width: r.width, height: value)
                 : CGRect(x: r.minX, y: r.minY, width: value, height: r.height)
    }

    private static func withStart(_ r: CGRect, _ value: CGFloat, _ vertical: Bool) -> CGRect {
        vertical ? CGRect(x: r.minX, y: value, width: r.width, height: r.height)
                 : CGRect(x: value, y: r.minY, width: r.width, height: r.height)
    }
}
