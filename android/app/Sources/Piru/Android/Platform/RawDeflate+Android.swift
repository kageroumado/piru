// Raw DEFLATE (RFC 1951: no zlib header, no checksum) over the system zlib, which is what
// Apple's COMPRESSION_ZLIB and NSData's `.zlib` read and write. A share's body is compressed
// this way on both platforms (Compression+Android.swift wraps it in Apple's names), so a share
// sealed on either phone opens on the other. Needs only Foundation and zlib, so
// android/Compat/Tests/ShareCompressionTests checks it against Apple's Compression on macOS.

import Foundation
import zlib

nonisolated enum RawDeflate {
    enum Failure: Error {
        case zlib(Int32)
    }

    /// `input` as raw DEFLATE at zlib's default level.
    static func deflate(_ input: Data) throws -> Data {
        var stream = z_stream()
        let initialized = deflateInit2_(
            &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size),
        )
        guard initialized == Z_OK else { throw Failure.zlib(initialized) }
        defer { deflateEnd(&stream) }
        let capacity = Int(deflateBound(&stream, uLong(input.count)))
        var output = Data(count: capacity)
        let status = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = uInt(capacity)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw Failure.zlib(status) }
        output.count = Int(stream.total_out)
        return output
    }

    /// Inflates the raw DEFLATE in `source` into `destination`: the number of bytes written,
    /// `destination.count` when the output fills it before the stream ends, and 0 for an empty,
    /// malformed or unfinished stream. Apple's `compression_decode_buffer` answers the same.
    static func inflate(_ source: UnsafeRawBufferPointer, into destination: UnsafeMutableRawBufferPointer) -> Int {
        guard let input = source.baseAddress, let output = destination.baseAddress,
              source.count > 0, destination.count > 0,
              source.count <= Int(UInt32.max), destination.count <= Int(UInt32.max)
        else { return 0 }
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return 0 }
        defer { inflateEnd(&stream) }
        stream.next_in = UnsafeMutablePointer(mutating: input.assumingMemoryBound(to: UInt8.self))
        stream.avail_in = uInt(source.count)
        stream.next_out = output.assumingMemoryBound(to: UInt8.self)
        stream.avail_out = uInt(destination.count)
        switch zlib.inflate(&stream, Z_FINISH) {
        case Z_STREAM_END:
            return Int(stream.total_out)
        case Z_BUF_ERROR where stream.avail_out == 0:
            return destination.count
        default:
            return 0
        }
    }
}
