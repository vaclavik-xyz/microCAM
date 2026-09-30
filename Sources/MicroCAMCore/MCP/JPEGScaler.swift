import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales a JPEG for an agent with ImageIO (no full-size decode).
public enum JPEGScaler {
    public static func scaled(_ data: Data, maxDimension: Int, quality: Double = 0.85) -> MCPImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return scaled(source, maxDimension: maxDimension, quality: quality)
    }

    public static func scaled(contentsOf url: URL, maxDimension: Int, quality: Double = 0.85) -> MCPImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return scaled(source, maxDimension: maxDimension, quality: quality)
    }

    private static func scaled(_ source: CGImageSource, maxDimension: Int, quality: Double) -> MCPImage? {
        // Never upscale: a small image keeps its size.
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let longest = max(props?[kCGImagePropertyPixelWidth] as? Int ?? 0, props?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: longest > 0 ? min(maxDimension, longest) : maxDimension]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return MCPImage(jpeg: out as Data, width: image.width, height: image.height)
    }
}
