import Foundation
import CoreGraphics
import SashKit

func runZoneTests() {
    T.test("Zone.rect right-half on origin screen") {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let r = Zone(name: "Right", x: 0.5, y: 0, w: 0.5, h: 1).rect(inVisibleFrame: vf)
        T.expect(T.approx(r.origin.x, 500))
        T.expect(T.approx(r.origin.y, 0))
        T.expect(T.approx(r.width, 500))
        T.expect(T.approx(r.height, 800))
    }

    T.test("Zone.rect flips y for a top zone") {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let r = Zone(name: "TL", x: 0, y: 0, w: 0.5, h: 0.5).rect(inVisibleFrame: vf)
        T.expect(T.approx(r.origin.y, 400))   // (1 - 0 - 0.5) * 800
        T.expect(T.approx(r.height, 400))
    }

    T.test("Zone.rect respects an offset (secondary) monitor") {
        let vf = CGRect(x: 1440, y: 120, width: 800, height: 600)
        let r = Zone(name: "Full", x: 0, y: 0, w: 1, h: 1).rect(inVisibleFrame: vf)
        T.expect(r == vf)
    }

    T.test("Zone Codable round-trips including id") {
        let zone = Zone(name: "Center", x: 0.25, y: 0.1, w: 0.5, h: 0.8)
        let data = try JSONEncoder().encode(zone)
        let decoded = try JSONDecoder().decode(Zone.self, from: data)
        T.expect(decoded == zone)
        T.expect(decoded.id == zone.id)
    }

    T.test("Zone decodes legacy JSON without an id") {
        let json = Data(#"{"name":"L","x":0,"y":0,"w":0.5,"h":1}"#.utf8)
        let zone = try JSONDecoder().decode(Zone.self, from: json)
        T.expect(zone.name == "L")
        T.expect(T.approx(zone.w, 0.5))
    }
}
