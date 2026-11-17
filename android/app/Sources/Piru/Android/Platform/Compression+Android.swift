// The slice of Apple's Compression framework and NSData compression that ShareEnvelope calls,
// in Apple's names, over RawDeflate+Android.swift. Apple's COMPRESSION_ZLIB and NSData's
// `.zlib` both mean raw DEFLATE, which is what RawDeflate reads and writes.

import Foundation

nonisolated struct compression_algorithm: Equatable, Sendable {
    let rawValue: Int32
}

nonisolated let COMPRESSION_ZLIB = compression_algorithm(rawValue: 0x205)

/// Inflates raw DEFLATE from `src` into `dst`, with Apple's contract: the number of bytes
/// written, `dstSize` when the output fills the buffer before the stream ends, and 0 for an
/// empty, malformed or unfinished stream.
nonisolated func compression_decode_buffer(
    _ dst: UnsafeMutablePointer<UInt8>,
    _ dstSize: Int,
    _ src: UnsafePointer<UInt8>,
    _ srcSize: Int,
    _: UnsafeMutableRawPointer?,
    _ algorithm: compression_algorithm,
) -> Int {
    guard algorithm == COMPRESSION_ZLIB else { return 0 }
    return RawDeflate.inflate(
        UnsafeRawBufferPointer(start: src, count: srcSize),
        into: UnsafeMutableRawBufferPointer(start: dst, count: dstSize),
    )
}

nonisolated extension NSData {
    enum CompressionAlgorithm: Sendable {
        case zlib
    }

    /// Raw DEFLATE, as Apple's `.zlib` writes it.
    func compressed(using _: CompressionAlgorithm) throws -> NSData {
        try RawDeflate.deflate(self as Data) as NSData
    }
}
