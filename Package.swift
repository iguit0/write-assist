// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WriteAssist",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        // Core library — all business logic, rules, services, and UI.
        // Separated from the executable entry point so tests can import it.
        // Resources/ is included via Bundle.module so JSON word lists can be
        // loaded at runtime instead of being hardcoded in Swift source (#022).
        .target(
            name: "WriteAssistCore",
            path: "Sources",
            exclude: ["App"],
            resources: [.process("Resources")]
        ),
        // Thin executable — only the @main entry point (WriteAssistApp.swift).
        .executableTarget(
            name: "WriteAssist",
            dependencies: ["WriteAssistCore"],
            path: "Sources/App"
        ),
        // Unit tests for core business logic.
        .testTarget(
            name: "WriteAssistTests",
            dependencies: ["WriteAssistCore"],
            path: "Tests/WriteAssistTests"
        )
    ]
)
