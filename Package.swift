// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sash",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, side-effect-free logic (geometry math, layouts, persistence).
        // No window server needed, so it is fully testable in headless CI.
        .target(
            name: "SashKit",
            path: "Sources/SashKit"
        ),
        // The menu-bar app: AppKit + Accessibility glue that drives the Kit.
        .executableTarget(
            name: "Sash",
            dependencies: ["SashKit"],
            path: "Sources/Sash"
        ),
        // Self-contained test runner. Runs with `swift run SashTests`, so it works on
        // machines with only Command Line Tools (where XCTest/swift-testing aren't wired into
        // `swift test`). Exits non-zero on any failure. See scripts/coverage.sh for coverage.
        .executableTarget(
            name: "SashTests",
            dependencies: ["SashKit"],
            path: "Tests/SashTests"
        ),
    ]
)
