import Foundation
import CoreGraphics

/// A zone is a rectangle expressed as fractions (0...1) of a screen's *visible* frame,
/// using a top-left origin (x grows right, y grows down) because that's how people picture
/// a layout on paper. Zones may overlap (e.g. two full-screen zones for windows you cycle
/// between). This type is pure — no AppKit — so it is fully unit-testable.
public struct Zone: Codable, Hashable {
    /// Stable identity so window assignments survive add/delete/reorder in the editor.
    public var id: UUID
    public var name: String
    public var x: CGFloat
    public var y: CGFloat
    public var w: CGFloat
    public var h: CGFloat

    enum CodingKeys: String, CodingKey { case id, name, x, y, w, h }

    public init(id: UUID = UUID(), name: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        self.id = id; self.name = name; self.x = x; self.y = y; self.w = w; self.h = h
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        w = try c.decode(CGFloat.self, forKey: .w)
        h = try c.decode(CGFloat.self, forKey: .h)
    }

    /// Resolve this zone to an AppKit global rect, given the target screen's visible frame
    /// (also in AppKit global coordinates, bottom-left origin).
    public func rect(inVisibleFrame vf: CGRect) -> CGRect {
        let width = w * vf.width
        let height = h * vf.height
        let originX = vf.minX + x * vf.width
        // Flip y: our zone y is top-down, the visible frame is bottom-up.
        let originY = vf.minY + (1 - y - h) * vf.height
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}

/// A named collection of zones.
public struct Layout: Codable, Hashable {
    public var name: String
    public var zones: [Zone]

    public init(name: String, zones: [Zone]) {
        self.name = name
        self.zones = zones
    }
}

extension Layout {
    /// A pure cols×rows grid of evenly-tiled zones. Shared by the built-ins and the editor.
    /// Inputs below 1 are clamped so the divisor is never zero.
    public static func grid(cols: Int, rows: Int) -> [Zone] {
        let cc = max(cols, 1), rr = max(rows, 1)
        var zones: [Zone] = []
        for r in 0..<rr {
            for c in 0..<cc {
                zones.append(Zone(name: "R\(r + 1)C\(c + 1)",
                                  x: CGFloat(c) / CGFloat(cc), y: CGFloat(r) / CGFloat(rr),
                                  w: 1 / CGFloat(cc), h: 1 / CGFloat(rr)))
            }
        }
        return zones
    }

    /// Built-in starter layouts.
    public static let builtins: [Layout] = [
        Layout(name: "Halves", zones: [
            Zone(name: "Left",  x: 0,   y: 0, w: 0.5, h: 1),
            Zone(name: "Right", x: 0.5, y: 0, w: 0.5, h: 1),
        ]),
        Layout(name: "Thirds", zones: [
            Zone(name: "Left",   x: 0,       y: 0, w: 1.0/3, h: 1),
            Zone(name: "Center", x: 1.0/3,   y: 0, w: 1.0/3, h: 1),
            Zone(name: "Right",  x: 2.0/3,   y: 0, w: 1.0/3, h: 1),
        ]),
        Layout(name: "Quarters", zones: [
            Zone(name: "Top-Left",     x: 0,   y: 0,   w: 0.5, h: 0.5),
            Zone(name: "Top-Right",    x: 0.5, y: 0,   w: 0.5, h: 0.5),
            Zone(name: "Bottom-Left",  x: 0,   y: 0.5, w: 0.5, h: 0.5),
            Zone(name: "Bottom-Right", x: 0.5, y: 0.5, w: 0.5, h: 0.5),
        ]),
        Layout(name: "3×3 Grid", zones: Layout.grid(cols: 3, rows: 3)),
        Layout(name: "Maximize", zones: [
            Zone(name: "Full", x: 0, y: 0, w: 1, h: 1),
        ]),
    ]
}
