import Foundation
import CoreGraphics

/// Works out a sensible tiling for however many windows happen to be on a screen, so a single
/// toggle can keep that screen arranged without the user picking a layout first.
///
/// The shape comes from the *screen's* aspect ratio: an ultrawide wants columns where a laptop
/// wants a 2×2. Candidate shapes are scored by how square the resulting tiles come out —
/// square-ish tiles are the ones that stay usable as the window count grows. This type is
/// pure — no AppKit — so it is fully unit-testable.
public enum AutoArrange {

    /// The tile aspect ratio we aim for. 1 (square) is deliberate: scoring against a squarer
    /// target keeps wide screens splitting into columns (four windows on an ultrawide become
    /// four columns, not a 2×2 of short letterboxes) while narrower screens still fall into
    /// grids.
    static let targetTileAspect = 1.0

    /// Two zones may overlap by this fraction of the screen before a saved layout is judged
    /// un-tileable — enough slack for rounding, not enough to stack two windows.
    static let overlapTolerance: CGFloat = 0.005

    /// Column/row shape for `count` windows on a screen of `aspectRatio` (width ÷ height).
    /// Rows hold `cols` tiles each except the last, which takes the remainder and stretches
    /// to fill the width.
    public static func shape(count: Int, aspectRatio: CGFloat) -> (cols: Int, rows: Int) {
        let n = max(count, 1)
        let aspect = Double(max(aspectRatio, 0.01))
        var best = (cols: n, rows: 1)
        var bestScore = Double.greatestFiniteMagnitude
        for rows in 1...n {
            let cols = Int((Double(n) / Double(rows)).rounded(.up))
            // Skip shapes where the full rows already hold every window — the last row of a
            // (rows, cols) pair like 4 rows × 2 cols for 5 windows would come out empty.
            guard (rows - 1) * cols < n else { continue }
            let tileAspect = aspect * Double(rows) / Double(cols)
            let score = abs(log(tileAspect / targetTileAspect))
            // Strictly-less keeps the earlier (wider, fewer-row) shape when scores tie.
            if score < bestScore {
                bestScore = score
                best = (cols, rows)
            }
        }
        return best
    }

    /// Tiles for `count` windows: a `shape`-sized grid whose last row stretches to fill the
    /// width when the count doesn't divide evenly (5 windows → 3 across, then 2 across).
    public static func zones(count: Int, aspectRatio: CGFloat) -> [Zone] {
        guard count > 0 else { return [] }
        let (cols, rows) = shape(count: count, aspectRatio: aspectRatio)
        let h = 1 / CGFloat(rows)
        var zones: [Zone] = []
        for row in 0..<rows {
            let inRow = (row == rows - 1) ? count - (rows - 1) * cols : cols
            let w = 1 / CGFloat(inRow)
            for col in 0..<inRow {
                zones.append(Zone(name: "Auto \(zones.count + 1)",
                                  x: CGFloat(col) * w, y: CGFloat(row) * h, w: w, h: h))
            }
        }
        return zones
    }

    /// Whether a saved layout can stand in for the computed grid. Overlapping zones are the
    /// disqualifier: they are a fine thing to *drag* into (two full-screen zones you cycle
    /// between), but auto-arrange would use them to stack windows instead of tiling them.
    public static func isTileable(_ layout: Layout) -> Bool {
        let rects = layout.zones.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        for i in rects.indices {
            for j in (i + 1)..<rects.count {
                let overlap = rects[i].intersection(rects[j])
                if overlap.width * overlap.height > overlapTolerance { return false }
            }
        }
        return true
    }

    /// The arrangement to apply: one of the user's own layouts when it has exactly the right
    /// number of non-overlapping zones, otherwise the computed grid. `savedLayouts` is searched
    /// in order, so precedence is the caller's to decide.
    public static func plan(count: Int, aspectRatio: CGFloat, savedLayouts: [Layout]) -> [Zone] {
        guard count > 0 else { return [] }
        if let match = savedLayouts.first(where: { $0.zones.count == count && isTileable($0) }) {
            return match.zones
        }
        return zones(count: count, aspectRatio: aspectRatio)
    }

    /// Pair each zone with the window already nearest to it, so arranging moves windows as
    /// little as possible — whatever is on the left stays on the left.
    ///
    /// Globally greedy: the closest zone/window pair is fixed first, then the closest of what
    /// remains, and so on. Ties break by index so the same input always gives the same result.
    /// The result is ordered by zone, and is as long as the shorter of the two inputs.
    public static func assign(windows: [CGRect], zones: [CGRect]) -> [(zone: Int, window: Int)] {
        var candidates: [(zone: Int, window: Int, distance: Double)] = []
        for z in zones.indices {
            for w in windows.indices {
                candidates.append((z, w, centerDistanceSquared(zones[z], windows[w])))
            }
        }
        candidates.sort { a, b in
            if a.distance != b.distance { return a.distance < b.distance }
            if a.zone != b.zone { return a.zone < b.zone }
            return a.window < b.window
        }

        var takenZones: Set<Int> = []
        var takenWindows: Set<Int> = []
        var pairs: [(zone: Int, window: Int)] = []
        for c in candidates where !takenZones.contains(c.zone) && !takenWindows.contains(c.window) {
            takenZones.insert(c.zone)
            takenWindows.insert(c.window)
            pairs.append((c.zone, c.window))
        }
        return pairs.sorted { $0.zone < $1.zone }
    }

    private static func centerDistanceSquared(_ a: CGRect, _ b: CGRect) -> Double {
        let dx = Double(a.midX - b.midX)
        let dy = Double(a.midY - b.midY)
        return dx * dx + dy * dy
    }
}
