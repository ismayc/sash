import Foundation
import CoreGraphics
import SashKit

func runDisplayTargetTests() {
    T.test("the chosen display is used while it is attached") {
        T.expect(DisplayTarget.active(desired: 7, attached: [1, 7, 9]) == 7)
    }

    T.test("choosing nothing acts on nothing") {
        T.expect(DisplayTarget.active(desired: nil, attached: [1, 7]) == nil)
    }

    T.test("a chosen display that is not attached pauses rather than acting on another") {
        // The LG asleep or unplugged: not a fallback to the built-in display.
        T.expect(DisplayTarget.active(desired: 7, attached: [1, 9]) == nil)
    }

    T.test("no displays attached acts on nothing") {
        T.expect(DisplayTarget.active(desired: 7, attached: []) == nil)
    }

    T.test("the same choice resumes once the display is back") {
        let desired: CGDirectDisplayID? = 7
        T.expect(DisplayTarget.active(desired: desired, attached: [1]) == nil)
        T.expect(DisplayTarget.active(desired: desired, attached: [1, 7]) == 7)
    }

    T.test("the result is always either the chosen display or nothing") {
        let cases: [(CGDirectDisplayID?, [CGDirectDisplayID])] = [
            (nil, []), (nil, [1]), (1, [1]), (1, [2]), (2, [1, 2, 3]), (4, [1, 2, 3]),
        ]
        for (desired, attached) in cases {
            let result = DisplayTarget.active(desired: desired, attached: attached)
            T.expect(result == nil || result == desired, "got \(String(describing: result))")
        }
    }
}
