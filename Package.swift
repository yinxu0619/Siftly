// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Siftly",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Siftly", targets: ["Siftly"]),
        .library(name: "SiftlyKit", targets: ["SiftlyKit"])
    ],
    targets: [
        // Core logic + UI. Kept as a library so it can be unit tested and, in
        // the future, reused by a Windows/AppKit host target.
        .target(
            name: "SiftlyKit",
            path: "Sources/SiftlyKit",
            resources: [
                .process("Resources")
            ]
        ),
        // Thin executable host that boots the SwiftUI app.
        .executableTarget(
            name: "Siftly",
            dependencies: ["SiftlyKit"],
            path: "Sources/Siftly"
        ),
        .testTarget(
            name: "SiftlyKitTests",
            dependencies: ["SiftlyKit"],
            path: "Tests/SiftlyKitTests"
        )
    ]
)
