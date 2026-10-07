// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quote",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "quote"),
        .testTarget(
            name: "quoteTests",
            dependencies: ["quote"]
        ),
    ]
)
