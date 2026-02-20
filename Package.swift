// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WriteAssist",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "WriteAssist",
            path: "Sources"
        )
    ]
)
