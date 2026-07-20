import Foundation
import SashKit

func runDisplayNamingTests() {
    T.test("a reported name is used as-is") {
        T.expect(DisplayNaming.name(reported: "LG ULTRAWIDE", index: 0) == "LG ULTRAWIDE")
    }

    T.test("surrounding whitespace is trimmed") {
        T.expect(DisplayNaming.name(reported: "  LG ULTRAWIDE \n", index: 0) == "LG ULTRAWIDE")
    }

    T.test("a display reporting no name falls back to its one-based position") {
        T.expect(DisplayNaming.name(reported: "", index: 0) == "Display 1")
        T.expect(DisplayNaming.name(reported: "   ", index: 2) == "Display 3")
    }

    T.test("distinct names are left unsuffixed") {
        let names = DisplayNaming.uniqueNames(reported: ["LG ULTRAWIDE", "Built-in Retina Display"])
        T.expect(names == ["LG ULTRAWIDE", "Built-in Retina Display"], "got \(names)")
    }

    T.test("a single monitor is not suffixed") {
        T.expect(DisplayNaming.uniqueNames(reported: ["LG ULTRAWIDE"]) == ["LG ULTRAWIDE"])
    }

    T.test("two identical models are numbered in order") {
        let names = DisplayNaming.uniqueNames(reported: ["LG ULTRAWIDE", "LG ULTRAWIDE"])
        T.expect(names == ["LG ULTRAWIDE (1)", "LG ULTRAWIDE (2)"], "got \(names)")
    }

    T.test("only the duplicated name is suffixed") {
        let names = DisplayNaming.uniqueNames(reported: ["LG", "Built-in Retina Display", "LG"])
        T.expect(names == ["LG (1)", "Built-in Retina Display", "LG (2)"], "got \(names)")
    }

    T.test("three of a kind number sequentially") {
        let names = DisplayNaming.uniqueNames(reported: ["LG", "LG", "LG"])
        T.expect(names == ["LG (1)", "LG (2)", "LG (3)"], "got \(names)")
    }

    T.test("unnamed displays disambiguate by position, not by suffix") {
        // Both report nothing, so the positional fallback already makes them distinct.
        let names = DisplayNaming.uniqueNames(reported: ["", ""])
        T.expect(names == ["Display 1", "Display 2"], "got \(names)")
    }

    T.test("a fallback name colliding with a reported one is still disambiguated") {
        // A monitor that genuinely calls itself "Display 2" alongside an unnamed second display.
        let names = DisplayNaming.uniqueNames(reported: ["Display 2", ""])
        T.expect(names == ["Display 2 (1)", "Display 2 (2)"], "got \(names)")
    }

    T.test("no displays yields no names") {
        T.expect(DisplayNaming.uniqueNames(reported: []).isEmpty)
    }

    T.test("output count always matches input count") {
        let inputs = [["A"], ["A", "A"], ["A", "B", "A", ""], [], ["", "", "C"]]
        for input in inputs {
            let out = DisplayNaming.uniqueNames(reported: input)
            T.expect(out.count == input.count, "\(input.count) in, \(out.count) out")
        }
    }

    T.test("every name is unique for any input") {
        let tricky = ["LG", "LG", "", "", "LG", "Display 1", "Built-in"]
        let names = DisplayNaming.uniqueNames(reported: tricky)
        T.expect(Set(names).count == names.count, "duplicates in \(names)")
    }
}
