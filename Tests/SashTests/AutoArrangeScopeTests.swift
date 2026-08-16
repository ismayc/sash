import Foundation
import CoreGraphics
import SashKit

func runAutoArrangeScopeTests() {
    let attached: [CGDirectDisplayID] = [1, 5, 9]

    T.test("off keeps nothing tiled") {
        T.expect(AutoArrangeScope.off.active(attached: attached).isEmpty)
        T.expect(!AutoArrangeScope.off.includes(5))
    }

    T.test("all displays means every display attached right now") {
        T.expect(AutoArrangeScope.allDisplays.active(attached: attached) == [1, 5, 9])
        T.expect(AutoArrangeScope.allDisplays.includes(5))
    }

    T.test("all displays picks up a monitor plugged in later, with no trip back to the menu") {
        let scope = AutoArrangeScope.allDisplays
        T.expect(scope.active(attached: [1]) == [1])
        T.expect(scope.active(attached: [1, 7]) == [1, 7])
    }

    T.test("all displays with nothing attached keeps nothing tiled") {
        T.expect(AutoArrangeScope.allDisplays.active(attached: []).isEmpty)
    }

    T.test("a hand-picked pair tiles exactly those two, out of three") {
        let two = AutoArrangeScope.displays([1, 9])
        T.expect(two.active(attached: attached) == [1, 9])
        T.expect(two.includes(1) && two.includes(9) && !two.includes(5))
    }

    T.test("a hand-picked set stays that set when a new monitor is plugged in") {
        // The difference from `allDisplays`: chosen means chosen, however many arrive later.
        let two = AutoArrangeScope.displays([1, 9])
        T.expect(two.active(attached: [1, 5, 9, 12]) == [1, 9])
    }

    T.test("the resolved order follows the system's, not the id order") {
        T.expect(AutoArrangeScope.displays([9, 1]).active(attached: [9, 5, 1]) == [9, 1])
    }

    T.test("one chosen display resolves to just that display") {
        T.expect(AutoArrangeScope.displays([5]).active(attached: attached) == [5])
    }

    T.test("a chosen display that is away pauses rather than tiling another") {
        // The same rule as DisplayTarget: unplugged is paused, not cancelled.
        T.expect(AutoArrangeScope.displays([5]).active(attached: [1, 9]).isEmpty)
        T.expect(AutoArrangeScope.displays([5]).active(attached: attached) == [5])
    }

    T.test("the rest of a pair keeps working while one of them is unplugged") {
        T.expect(AutoArrangeScope.displays([1, 9]).active(attached: [1, 5]) == [1])
    }

    // MARK: - Ticking displays on and off

    T.test("ticking a display from off starts a set of one") {
        T.expect(AutoArrangeScope.off.toggling(5, attached: attached) == .displays([5]))
    }

    T.test("ticking a second display adds to the set") {
        let one = AutoArrangeScope.displays([5])
        T.expect(one.toggling(9, attached: attached) == .displays([5, 9]))
    }

    T.test("unticking the last display leaves off, not an empty set") {
        T.expect(AutoArrangeScope.displays([5]).toggling(5, attached: attached) == .off)
    }

    T.test("unticking one of all monitors names the rest explicitly") {
        // "All" has to keep meaning "and whatever I plug in next", so it can't quietly become
        // "all but that one" — the two that are left are spelled out.
        T.expect(AutoArrangeScope.allDisplays.toggling(5, attached: attached) == .displays([1, 9]))
    }

    T.test("ticking every display by hand is not the same as choosing all monitors") {
        let each = attached.reduce(AutoArrangeScope.off) { $0.toggling($1, attached: attached) }
        T.expect(each == .displays([1, 5, 9]))
        T.expect(each != .allDisplays)
        T.expect(each.active(attached: [1, 5, 9, 12]) == [1, 5, 9])          // no new monitor
        T.expect(AutoArrangeScope.allDisplays.active(attached: [1, 5, 9, 12]) == [1, 5, 9, 12])
    }

    // MARK: - Storage

    T.test("every scope survives a round-trip through its stored form") {
        let scopes: [AutoArrangeScope] = [.off, .allDisplays, .displays([0]),
                                          .displays([1, 9]), .displays([4_294_967_294])]
        for scope in scopes {
            T.expect(AutoArrangeScope(rawValue: scope.rawValue) == scope, scope.rawValue)
        }
    }

    T.test("the stored forms are the ones the preference file is expected to hold") {
        T.expect(AutoArrangeScope.off.rawValue == "off")
        T.expect(AutoArrangeScope.allDisplays.rawValue == "all")
        T.expect(AutoArrangeScope.displays([5]).rawValue == "displays:5")
        T.expect(AutoArrangeScope.displays([9, 1]).rawValue == "displays:1,9",
                 AutoArrangeScope.displays([9, 1]).rawValue)                 // sorted, so stable
    }

    T.test("the superseded single-display preference still reads") {
        T.expect(AutoArrangeScope(rawValue: "display:5") == .displays([5]))
    }

    T.test("an unreadable preference leaves auto-arrange off rather than guessing a display") {
        for raw in ["", "yes", "display:", "displays:", "display:abc", "displays:-1,x",
                    "monitors:5", "all monitors"] {
            T.expect(AutoArrangeScope(rawValue: raw) == .off, raw)
        }
    }

    T.test("a partly-unreadable list keeps the displays it could read") {
        T.expect(AutoArrangeScope(rawValue: "displays:1,rubbish,9") == .displays([1, 9]))
    }
}
