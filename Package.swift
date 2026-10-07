// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quote",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "QuoteFileLogic"),
        .executableTarget(
            name: "quote",
            dependencies: ["QuoteFileLogic"]
        ),
        .testTarget(
            name: "quoteTests",
            dependencies: ["QuoteFileLogic"]
        ),
    ]
)
