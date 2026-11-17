import Compression
import Foundation
import Testing

/// A share's body crosses between an iPhone, which compresses it with Apple's Compression, and
/// an Android phone, which uses `RawDeflate` over zlib. Each side must read what the other writes,
/// and refuse what ShareEnvelope refuses.
@Suite("RawDeflate")
struct ShareCompressionTests {
    /// A share-sized JSON body: repetitive keys, as a session's doses are.
    static let body: Data = {
        let dose = #"{"amount":20,"id":"5C3F6A9E-1D2B-4C8A-9F0E-7B6D5A4C3B2A","substance":"2C-B","timestamp":"2026-11-14T22:10:00Z","unit":"mg"}"#
        return Data(("{\"doses\":[" + Array(repeating: dose, count: 200).joined(separator: ",") + "]}").utf8)
    }()

    static let limit = 8_000_000

    /// ShareEnvelope's iOS inflate, exactly: Apple's decoder into `limit + 1` bytes.
    static func appleInflate(_ data: Data, limit: Int = limit) -> Data? {
        var output = Data(count: limit + 1)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, limit + 1,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB,
                )
            }
        }
        guard written > 0, written <= limit else { return nil }
        output.count = written
        return output
    }

    /// ShareEnvelope's Android inflate: the same call, answered by RawDeflate.
    static func androidInflate(_ data: Data, limit: Int = limit) -> Data? {
        var output = Data(count: limit + 1)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in RawDeflate.inflate(source, into: destination) }
        }
        guard written > 0, written <= limit else { return nil }
        output.count = written
        return output
    }

    @Test
    func `An iPhone reads what Android compresses`() throws {
        let compressed = try RawDeflate.deflate(Self.body)
        #expect(compressed.count < Self.body.count / 4)
        #expect(Self.appleInflate(compressed) == Self.body)
        #expect(try (compressed as NSData).decompressed(using: .zlib) as Data == Self.body)
    }

    @Test
    func `Android reads what an iPhone compresses`() throws {
        let compressed = try (Self.body as NSData).compressed(using: .zlib) as Data
        #expect(Self.androidInflate(compressed) == Self.body)
    }

    @Test
    func `Neither side writes a zlib header`() throws {
        // A zlib stream starts 0x78; raw DEFLATE's first byte is a block header.
        let android = try RawDeflate.deflate(Self.body)
        let apple = try (Self.body as NSData).compressed(using: .zlib) as Data
        #expect(android.first != 0x78)
        #expect(apple.first != 0x78)
    }

    @Test
    func `A body that inflates past the limit is refused on both sides`() throws {
        let compressed = try RawDeflate.deflate(Self.body)
        let limit = Self.body.count - 1
        #expect(Self.appleInflate(compressed, limit: limit) == nil)
        #expect(Self.androidInflate(compressed, limit: limit) == nil)
        #expect(Self.androidInflate(compressed, limit: Self.body.count) == Self.body)
    }

    @Test
    func `Garbage, a cut-off stream and nothing inflate to nothing`() throws {
        let compressed = try RawDeflate.deflate(Self.body)
        #expect(Self.androidInflate(Data(repeating: 0xFF, count: 64)) == nil)
        #expect(Self.androidInflate(compressed.prefix(compressed.count / 2)) == nil)
        #expect(Self.androidInflate(Data()) == nil)
    }

    @Test
    func `An empty body inflates to nothing, which ShareEnvelope refuses`() throws {
        let compressed = try RawDeflate.deflate(Data())
        #expect(!compressed.isEmpty)
        var output = Data(count: 16)
        let written = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { RawDeflate.inflate($0, into: destination) }
        }
        #expect(written == 0)
    }
}
