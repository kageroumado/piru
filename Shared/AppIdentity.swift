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

    private static func infoString(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("\(key) is missing from \(Bundle.main.bundleURL.lastPathComponent)'s Info.plist")
        }
        return value
    }
}
