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
}
