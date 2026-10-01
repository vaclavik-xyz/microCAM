import AppKit
import MicroCAMCore

/// The drawing over the preview. Shapes live in image coordinates, so they
/// stay on the board when the preview is zoomed or moved, and are drawn by the
/// same code that draws them into photos.
///
/// Costs nothing while the board is empty: the view is hidden, and a timer
/// runs only while a pointer is fading. While drawing, drags draw instead of
/// moving the image; scrolling and pinching still zoom (the events go on to
/// the preview). With the text tool a click places a label, a click on a
/// label edits it and a drag moves it; Return or a click elsewhere finishes,
/// Esc cancels.
@MainActor
final class AnnotationOverlayView: NSView, NSTextFieldDelegate {
    private let board: AnnotationBoard
    /// The board changed through this view (the model refreshes its state).
    var onChange: () -> Void = {}
    /// A label was opened for editing: the palette shows its colour and size.
    var onPickStyle: (String, AnnotationTextSize) -> Void = { _, _ in }

    var isDrawing = false {
        didSet {
            guard isDrawing != oldValue else { return }
            if !isDrawing { commitText(); current = nil; pointer = nil }
            window?.invalidateCursorRects(for: self)
            updateVisibility()
        }
    }
    var tool: AnnotationShape.Kind = .arrow {
        didSet {
            guard tool != oldValue else { return }
            if tool != .text { commitText() }
            window?.invalidateCursorRects(for: self)
        }
    }
    var color = AppModel.drawColors[0] { didSet { if color != oldValue { placeEditor() } } }
    var textSize = AnnotationTextSize.medium { didSet { if textSize != oldValue { placeEditor() } } }
    var contentSize: CGSize? { didSet { if contentSize != oldValue { relayout() } } }
    var zoom = ZoomState() { didSet { if zoom != oldValue { relayout() } } }

    /// Arrow, circle or pen stroke being drawn; on the board from mouse-up.
    private var current: AnnotationShape?
    /// Pointer being drawn: on the board from its second point, updated on every move.
    private var pointer: AnnotationShape?
    private var textDrag: (shape: AnnotationShape, from: AnnotationPoint, start: AnnotationPoint, moved: Bool)?
    private var newTextPoint: AnnotationPoint?
    private var editor: NSTextField?
    private var editing: (id: String?, point: AnnotationPoint)?
    private var fadeTimer: Timer?

