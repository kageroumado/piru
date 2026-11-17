// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

/// Stand-ins for Apple modules on platforms without them, each named for the module it
/// replaces so a shared file's `import X` compiles unchanged. Consumers depend on them only
/// `.when(platforms: [.android, .linux])`.
let portable: [Platform] = [.android, .linux]

let package = Package(
    name: "PiruCompat",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "os", targets: ["os"]),
        .library(name: "OSLog", targets: ["OSLog"]),
        .library(name: "CryptoKit", targets: ["CryptoKit"]),
        .library(name: "CoreLocation", targets: ["CoreLocation"]),
        .library(name: "SwiftData", targets: ["SwiftData"]),
        .library(name: "PortableData", targets: ["PortableData"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        // A range, not a pin: Skip's tool (skipstone) requires 602.x in the same graph.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0" ..< "605.0.0"),
    ],
    targets: [
        .target(name: "os"),
        .target(name: "OSLog", dependencies: ["os"]),
        // swift-crypto is Apple's API-compatible open-source build of CryptoKit. On Apple platforms
        // the module is empty: there, swift-crypto itself re-exports the real CryptoKit.
        .target(
            name: "CryptoKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: portable))],
        ),
        .target(name: "CoreLocation"),
        .target(name: "SwiftData", dependencies: ["PortableData"]),
        // SwiftData's API over SQLite. Named apart from SwiftData so it builds, and is tested, on macOS too.
        .target(
            name: "PortableData",
            dependencies: [
                "PortableDataMacros",
                // Loaded by every target downstream, so `#Predicate` expands off Apple platforms.
                .target(name: "FoundationMacros", condition: .when(platforms: portable)),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
        ),
        // swift-foundation's plugin for `#Predicate`, vendored (Sources/FoundationMacros/VENDORED.md).
        .macro(
            name: "FoundationMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            exclude: ["VENDORED.md"],
        ),
        .macro(
            name: "PortableDataMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
        ),
        .testTarget(name: "PortableDataTests", dependencies: ["PortableData", .product(name: "GRDB", package: "GRDB.swift")]),
        // The persistence contract (android/README.md), tested against the app's own models as the
        // Android stage compiles them: StageSources copies each file named in staged-sources.txt
        // with android/substitutions.txt applied. The settings are the app's, as in PiruCore.
        .testTarget(
            name: "PiruModelTests",
            dependencies: ["PortableData", "os", "CoreLocation", .product(name: "GRDB", package: "GRDB.swift")],
            exclude: ["staged-sources.txt", "stage_file.py"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ],
            plugins: ["StageSources"],
        ),
        // The update check's release picking and version order: the app's own file, linked in from
        // app/Sources/Piru/Android/Update, which needs nothing past Foundation.
        .testTarget(
            name: "AppReleaseTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ],
        ),
        // Grammar agreement for counted phrases: the app's own file, linked in from
        // app/Sources/Piru/Android/Platform, which needs nothing past Foundation.
        .testTarget(
            name: "InflectionTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ],
        ),
        // The pairing QR code as Android draws it, read back with Core Image: the app's own file,
        // linked in from app/Sources/Piru/Android/Platform, which needs only Foundation.
        .testTarget(
            name: "QRCodeTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ],
        ),
        // A share's compressed body as Android writes and reads it, against Apple's Compression:
        // the app's own file, linked in from app/Sources/Piru/Android/Platform, which needs only
        // Foundation and zlib.
        .testTarget(
            name: "ShareCompressionTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ],
        ),
        .plugin(name: "StageSources", capability: .buildTool()),
    ],
)
