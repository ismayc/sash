import Foundation
import CoreGraphics
import SashKit

func runGeometryMathTests() {
    T.test("appKitToCG flips the y axis") {
        let rect = CGRect(x: 50, y: 100, width: 400, height: 200)
        let cg = GeometryMath.appKitToCG(rect, primaryHeight: 900)
        T.expect(T.approx(cg.origin.x, 50))
        T.expect(T.approx(cg.origin.y, 600))   // 900 - 100 - 200
        T.expect(T.approx(cg.width, 400))
        T.expect(T.approx(cg.height, 200))
    }

    T.test("appKitToCG and cgToAppKit are inverses") {
        let rect = CGRect(x: 12, y: 34, width: 560, height: 78)
        let h: CGFloat = 1080
        let back = GeometryMath.cgToAppKit(GeometryMath.appKitToCG(rect, primaryHeight: h), primaryHeight: h)
        T.expect(T.approx(back.origin.x, rect.origin.x))
        T.expect(T.approx(back.origin.y, rect.origin.y))
        T.expect(T.approx(back.width, rect.width))
        T.expect(T.approx(back.height, rect.height))
    }

    // A screen's visible frame, AppKit global coords: x 0…1000, y 0…800.
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    T.test("containing leaves a rect that already fits alone") {
        let rect = CGRect(x: 100, y: 100, width: 300, height: 300)
        T.expect(GeometryMath.containing(rect, within: screen) == rect)
    }

    T.test("containing slides an overhanging rect back on screen") {
        // The real case: a window that refused to shrink to its zone and now hangs off the
        // bottom edge. Its size is kept; it slides up until it sits on the edge.
        let hangingOffBottom = CGRect(x: 0, y: -16, width: 500, height: 720)
        let fixed = GeometryMath.containing(hangingOffBottom, within: screen)
        T.expect(T.approx(fixed.minY, 0))
        T.expect(T.approx(fixed.height, 720), "size is never changed")

        let hangingOffRight = CGRect(x: 700, y: 100, width: 500, height: 200)
        T.expect(T.approx(GeometryMath.containing(hangingOffRight, within: screen).minX, 500))

        let hangingOffTop = CGRect(x: 0, y: 700, width: 200, height: 200)
        T.expect(T.approx(GeometryMath.containing(hangingOffTop, within: screen).minY, 600))

        let hangingOffLeft = CGRect(x: -50, y: 100, width: 200, height: 200)
        T.expect(T.approx(GeometryMath.containing(hangingOffLeft, within: screen).minX, 0))
    }

    T.test("containing pins a too-big rect to the top-left, keeping its title bar reachable") {
        let tooTall = CGRect(x: 10, y: -100, width: 200, height: 1200)
        let fixed = GeometryMath.containing(tooTall, within: screen)
        T.expect(T.approx(fixed.maxY, 800), "top edge stays on screen")
        T.expect(T.approx(fixed.minX, 10))

        let tooWide = CGRect(x: -30, y: 10, width: 1400, height: 200)
        T.expect(T.approx(GeometryMath.containing(tooWide, within: screen).minX, 0))
    }

    T.test("containing respects a screen that is not at the origin") {
        // The ultrawide sits above and left of the primary display.
        let ultrawide = CGRect(x: -827, y: 1329, width: 3440, height: 1409)
        let overhanging = CGRect(x: -827, y: 1313, width: 2007, height: 720)
        let fixed = GeometryMath.containing(overhanging, within: ultrawide)
        T.expect(T.approx(fixed.minY, 1329))
        T.expect(T.approx(fixed.minX, -827))
    }
}
