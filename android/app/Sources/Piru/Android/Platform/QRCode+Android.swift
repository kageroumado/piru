// QR codes for the pairing screen (Piru/Views/Profiles/Sharing/PairingView.swift), which iOS
// draws with Core Image's CIQRCodeGenerator. This is the same symbol from ISO/IEC 18004: byte
// mode, error correction level M (Core Image's "M", as PairingView asks), the smallest version
// that holds the text, and the mask with the lowest penalty. Needs only Foundation, so
// android/Compat/Tests/QRCodeTests decodes what it draws with Core Image's QR reader on macOS.

import Foundation

/// The modules of a QR code, dark or light, without the quiet zone around them.
nonisolated struct QRCodeMatrix: Equatable, Sendable {
    /// Modules per side: 21 for version 1, four more for each version after.
    let size: Int
    let version: Int
    let mask: Int
    private let modules: [Bool]

    /// Whether the module at column `x`, row `y` is dark.
    subscript(x: Int, y: Int) -> Bool {
        modules[y * size + x]
    }

    /// The code for `text` in byte mode at level M; `nil` past version 40's 2,331 bytes.
    /// `mask` overrides the lowest-penalty choice, for comparing with another encoder.
    init?(_ text: String, mask forcedMask: Int? = nil) {
        let bytes = Array(text.utf8)
        guard let version = (1 ... 40).first(where: { Self.fits(bytes.count, version: $0) }) else { return nil }
        var builder = Builder(version: version)
        builder.drawFunctionPatterns()
        builder.drawCodewords(Self.codewords(bytes, version: version))
        let penalties = (0 ..< 8).map { builder.masked($0).penalty }
        let mask = forcedMask ?? penalties.indices.min { penalties[$0] < penalties[$1] } ?? 0
        builder = builder.masked(mask)
        builder.drawFormatBits(mask: mask)
        size = builder.size
        self.version = version
        self.mask = mask
        modules = builder.modules
    }

    // MARK: - Capacity (level M)

    /// Error correction codewords in each block, by version.
    private static let eccPerBlock = [
        10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
        26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    ]
    /// Blocks the codewords are split into, by version.
    private static let blockCount = [
        1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
        17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49,
    ]

    /// Modules left for codewords once the function patterns are drawn.
    private static func rawDataModules(version: Int) -> Int {
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let alignments = version / 7 + 2
            result -= (25 * alignments - 10) * alignments - 55
            if version >= 7 { result -= 36 }
        }
        return result
    }

    private static func dataCodewords(version: Int) -> Int {
        rawDataModules(version: version) / 8 - eccPerBlock[version - 1] * blockCount[version - 1]
    }

    private static func countBits(version: Int) -> Int {
        version <= 9 ? 8 : 16
    }

    private static func fits(_ count: Int, version: Int) -> Bool {
        count < 1 << countBits(version: version) && 4 + countBits(version: version) + count * 8 <= dataCodewords(version: version) * 8
    }

    // MARK: - Codewords

    /// The data in byte mode, padded, split into blocks with Reed–Solomon error correction,
    /// and interleaved.
    private static func codewords(_ bytes: [UInt8], version: Int) -> [UInt8] {
        let capacity = dataCodewords(version: version)
        var bits: [Bool] = []
        func append(_ value: Int, _ count: Int) {
            for shift in stride(from: count - 1, through: 0, by: -1) {
                bits.append((value >> shift) & 1 == 1)
            }
        }
        append(0b0100, 4)
        append(bytes.count, countBits(version: version))
        for byte in bytes {
            append(Int(byte), 8)
        }
        append(0, min(4, capacity * 8 - bits.count))
        append(0, (8 - bits.count % 8) % 8)
        var data = stride(from: 0, to: bits.count, by: 8).map { start in
            bits[start ..< start + 8].reduce(UInt8(0)) { $0 << 1 | ($1 ? 1 : 0) }
        }
        var pad: UInt8 = 0xEC
        while data.count < capacity {
            data.append(pad)
            pad ^= 0xEC ^ 0x11
        }

        let blocks = blockCount[version - 1]
        let eccLength = eccPerBlock[version - 1]
        let rawCodewords = rawDataModules(version: version) / 8
        let shortBlocks = blocks - rawCodewords % blocks
        let shortLength = rawCodewords / blocks
        let divisor = ReedSolomon.divisor(degree: eccLength)
        var split: [[UInt8]] = []
        var offset = 0
        for index in 0 ..< blocks {
            let length = shortLength - eccLength + (index < shortBlocks ? 0 : 1)
            let chunk = Array(data[offset ..< offset + length])
            offset += length
            // A short block takes a placeholder byte so every block indexes alike; it is skipped
            // when interleaving.
            var block = chunk
            if index < shortBlocks { block.append(0) }
            block += ReedSolomon.remainder(chunk, divisor: divisor)
            split.append(block)
        }
        var result: [UInt8] = []
        for position in 0 ..< split[0].count {
            for (index, block) in split.enumerated() where position != shortLength - eccLength || index >= shortBlocks {
                result.append(block[position])
            }
        }
        return result
    }

    private enum ReedSolomon {
        /// Product in GF(2⁸) modulo x⁸ + x⁴ + x³ + x² + 1.
        static func multiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
            var z = 0
            for shift in stride(from: 7, through: 0, by: -1) {
                z = (z << 1) ^ ((z >> 7) * 0x11D)
                z ^= Int((y >> UInt8(shift)) & 1) * Int(x)
            }
            return UInt8(z & 0xFF)
        }

        /// The generator polynomial's coefficients, highest power first, its leading 1 left out.
        static func divisor(degree: Int) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: degree)
            result[degree - 1] = 1
            var root: UInt8 = 1
            for _ in 0 ..< degree {
                for index in result.indices {
                    result[index] = multiply(result[index], root)
                    if index + 1 < result.count { result[index] ^= result[index + 1] }
                }
                root = multiply(root, 0x02)
            }
            return result
        }

        static func remainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: divisor.count)
            for byte in data {
                let factor = byte ^ result.removeFirst()
                result.append(0)
                for index in result.indices {
                    result[index] ^= multiply(divisor[index], factor)
                }
            }
            return result
        }
    }

    // MARK: - Drawing

    private struct Builder {
        let version: Int
        let size: Int
        var modules: [Bool]
        var isFunction: [Bool]

        init(version: Int) {
            self.version = version
            size = version * 4 + 17
            modules = Array(repeating: false, count: size * size)
            isFunction = Array(repeating: false, count: size * size)
        }

        mutating func set(_ x: Int, _ y: Int, _ dark: Bool) {
            modules[y * size + x] = dark
            isFunction[y * size + x] = true
        }

        mutating func drawFunctionPatterns() {
            for index in 0 ..< size {
                set(6, index, index % 2 == 0)
                set(index, 6, index % 2 == 0)
            }
            drawFinder(3, 3)
            drawFinder(size - 4, 3)
            drawFinder(3, size - 4)
            let positions = alignmentPositions
            for (i, x) in positions.enumerated() {
                for (j, y) in positions.enumerated() {
                    let last = positions.count - 1
                    if (i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0) { continue }
                    for dy in -2 ... 2 {
                        for dx in -2 ... 2 {
                            set(x + dx, y + dy, max(abs(dx), abs(dy)) != 1)
                        }
                    }
                }
            }
            // Reserves the format areas; the real bits go in once the mask is chosen.
            drawFormatBits(mask: 0)
            drawVersion()
        }

        private mutating func drawFinder(_ x: Int, _ y: Int) {
            for dy in -4 ... 4 {
                for dx in -4 ... 4 {
                    let distance = max(abs(dx), abs(dy))
                    let (px, py) = (x + dx, y + dy)
                    if (0 ..< size).contains(px), (0 ..< size).contains(py) {
                        set(px, py, distance != 2 && distance != 4)
                    }
                }
            }
        }

        private var alignmentPositions: [Int] {
            guard version > 1 else { return [] }
            let count = version / 7 + 2
            let step = (version * 8 + count * 3 + 5) / (count * 4 - 4) * 2
            var result = [6]
            for index in 0 ..< count - 1 {
                result.insert(size - 7 - index * step, at: 1)
            }
            return result
        }

        /// The 15 format bits (level M, then the mask, BCH-coded and XORed with 0x5412), twice.
        mutating func drawFormatBits(mask: Int) {
            let data = 0b00 << 3 | mask
            var remainder = data
            for _ in 0 ..< 10 {
                remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
            }
            let bits = (data << 10 | remainder) ^ 0x5412
            func bit(_ index: Int) -> Bool {
                (bits >> index) & 1 == 1
            }
            for index in 0 ... 5 {
                set(8, index, bit(index))
            }
            set(8, 7, bit(6))
            set(8, 8, bit(7))
            set(7, 8, bit(8))
            for index in 9 ..< 15 {
                set(14 - index, 8, bit(index))
            }
            for index in 0 ..< 8 {
                set(size - 1 - index, 8, bit(index))
            }
            for index in 8 ..< 15 {
                set(8, size - 15 + index, bit(index))
            }
            set(8, size - 8, true)
        }

        /// The 18 version bits, from version 7 on, twice.
        private mutating func drawVersion() {
            guard version >= 7 else { return }
            var remainder = version
            for _ in 0 ..< 12 {
                remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
            }
            let bits = version << 12 | remainder
            for index in 0 ..< 18 {
                let dark = (bits >> index) & 1 == 1
                let a = size - 11 + index % 3, b = index / 3
                set(a, b, dark)
                set(b, a, dark)
            }
        }

        /// The codewords' bits in the zigzag of two-module columns, right to left.
        mutating func drawCodewords(_ data: [UInt8]) {
            var bit = 0
            var right = size - 1
            while right >= 1 {
                if right == 6 { right = 5 }
                for vertical in 0 ..< size {
                    for offset in 0 ..< 2 {
                        let x = right - offset
                        let upward = (right + 1) & 2 == 0
                        let y = upward ? size - 1 - vertical : vertical
                        if !isFunction[y * size + x], bit < data.count * 8 {
                            modules[y * size + x] = (data[bit >> 3] >> UInt8(7 - (bit & 7))) & 1 == 1
                            bit += 1
                        }
                    }
                }
                right -= 2
            }
        }

        func masked(_ mask: Int) -> Builder {
            var copy = self
            for y in 0 ..< size {
                for x in 0 ..< size where !isFunction[y * size + x] {
                    let flip = switch mask {
                    case 0: (x + y) % 2 == 0
                    case 1: y % 2 == 0
                    case 2: x % 3 == 0
                    case 3: (x + y) % 3 == 0
                    case 4: (x / 3 + y / 2) % 2 == 0
                    case 5: x * y % 2 + x * y % 3 == 0
                    case 6: (x * y % 2 + x * y % 3) % 2 == 0
                    default: ((x + y) % 2 + x * y % 3) % 2 == 0
                    }
                    if flip { copy.modules[y * size + x].toggle() }
                }
            }
            return copy
        }

        /// ISO/IEC 18004's four penalty rules; the mask with the lowest score scans best.
        var penalty: Int {
            var score = 0
            func line(_ at: (Int) -> Bool) {
                var run = 1
                for index in 1 ..< size {
                    if at(index) == at(index - 1) {
                        run += 1
                    } else {
                        if run >= 5 { score += run - 2 }
                        run = 1
                    }
                }
                if run >= 5 { score += run - 2 }
                // A finder-like 1:1:3:1:1 run with four light modules on either side.
                let finder = [true, false, true, true, true, false, true]
                for start in 0 ..< size - 6 where (0 ..< 7).allSatisfy({ at(start + $0) == finder[$0] }) {
                    let before = (start - 4 ..< start).allSatisfy { $0 < 0 || !at($0) }
                    let after = (start + 7 ..< start + 11).allSatisfy { $0 >= size || !at($0) }
                    if before || after { score += 40 }
                }
            }
            for y in 0 ..< size {
                line { self.modules[y * size + $0] }
            }
            for x in 0 ..< size {
                line { self.modules[$0 * size + x] }
            }
            for y in 0 ..< size - 1 {
                for x in 0 ..< size - 1 {
                    let dark = modules[y * size + x]
                    if dark == modules[y * size + x + 1], dark == modules[(y + 1) * size + x],
                       dark == modules[(y + 1) * size + x + 1] { score += 3 }
                }
            }
            let darkCount = modules.count(where: { $0 })
            let total = size * size
            let deviation = abs(darkCount * 20 - total * 10)
            score += ((deviation + total - 1) / total - 1) * 10
            return score
        }
    }
}
