// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubstanceValidator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "SubstanceValidator",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .testTarget(
            name: "SubstanceValidatorTests",
            dependencies: ["SubstanceValidator"],
        ),
    ],
)
