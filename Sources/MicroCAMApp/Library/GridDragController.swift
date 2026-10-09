import AppKit
import MicroCAMCore

/// Drags in the side-panel grid, without the keyboard. From an unselected
/// tile the drag selects the range up to the tile under the pointer, and
/// scrolls when the pointer reaches the top or bottom edge of the panel. From
/// a selected tile it carries all the selected files into another app (an
/// AppKit dragging session: SwiftUI's `onDrag` drags only one item on macOS 14).
///
/// The pointer is read from the window, not from the gesture, so a scroll
/// with the pointer held still also extends the selection.
@MainActor
final class GridDragController: NSObject, NSDraggingSource {
    /// The grid's own view: its bounds are the "grid" coordinate space the
    /// tiles report their frames in.
    weak var gridView: NSView?
    /// Tile frames in the grid, from the tiles on screen (the grid is lazy).
    var frames: [URL: CGRect] = [:]

    private enum Mode { case idle, selecting(start: URL), draggingOut }
    private var mode = Mode.idle
    private var autoscroll: Timer?
    private let library: LibraryModel

    init(library: LibraryModel) { self.library = library }

    /// Every change of a tile's drag gesture.
    func dragChanged(from url: URL) {
        switch mode {
        case .idle:
            if library.grid.dragSelects(from: url) {
                mode = .selecting(start: url)
                startAutoscroll()
                extendSelection()
            } else {
                dragOut()
            }
        case .selecting:
            extendSelection()
        case .draggingOut:
            break
        }
    }

    func dragEnded() {
        // A drag out ends in `draggingSession(_:endedAt:operation:)`; AppKit
        // tracks the mouse then and the gesture may never end.
        if case .selecting = mode { finish() }
    }

    private func finish() {
        autoscroll?.invalidate()
        autoscroll = nil
        mode = .idle
    }

    // MARK: Selecting

    private func extendSelection() {
        guard case .selecting(let start) = mode, let point = pointerInGrid(),
              let current = GridHitTest.item(at: point, frames: frames) else { return }
        library.grid.drag(from: start, to: current, in: library.files)
    }

    /// The pointer in the grid's coordinates, y downwards like SwiftUI's.
    private func pointerInGrid() -> CGPoint? {
        guard let view = gridView, let window = view.window else { return nil }
        let p = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return CGPoint(x: p.x, y: view.isFlipped ? p.y : view.bounds.height - p.y)
    }

    private func startAutoscroll() {
        autoscroll?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollIfAtEdge() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoscroll = timer
    }

    /// Faster the further the pointer is past the edge zone, up to 24 pt a frame.
    private func scrollIfAtEdge() {
        guard let scrollView = gridView?.enclosingScrollView, let window = scrollView.window,
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let pointer = clip.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let visible = clip.bounds
        let fromTop = clip.isFlipped ? pointer.y - visible.minY : visible.maxY - pointer.y
        let fromBottom = visible.height - fromTop
        let zone: CGFloat = 32
        let down: CGFloat
        if fromTop < zone { down = -min(24, 2 + (zone - fromTop) / 3) }
        else if fromBottom < zone { down = min(24, 2 + (zone - fromBottom) / 3) }
        else { return }
        let maxY = max(0, document.frame.height - visible.height)
        var origin = visible.origin
        origin.y = min(maxY, max(0, origin.y + (clip.isFlipped ? down : -down)))
        guard origin != visible.origin else { return }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        extendSelection()
    }

    // MARK: Dragging out

    private func dragOut() {
        let urls = library.selectedFiles
        guard let view = gridView, let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              !urls.isEmpty else { return }
        mode = .draggingOut
        let point = view.convert(event.locationInWindow, from: nil)
        let size = CGSize(width: 72, height: 54)
        let items = urls.prefix(50).enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(CGRect(x: point.x - size.width / 2 + offset, y: point.y - size.height / 2 - offset,
                                         width: size.width, height: size.height),
                                  contents: library.cachedThumbnail(for: url) ?? NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        // More than 50 files: all of them go, only the picture shows fewer.
        let rest = urls.dropFirst(50).map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(CGRect(origin: point, size: .zero), contents: nil)
            return item
        }
        let session = view.beginDraggingSession(with: items + rest, event: event, source: self)
        session.draggingFormation = .pile
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                                     operation: NSDragOperation) {
        MainActor.assumeIsolated { mode = .idle }
    }
}
