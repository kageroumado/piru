// swift-tools-version: 6.2
import PackageDescription

/// The app's Swift settings, mirrored from Piru.xcodeproj so a shared file means the same
/// thing here as in the app: MainActor default isolation, approachable concurrency, and
/// member-import visibility.
let appSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

/// Platforms without Apple's frameworks, where the stand-ins below take their place.
let portable: [Platform] = [.android, .linux]

let package = Package(
    name: "PiruCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Piru", targets: ["Piru"]),
    ],
    dependencies: [
        .package(path: "../Compat"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
    ],
    targets: [
        // Named `Piru` so module-qualified names (`Piru.SourceFacet`) resolve as they do in the app.
        // Sources are symlinks into the app tree: one copy of every file, compiled by both.
        .target(
            name: "Piru",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "os", package: "Compat", condition: .when(platforms: portable)),
                .product(name: "OSLog", package: "Compat", condition: .when(platforms: portable)),
                .product(name: "CryptoKit", package: "Compat", condition: .when(platforms: portable)),
                .product(name: "CoreLocation", package: "Compat", condition: .when(platforms: portable)),
                .product(name: "SwiftData", package: "Compat", condition: .when(platforms: portable)),
            ],
            // Apple's Foundation re-exports Observation, so shared files write `@Observable`
            // under `import Foundation` alone; the implicit import reproduces that re-export.
            swiftSettings: appSwiftSettings + [
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "Observation"], .when(platforms: portable)),
            ],
        ),

        .testTarget(
            name: "WikiTimingTests",
            dependencies: ["Piru", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: appSwiftSettings,
        ),

        // The core reads its identity from Info.plist, as the app's bundle provides it. On macOS the
        // plist is linked into the binary; elsewhere it sits at the root of the directory holding it.
        .executableTarget(
            name: "piru-smoke",
            dependencies: ["Piru"],
            exclude: ["Info.plist"],
            swiftSettings: appSwiftSettings,
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker",
                        "-sectcreate",
                        "-Xlinker",
                        "__TEXT",
                        "-Xlinker",
                        "__info_plist",
                        "-Xlinker",
                        "Sources/piru-smoke/Info.plist",
                    ],
                    .when(platforms: [.macOS]),
                ),
            ],
        ),
    ],
)
