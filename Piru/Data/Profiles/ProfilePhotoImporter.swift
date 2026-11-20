import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// A picked photo ready to crop: upright, at most ``ProfilePhotoImporter/workingSide``
/// pixels on its long side, with the largest face Vision found in it.
nonisolated struct ProfilePhotoSource: Identifiable, @unchecked Sendable {
    let id = UUID()
    let image: CGImage
    /// The face, in pixels with a top-left origin.
    let face: CGRect?

    var size: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

/// Turns a picked photo into an avatar file: a thumbnail of the original
/// (never a full decode), a square crop, and a re-encode that keeps only
/// the pixels. The original's EXIF and location never reach the file.
nonisolated enum ProfilePhotoImporter {
    /// The long side the crop screen works at.
    static let workingSide = 1024
    /// The saved avatar's side: 3× the largest circle it fills (the 72 pt
    /// editor preview) with room to spare.
    static let savedSide = 256

    @concurrent
    static func prepare(_ data: Data) async -> ProfilePhotoSource? {
        guard let image = thumbnail(of: data, maxSide: workingSide) else { return nil }
        return await ProfilePhotoSource(image: image, face: largestFace(in: image))
    }

    /// `data` decoded upright at no more than `maxSide` pixels on its long
    /// side, so an outsized file costs no more memory than a small one.
    static func thumbnail(of data: Data, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The largest face, or `nil` when there is none or Vision fails.
    private static func largestFace(in image: CGImage) async -> CGRect? {
        guard let faces = try? await DetectFaceRectanglesRequest().perform(on: image) else { return nil }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        return faces
            .map { face -> CGRect in
                // Vision's rect is normalized with a bottom-left origin.
                let box = face.boundingBox.cgRect
                return CGRect(
                    x: box.minX * width,
                    y: (1 - box.maxY) * height,
                    width: box.width * width,
                    height: box.height * height,
                )
            }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// `crop` (pixels, top-left origin) of `source`, scaled to
    /// ``savedSide`` and encoded as HEIC, or JPEG where HEIC can't be written.
    @concurrent
    static func encode(_ source: ProfilePhotoSource, crop: CGRect) async -> (data: Data, fileExtension: String)? {
        let bounds = CGRect(origin: .zero, size: source.size)
        guard let cropped = source.image.cropping(to: crop.integral.intersection(bounds)) else { return nil }
        let side = savedSide
        let space = cropped.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let scaled = context.makeImage() else { return nil }
        for (type, fileExtension) in [(UTType.heic, "heic"), (UTType.jpeg, "jpg")] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            if CGImageDestinationFinalize(destination) { return (data as Data, fileExtension) }
        }
        return nil
    }
}
