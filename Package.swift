// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "shh",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShhCore", targets: ["ShhCore"]),
        .executable(name: "shh", targets: ["shh"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "ShhCore"),
        .executableTarget(
            name: "shh",
            dependencies: [
                "ShhCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "ShhCoreTests", dependencies: ["ShhCore"]),
    ]
)
