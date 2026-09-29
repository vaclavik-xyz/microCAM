import CoreGraphics

/// Preview-only digital zoom. Photos and videos are never zoomed.
public struct ZoomState: Equatable, Sendable {
    public static let maxScale: CGFloat = 8

    public private(set) var scale: CGFloat = 1
    /// Normalized image point shown in the view center (origin bottom-left).
    public private(set) var center = CGPoint(x: 0.5, y: 0.5)

    public init() {}

    public mutating func zoom(by factor: CGFloat, anchor: CGPoint) {
        let pinned = CGPoint(x: center.x + (anchor.x - 0.5) / scale,
                             y: center.y + (anchor.y - 0.5) / scale)
        scale = min(max(scale * factor, 1), Self.maxScale)
        center = CGPoint(x: pinned.x - (anchor.x - 0.5) / scale,
                         y: pinned.y - (anchor.y - 0.5) / scale)
        clampCenter()
    }

    /// `delta` is the drag distance as a fraction of the view size.
    public mutating func pan(byNormalized delta: CGPoint) {
        center = CGPoint(x: center.x - delta.x / scale, y: center.y - delta.y / scale)
        clampCenter()
    }

    public mutating func reset() {
        self = ZoomState()
    }

    /// For a layer whose transform is applied around its center anchor.
    public func layerTransform(viewSize: CGSize) -> CGAffineTransform {
        let dx = (center.x - 0.5) * viewSize.width
        let dy = (center.y - 0.5) * viewSize.height
        return CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -dx, y: -dy)
    }

    /// For Core Image drawing into a view-sized destination (origin bottom-left).
    public func absoluteTransform(viewSize: CGSize) -> CGAffineTransform {
        CGAffineTransform(translationX: viewSize.width / 2, y: viewSize.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x * viewSize.width, y: -center.y * viewSize.height)
    }

    private mutating func clampCenter() {
        let half = 0.5 / scale
        center = CGPoint(x: min(max(center.x, half), 1 - half),
                         y: min(max(center.y, half), 1 - half))
    }
}
