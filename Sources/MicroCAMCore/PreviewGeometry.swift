import CoreGraphics

/// Where the picture is in the preview view: fitted to the view (letterboxed)
/// and then zoomed like the preview (`ZoomState`). Maps between normalized
/// image points (0…1, origin top-left, as annotations store them) and view
/// points (origin bottom-left, as AppKit uses them).
public struct PreviewGeometry: Equatable, Sendable {
    public var viewSize: CGSize
    public var contentSize: CGSize?
    public var zoom: ZoomState

    public init(viewSize: CGSize, contentSize: CGSize?, zoom: ZoomState) {
        self.viewSize = viewSize; self.contentSize = contentSize; self.zoom = zoom
    }

    /// The picture in view coordinates after the fit and the zoom.
    public var imageRect: CGRect {
        var fitted = CGRect(origin: .zero, size: viewSize)
        if let size = contentSize, size.width > 0, size.height > 0, viewSize.width > 0, viewSize.height > 0 {
            let scale = min(viewSize.width / size.width, viewSize.height / size.height)
            let w = size.width * scale, h = size.height * scale
            fitted = CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
        }
        return fitted.applying(zoom.absoluteTransform(viewSize: viewSize))
    }

    public func viewPoint(_ p: AnnotationPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: r.minX + p.x * r.width, y: r.maxY - p.y * r.height)
    }

    /// The image point under a view point, clamped to the picture.
    public func imagePoint(_ v: CGPoint) -> AnnotationPoint {
        let r = imageRect
        guard r.width > 0, r.height > 0 else { return AnnotationPoint(x: 0, y: 0) }
        return AnnotationPoint(x: min(max((v.x - r.minX) / r.width, 0), 1),
                               y: min(max((r.maxY - v.y) / r.height, 0), 1))
    }

    public func containsImage(_ v: CGPoint) -> Bool { imageRect.contains(v) }
}
