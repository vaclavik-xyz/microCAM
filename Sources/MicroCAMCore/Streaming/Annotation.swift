import CoreGraphics
import Foundation

public struct AnnotationPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// One shape drawn in the browser or on the Mac. Points are normalized to
/// the image (0…1) with the origin top-left; `width` is a fraction of the
/// image width. A text shape has one point, its top-left corner, and a
/// `fontSize` as a fraction of the image height. A pointer is a pen stroke
/// that fades on its own and is never rendered into files.
///
/// `id` and `author` belong to the shared board (`AnnotationBoard`); they are
/// optional so the photo endpoint keeps accepting the older JSON.
public struct AnnotationShape: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case arrow, ellipse, pen, text, pointer }
    public var kind: Kind
    public var points: [AnnotationPoint]
    public var color: String
    public var width: Double
    public var id: String?
    public var author: String?
    public var text: String?
    public var fontSize: Double?

    public static let maxTextLength = 200
    public static let fontSizeRange: ClosedRange<Double> = 0.015...0.12
    public static let maxPointerPoints = 200

    public init(kind: Kind, points: [AnnotationPoint], color: String, width: Double, id: String? = nil,
                author: String? = nil, text: String? = nil, fontSize: Double? = nil) {
        self.kind = kind; self.points = points; self.color = color; self.width = width
        self.id = id; self.author = author; self.text = text; self.fontSize = fontSize
    }

    /// One line of at most 200 characters: line breaks and tabs become spaces,
    /// other control and format characters (except the emoji joiner) go, and
    /// the ends are trimmed. Nil when nothing is left.
    public static func cleanText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var out = ""
        for character in raw {
            if character == "\n" || character == "\r\n" || character == "\r" || character == "\t" {
                out.append(" ")
                continue
            }
            let scalars = character.unicodeScalars.filter { scalar in
                scalar == "\u{200D}" || !(scalar.properties.generalCategory == .control
                                           || scalar.properties.generalCategory == .format)
            }
            out.unicodeScalars.append(contentsOf: scalars)
        }
        let trimmed = String(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Board ids and authors: 1–64 characters of `A–Z a–z 0–9 _ -`, else nil.
    public static func cleanID(_ raw: String?) -> String? {
        guard let raw, raw.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return nil }
        return raw
    }

    /// The shape made safe to draw, or nil when it has to be dropped (too few
    /// points, empty text, more points than `pointBudget`).
    public func sanitized(pointBudget: Int) -> AnnotationShape? {
        var shape = self
        var pts = points.map { AnnotationPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        switch kind {
        case .text:
            guard let first = pts.first, let text = Self.cleanText(text) else { return nil }
            pts = [first]
            shape.text = text
            let size = fontSize ?? AnnotationTextSize.medium.fontSize
            shape.fontSize = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        case .arrow, .ellipse:
            if let first = pts.first, let last = pts.last { pts = [first, last] }
            shape.text = nil; shape.fontSize = nil
        case .pointer:
            pts = Array(pts.suffix(Self.maxPointerPoints))
            shape.text = nil; shape.fontSize = nil
        case .pen:
            shape.text = nil; shape.fontSize = nil
        }
        guard pts.count >= (kind == .text ? 1 : 2), pts.count <= pointBudget else { return nil }
        shape.points = pts
        shape.width = min(max(width, 0.001), 0.05)
        if color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) == nil {
            shape.color = AnnotationRequest.defaultColor
        }
        shape.id = Self.cleanID(id)
        shape.author = Self.cleanID(author)
        return shape
    }
}

/// The three text sizes offered by the web page and the Mac palette, as a
/// fraction of the image height.
public enum AnnotationTextSize: String, CaseIterable, Sendable {
    case small, medium, large
    public var fontSize: Double {
        switch self {
        case .small: 0.03
        case .medium: 0.045
        case .large: 0.07
        }
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
        for shape in shapes where out.count < Self.maxShapes {
            guard let clean = shape.sanitized(pointBudget: budget) else { continue }
            budget -= clean.points.count
            out.append(clean)
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
            case .text, .pointer:
                continue
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
