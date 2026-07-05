import Foundation
import CoreGraphics

/// A tiny dependency-free test harness so the suite runs with `swift run` on any machine,
/// including ones with only the Command Line Tools installed.
enum T {
    static var checks = 0
    static var failures = 0
    static var currentTest = ""

    static func test(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        do {
            try body()
        } catch {
            failures += 1
            print("  ✘ \(name): threw \(error)")
        }
    }

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String = "",
                       file: StaticString = #file, line: UInt = #line) {
        checks += 1
        if !condition {
            failures += 1
            let detail = message().isEmpty ? "" : " — \(message())"
            print("  ✘ [\(currentTest)]\(detail)  (\(file):\(line))")
        }
    }

    static func approx(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.001) -> Bool {
        abs(a - b) < tol
    }

    /// Print the summary and return the process exit code.
    static func summarize() -> Int32 {
        if failures == 0 {
            print("\n✓ All \(checks) checks passed.")
            return 0
        } else {
            print("\n✘ \(failures) failure(s) out of \(checks) checks.")
            return 1
        }
    }
}
