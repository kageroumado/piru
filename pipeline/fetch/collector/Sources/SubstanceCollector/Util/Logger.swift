import Foundation

/// Tiny stderr logger. We send all human-facing diagnostics to stderr so
/// stdout stays available for piping if a future subcommand wants to emit
/// JSON straight to the shell.
enum Log {
    static func info(_ msg: String) {
        FileHandle.standardError.write(Data("\(msg)\n".utf8))
    }

    static func warn(_ msg: String) {
        FileHandle.standardError.write(Data("[warn] \(msg)\n".utf8))
    }

    static func error(_ msg: String) {
        FileHandle.standardError.write(Data("[error] \(msg)\n".utf8))
    }

    static func step(_ msg: String) {
        FileHandle.standardError.write(Data("\n=== \(msg) ===\n".utf8))
    }
}