    init(board: AnnotationBoard) {
        self.board = board
        super.init(frame: .zero)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var geometry: PreviewGeometry { PreviewGeometry(viewSize: bounds.size, contentSize: contentSize, zoom: zoom) }

    /// Call after every change of the board.
    func boardChanged() {
        updateVisibility()
        needsDisplay = true
        updateFadeTimer()
    }

    private func relayout() {
        needsDisplay = true
        placeEditor()
    }

    override func layout() {
        super.layout()
        relayout()
    }

    private func updateVisibility() {
        isHidden = board.isEmpty && !isDrawing && current == nil && editor == nil
    }

    // MARK: Drawing

    override func hitTest(_ point: NSPoint) -> NSView? { isDrawing ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        guard isDrawing else { return }
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = geometry.imageRect
        guard rect.width > 0, rect.height > 0 else { return }
        var shapes = board.shapes
        if let id = editing?.id { shapes.removeAll { $0.id == id } }   // the editor shows it meanwhile
        if let current { shapes.append(current) }
        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        let now = Date()
        AnnotationRenderer.draw(shapes, in: ctx, size: rect.size) { [board] shape in
            CGFloat(board.pointerOpacity(id: shape.id ?? "", now: now))
        }
        ctx.restoreGState()
    }

    /// Redraws while pointers fade and drops them when they expire.
    private func updateFadeTimer() {
        guard board.hasPointers else {
            fadeTimer?.invalidate()
            fadeTimer = nil
            return
        }
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeTick() }
        }
    }

    private func fadeTick() {
        if board.prune() { onChange() }
        needsDisplay = true
        updateFadeTimer()
    }

    // MARK: Mouse

    private func imagePoint(_ event: NSEvent) -> AnnotationPoint {
        geometry.imagePoint(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard isDrawing else { return }
        let location = convert(event.locationInWindow, from: nil)
        let p = geometry.imagePoint(location)
        if tool == .text {
            // A click elsewhere finishes the label being typed.
            if editor != nil { commitText(); return }
            if let hit = ownText(at: location), let frame = textFrame(of: hit) {
                textDrag = (hit, geometry.imagePoint(CGPoint(x: frame.minX, y: frame.maxY)), p, false)
            } else if geometry.containsImage(location) {
                newTextPoint = p
            }
            return
        }
        guard geometry.containsImage(location) else { return }
        let shape = AnnotationShape(kind: tool, points: [p], color: color, width: 0.006,
                                    id: UUID().uuidString, author: AnnotationBoard.bench)
        switch tool {
        case .pointer: pointer = shape
        case .pen: current = shape
        default: current = AnnotationShape(kind: tool, points: [p, p], color: color, width: 0.006,
                                           id: shape.id, author: shape.author)
        }
        updateVisibility()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event)
        if var drag = textDrag {
            let dx = p.x - drag.start.x, dy = p.y - drag.start.y
            let rect = geometry.imageRect
            guard drag.moved || hypot(dx * rect.width, dy * rect.height) >= 4 else { return }
            drag.moved = true
            textDrag = drag
            var moved = drag.shape
            moved.points = [AnnotationPoint(x: min(max(drag.from.x + dx, 0), 1), y: min(max(drag.from.y + dy, 0), 1))]
            if board.add(moved) != nil { onChange() }
            return
        }
        if var shape = pointer {
            shape.points.append(p)
            if shape.points.count > AnnotationShape.maxPointerPoints { shape.points.removeFirst() }
            pointer = shape
            if board.add(shape) != nil { onChange() }
            return
        }
        guard var shape = current else { return }
        if shape.kind == .pen {
            // Skip points that add nothing; long strokes stay within the point limit.
            if let last = shape.points.last, abs(last.x - p.x) + abs(last.y - p.y) < 0.001 { return }
            shape.points.append(p)
        } else {
            shape.points[1] = p
        }
        current = shape
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let drag = textDrag {
            textDrag = nil
            if !drag.moved { beginText(at: drag.shape.points[0], editing: drag.shape) }
            return
        }
        if let point = newTextPoint {
            newTextPoint = nil
            beginText(at: point)
            return
        }
        pointer = nil   // it fades on its own
        guard let shape = current, let a = shape.points.first, let b = shape.points.last else { return }
        current = nil
        let long = shape.kind == .pen ? shape.points.count > 1 : abs(a.x - b.x) + abs(a.y - b.y) > 0.005
        if long { board.add(shape) }
        onChange()
        needsDisplay = true
        updateVisibility()
    }

    // MARK: Text

    /// A text shape's box in view coordinates.
    private func textFrame(of shape: AnnotationShape) -> CGRect? {
        let r = geometry.imageRect
        guard let f = AnnotationTextLayout.frame(of: shape, in: r.size) else { return nil }
        return CGRect(x: r.minX + f.minX, y: r.maxY - f.maxY, width: f.width, height: f.height)
    }

    /// The Mac's own label under a view point (others' labels are not changed here).
    private func ownText(at location: CGPoint) -> AnnotationShape? {
        board.shapes.reversed().first { shape in
            shape.kind == .text && shape.author == AnnotationBoard.bench
                && (textFrame(of: shape)?.insetBy(dx: -6, dy: -6).contains(location) ?? false)
        }
    }

    /// Opens the label editor at `point`; with `shape`, edits that label.
    func beginText(at point: AnnotationPoint, editing shape: AnnotationShape? = nil, text: String? = nil) {
        commitText()
        if let shape {
            color = shape.color
            textSize = AnnotationTextSize.allCases.min {
                abs($0.fontSize - (shape.fontSize ?? 0)) < abs($1.fontSize - (shape.fontSize ?? 0))
            } ?? .medium
            onPickStyle(color, textSize)
        }
        let field = NSTextField(string: text ?? shape?.text ?? "")
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.focusRingType = .none
        field.placeholderString = String(localized: "Type a label")
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        field.delegate = self
        editing = (shape?.id, point)
        editor = field
        addSubview(field)
        placeEditor()
        window?.makeFirstResponder(field)
        needsDisplay = true
        updateVisibility()
    }

    /// Keeps the editor where the label will be drawn, in its colour and size.
    private func placeEditor() {
        guard let field = editor, let editing else { return }
        let r = geometry.imageRect
        let pixels = CGFloat(textSize.fontSize) * r.height
        let fontSize = max(pixels, 13)   // readable while typing, even far out
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = NSColor(hex: color)
        let sample = field.stringValue.isEmpty ? (field.placeholderString ?? "") : field.stringValue
        let width = min(AnnotationTextLayout.width(of: sample, fontPixels: fontSize) + fontSize + 12, bounds.width)
        let height = ceil(fontSize * 1.25) + 4
        let origin = AnnotationTextLayout.origin(editing.point, textWidth: width, fontPixels: pixels, in: r.size)
        field.frame = CGRect(x: r.minX + origin.x - 4, y: r.maxY - origin.y - height, width: width, height: height)
    }

    func controlTextDidChange(_ obj: Notification) { placeEditor() }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commitText(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelText(); return true
        default: return false
        }
    }

    /// Saves the label being typed; an empty one removes the label it edited.
    func commitText() {
        guard let (text, editing) = closeEditor() else { return }
        if AnnotationShape.cleanText(text) == nil {
            if let id = editing.id { board.delete(id: id, by: AnnotationBoard.bench) }
        } else {
            board.add(AnnotationShape(kind: .text, points: [editing.point], color: color, width: 0.006,
                                      id: editing.id, author: AnnotationBoard.bench, text: text,
                                      fontSize: textSize.fontSize))
        }
        onChange()
    }

    /// Closes the editor and leaves the label as it was.
    func cancelText() {
        guard closeEditor() != nil else { return }
        onChange()
    }

    private func closeEditor() -> (String, (id: String?, point: AnnotationPoint))? {
        guard let field = editor, let editing else { return nil }
        editor = nil
        self.editing = nil
        field.delegate = nil
        let text = field.stringValue
        if field.currentEditor() != nil { window?.makeFirstResponder(nil) }
        field.removeFromSuperview()
        needsDisplay = true
        updateVisibility()
        return (text, editing)
    }
}

extension NSColor {
    /// `#rrggbb`, as annotations store their colours.
    convenience init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0xFF3B30
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
