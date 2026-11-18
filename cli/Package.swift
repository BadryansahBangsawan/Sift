// swift-tools-version:5.9
import PackageDescription

// The executable is `sift-cli`, not `sift`: Homebrew core already ships an
// unrelated `sift` (a grep alternative), and the two would clash on PATH.
let package = Package(
    name: "sift",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "sift-cli", targets: ["sift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "sift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/sift"
        ),
        .testTarget(
            name: "siftTests",
            dependencies: ["sift"],
            path: "Tests/siftTests"
        ),
    ]
)
