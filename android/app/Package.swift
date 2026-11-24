// swift-tools-version: 6.2
// Piru for Android: a Skip Fuse package that android/tools/stage.py fills with the iOS app's
// sources. Edit this template in android/app, never the staged copy.
import PackageDescription

/// The app's Swift settings, mirrored from Piru.xcodeproj so a staged file means what it
/// means in the iOS build. MemberImportVisibility is left off: it only narrows what a file
/// sees, and Skip supplies Foundation types (LocalizedStringResource, UserDefaults, Bundle)
/// from SkipAndroidBridge, a module no upstream file names.
let appSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "piru-android",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Piru", type: .dynamic, targets: ["Piru"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", exact: "1.9.13"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", exact: "1.19.4"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.1.4"),
        .package(url: "https://github.com/skiptools/swift-android-native.git", exact: "1.5.3"),
        .package(path: "@COMPAT_PATH@"),
    ],
    targets: [
        .target(
            name: "Piru",
            dependencies: [
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "GRDB", package: "GRDB.swift"),
                // AndroidResources reads the module's APK assets through it.
                .product(
                    name: "AndroidAssetManager", package: "swift-android-native",
                    condition: .when(platforms: [.android]),
                ),
                // android/substitutions.txt rewrites `import SwiftData` and `import CryptoKit`
                // to these.
                .product(name: "PortableData", package: "Compat"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            resources: [.process("Resources")],
            // Apple's Foundation re-exports Observation, so shared files write `@Observable`
            // under `import Foundation` alone; the implicit import reproduces that re-export.
            swiftSettings: appSwiftSettings + [
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "Observation"]),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")],
        ),
    ],
)
