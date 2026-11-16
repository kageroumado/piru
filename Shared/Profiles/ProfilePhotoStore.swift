import Foundation

/// Profile photos, as small HEIC files in `avatars/` beside `profiles.json`.
/// Every avatar is drawn at once (the switcher, the For chip, the shared-night
/// marks) and before any profile's store opens, so a photo lives with the
/// registry rather than in a store.
nonisolated enum ProfilePhotoStore {
    static let folderName = "avatars"

    static func folder(in container: URL = ProfileRegistry.containerURL) -> URL {
        container.appendingPathComponent(folderName, isDirectory: true)
    }

    static func url(named name: String, in container: URL = ProfileRegistry.containerURL) -> URL {
        folder(in: container).appendingPathComponent(name)
    }

    static func data(named name: String, in container: URL = ProfileRegistry.containerURL) -> Data? {
        guard isFileName(name) else { return nil }
        return try? Data(contentsOf: url(named: name, in: container))
    }

    /// Writes an encoded photo under a fresh name and returns the name.
    static func write(
        _ data: Data, fileExtension: String, in container: URL = ProfileRegistry.containerURL,
    ) throws -> String {
        let name = "\(UUID().uuidString.lowercased()).\(fileExtension)"
        try write(data, named: name, in: container)
        return name
    }

    /// Writes a photo under the name a backup recorded, so the restored
    /// registry's avatars find their files.
    static func write(_ data: Data, named name: String, in container: URL = ProfileRegistry.containerURL) throws {
        guard isFileName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: folder(in: container), withIntermediateDirectories: true)
        try data.write(to: url(named: name, in: container), options: .atomic)
    }

    /// Removes every photo no profile names: the one a profile replaced, a
    /// deleted profile's, and one picked in an editor that was cancelled.
    static func sweep(keeping profiles: [PiruProfile], in container: URL = ProfileRegistry.containerURL) {
        let kept = Set(profiles.compactMap(\.avatar.photo))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder(in: container).path)) ?? []
        for file in files where !kept.contains(file) {
            try? FileManager.default.removeItem(at: url(named: file, in: container))
        }
    }

    /// A bare file name: a name read from a backup can't reach outside the folder.
    private static func isFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }
}
