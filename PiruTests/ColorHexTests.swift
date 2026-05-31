import SwiftUI
import Testing
@testable import Piru

@Suite("Color from Hex")
struct ColorHexTests {
    /// Helper to extract RGB components from a Color
    private func rgb(from color: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = color.resolve(in: .init())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }

    // MARK: - Valid hex parsing

    @Test
    func `Parses red hex correctly`() {
        let color = Color(hex: "#FF0000")
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test
    func `Parses green hex correctly`() {
        let color = Color(hex: "#00FF00")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g > 0.99)
        #expect(b < 0.01)
    }

    @Test
    func `Parses blue hex correctly`() {
        let color = Color(hex: "#0000FF")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b > 0.99)
    }

    @Test
    func `Parses white hex correctly`() {
        let color = Color(hex: "#FFFFFF")
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g > 0.99)
        #expect(b > 0.99)
    }

    @Test
    func `Parses black hex correctly`() {
        let color = Color(hex: "#000000")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    // MARK: - Prefix handling

    @Test
    func `Parses hex without # prefix`() {
        let color = Color(hex: "FF0000")
        let (r, _, _) = rgb(from: color)
        #expect(r > 0.99)
    }

    @Test
    func `Parses hex with # prefix`() {
        let color = Color(hex: "#FF0000")
        let (r, _, _) = rgb(from: color)
        #expect(r > 0.99)
    }

    // MARK: - Case sensitivity

    @Test
    func `Case insensitive parsing`() {
        let lower = Color(hex: "ff0000")
        let upper = Color(hex: "FF0000")
        let lowerRGB = rgb(from: lower)
        let upperRGB = rgb(from: upper)
        #expect(abs(lowerRGB.r - upperRGB.r) < 0.01)
        #expect(abs(lowerRGB.g - upperRGB.g) < 0.01)
        #expect(abs(lowerRGB.b - upperRGB.b) < 0.01)
    }

    // MARK: - Invalid input

    @Test
    func `3-char shorthand expands correctly`() {
        let white = Color(hex: "FFF")
        let (wr, wg, wb) = rgb(from: white)
        #expect(wr > 0.99)
        #expect(wg > 0.99)
        #expect(wb > 0.99)

        let red = Color(hex: "F00")
        let (rr, rg, rb) = rgb(from: red)
        #expect(rr > 0.99)
        #expect(rg < 0.01)
        #expect(rb < 0.01)
    }

    @Test
    func `Invalid length defaults to black`() {
        let color = Color(hex: "GG")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test
    func `Empty string defaults to black`() {
        let color = Color(hex: "")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }
}
