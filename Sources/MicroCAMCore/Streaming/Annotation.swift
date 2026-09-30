import CoreGraphics
import Foundation

public struct AnnotationPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// One shape drawn in the browser. Points are normalized to the image
/// (0…1) with the origin top-left; `width` is a fraction of the image width.
public struct AnnotationShape: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case arrow, ellipse, pen }
    public var kind: Kind
    public var points: [AnnotationPoint]
    public var color: String
    public var width: Double

    public init(kind: Kind, points: [AnnotationPoint], color: String, width: Double) {
        self.kind = kind; self.points = points; self.color = color; self.width = width
    }
}

public struct AnnotationRequest: Codable, Sendable {
    public static let maxShapes = 200
    public static let maxPoints = 5_000
    public static let defaultColor = "#ff3b30"

    public var source: String
    public var shapes: [AnnotationShape]

    public init(source: String, shapes: [AnnotationShape]) { self.source = source; self.shapes = shapes }

    public func sanitized() -> AnnotationRequest {
        var budget = Self.maxPoints
        var out: [AnnotationShape] = []
        for var shape in shapes where out.count < Self.maxShapes {
            var pts = shape.points.map { AnnotationPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
            if shape.kind != .pen, let first = pts.first, let last = pts.last { pts = [first, last] }
            guard pts.count >= 2, pts.count <= budget else { continue }
            budget -= pts.count
            shape.points = pts
            shape.width = min(max(shape.width, 0.001), 0.05)
            if shape.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) == nil {
                shape.color = Self.defaultColor
            }
            out.append(shape)
        }
        return AnnotationRequest(source: source, shapes: out)
    }
}

public enum AnnotationRenderer {
    public static func render(_ shapes: [AnnotationShape], onto image: CGImage) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let point = { (p: AnnotationPoint) in CGPoint(x: p.x * w, y: (1 - p.y) * h) }   // flip to bottom-left
        for shape in shapes {
            ctx.setStrokeColor(color(shape.color))
            ctx.setLineWidth(shape.width * w)
            let pts = shape.points.map(point)
            guard pts.count >= 2 else { continue }
            switch shape.kind {
            case .pen:
                ctx.addLines(between: pts)
                ctx.strokePath()
            case .ellipse:
                ctx.strokeEllipse(in: CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y),
                                             width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y)))
            case .arrow:
                let (a, b) = (pts[0], pts[1])
                ctx.move(to: a); ctx.addLine(to: b)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let head = max(shape.width * w * 4, 12)
                for side in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                    ctx.move(to: b)
                    ctx.addLine(to: CGPoint(x: b.x + head * cos(angle + side), y: b.y + head * sin(angle + side)))
                }
                ctx.strokePath()
            }
        }
        return ctx.makeImage()
    }

    private static func color(_ hex: String) -> CGColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0xFF3B30
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
