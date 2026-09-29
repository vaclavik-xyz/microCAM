import AVFoundation
import AppKit
import MicroCAMCore

extension GridColor {
    var nsColor: NSColor {
        switch self {
        case .white: .white
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .red: .systemRed
        }
    }
}

/// Preview-only guide lines over the video area. Never recorded; ignores clicks.
final class GridOverlayView: NSView {
    var gridType: GridType = .thirds { didSet { needsDisplay = true } }
    var gridColor: GridColor = .white { didSet { needsDisplay = true } }
    var contentSize: CGSize? { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect: CGRect
        if let size = contentSize, size.width > 0, size.height > 0 {
            rect = AVMakeRect(aspectRatio: size, insideRect: bounds)
        } else {
            rect = bounds
        }
        let divisions = gridType == .thirds ? 3 : 8
        let path = NSBezierPath()
        for i in 1..<divisions {
            let fx = rect.minX + rect.width * CGFloat(i) / CGFloat(divisions)
            let fy = rect.minY + rect.height * CGFloat(i) / CGFloat(divisions)
            path.move(to: CGPoint(x: fx, y: rect.minY)); path.line(to: CGPoint(x: fx, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: fy)); path.line(to: CGPoint(x: rect.maxX, y: fy))
        }
        path.lineWidth = 1
        gridColor.nsColor.withAlphaComponent(0.6).setStroke()
        path.stroke()
    }
}
