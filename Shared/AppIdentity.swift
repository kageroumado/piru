import Foundation

/// The identifiers the app, its widget and its Live Activity share, read from each bundle's
/// Info.plist. Their one source is the `PIRU_BUNDLE_ID` project build setting, which also
/// derives every target's bundle ID and the app group entitlement — so moving the app to a
/// new identifier is a one-line change there, never a string hunt through the code.
nonisolated enum AppIdentity {
    /// The main app's bundle identifier, also in an extension, where `Bundle.main` is the
    /// extension's own bundle.
    static let bundleID = infoString("PiruBundleID")

    /// The app group holding the SwiftData store and the shared defaults.
    static let appGroup = infoString("PiruAppGroup")

    /// The `os.Logger` subsystem for everything the app and its extensions log.
    static let subsystem = bundleID

    /// The app group of the identity Piru shipped under before its current one. The main
    /// app is entitled to it and carries an install across through it (`LegacyHandoff`).
    /// Only the main app's Info.plist has the key: an extension reading this traps.
    static let legacyAppGroup = infoString("PiruLegacyAppGroup")

    /// Whether this build is the legacy identity itself — the app people are moving
    /// away from, which publishes its sandbox-only state for its successor and tells
    /// them where Piru went.
    static var isLegacy: Bool {
        appGroup == legacyAppGroup
    }

    /// The successor app's public TestFlight invitation, opened from the legacy build's
    /// "Piru has moved" notice.
    static let successorTestFlightURL = URL(string: "https://testflight.apple.com/join/JVB4589D")!

    private static func infoString(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("\(key) is missing from \(Bundle.main.bundleURL.lastPathComponent)'s Info.plist")
        }
        return value
    }
}
