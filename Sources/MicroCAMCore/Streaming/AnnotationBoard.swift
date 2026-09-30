import Foundation

/// The live drawing over the camera picture, shared by everyone who draws on
/// it: the Mac (author `bench`) and, later, stream viewers (a random id each).
///
/// Everyone may add shapes and undo or delete their own; only the bench may
/// delete anyone's shape or clear the board. Pointers are strokes that expire
/// `pointerLifetime` after their last point; they are updated in place (same
/// id) while they move, and never go into photos.
///
/// Every change bumps `revision` by one and is kept in a short history, so a
/// client that missed some changes gets exactly those (`changes(since:)`), or a
/// snapshot when it is too far behind. Knows nothing of networking or UI.
/// Thread-safe.
public final class AnnotationBoard: @unchecked Sendable {
    public static let bench = "bench"
    public static let pointerLifetime: TimeInterval = 2.5
    /// The last part of a pointer's life, in which it fades out.
    public static let pointerFade: TimeInterval = 0.5
    public static let maxPointers = 5
    public static let historyLimit = 500

    public enum Change: Equatable, Sendable {
        case add(AnnotationShape)
        case update(AnnotationShape)
        case delete(String)
        case clear
    }

    public struct Revisioned: Equatable, Sendable {
        public let revision: Int
        public let change: Change
        public init(revision: Int, change: Change) { self.revision = revision; self.change = change }
    }

    public enum Delta: Equatable, Sendable {
        case changes([Revisioned])
        case snapshot(revision: Int, shapes: [AnnotationShape])
    }

    private let lock = NSLock()
    private var items: [AnnotationShape] = []
    /// When each pointer got its last point.
    private var pointerUpdates: [String: Date] = [:]
    private var history: [Revisioned] = []
    private var currentRevision = 0

    public init() {}

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    public var revision: Int { locked { currentRevision } }
    /// Everything, in drawing order, pointers included.
    public var shapes: [AnnotationShape] { locked { items } }
    /// What a photo or video keeps: everything except pointers.
    public var persistent: [AnnotationShape] { locked { items.filter { $0.kind != .pointer } } }
    public var isEmpty: Bool { locked { items.isEmpty } }
    public var hasPointers: Bool { locked { items.contains { $0.kind == .pointer } } }

    /// The shapes a capture of `kind` carries: only photos get the drawing
    /// (timelapse shots stay clean).
    public func photoShapes(for kind: CaptureKind) -> [AnnotationShape] {
        kind == .photo ? persistent : []
    }

    /// Adds a shape, or replaces the author's shape with the same id (a moving
    /// pointer). Returns the stored, sanitized shape, or nil when refused.
    @discardableResult
    public func add(_ shape: AnnotationShape, now: Date = Date()) -> AnnotationShape? {
        locked {
            guard let author = AnnotationShape.cleanID(shape.author) else { return nil }
            let id = AnnotationShape.cleanID(shape.id) ?? UUID().uuidString
            let existing = items.firstIndex { $0.id == id }
            if let existing, items[existing].author != author || items[existing].kind != shape.kind { return nil }
            let isPointer = shape.kind == .pointer
            let budget = isPointer ? AnnotationShape.maxPointerPoints
                : AnnotationRequest.maxPoints - items.enumerated()
                    .filter { $0.offset != existing && $0.element.kind != .pointer }
                    .reduce(0) { $0 + $1.element.points.count }
            var input = shape
            input.id = id
            input.author = author
            guard let clean = input.sanitized(pointBudget: budget) else { return nil }
            if let existing {
                items[existing] = clean
                if isPointer { pointerUpdates[id] = now }
                record(.update(clean))
                return clean
            }
            if isPointer {
                let pointers = items.filter { $0.kind == .pointer }
                if pointers.count >= Self.maxPointers,
                   let oldest = pointers.min(by: { pointerUpdates[$0.id!, default: .distantPast] < pointerUpdates[$1.id!, default: .distantPast] })?.id {
                    remove(oldest)
                }
                pointerUpdates[id] = now
            } else if items.filter({ $0.kind != .pointer }).count >= AnnotationRequest.maxShapes {
                return nil
            }
            items.append(clean)
            record(.add(clean))
            return clean
        }
    }

    /// Own shapes only; the bench may delete any.
    @discardableResult
    public func delete(id: String, by author: String) -> Bool {
        locked {
            guard let shape = items.first(where: { $0.id == id }),
                  author == Self.bench || shape.author == author else { return false }
            remove(id)
            return true
        }
    }

    /// Removes the author's most recently added shape (pointers aside).
    @discardableResult
    public func undo(by author: String) -> AnnotationShape? {
        locked {
            guard let shape = items.last(where: { $0.author == author && $0.kind != .pointer }),
                  let id = shape.id else { return nil }
            remove(id)
            return shape
        }
    }

    /// Removes every shape of the author; returns how many.
    @discardableResult
    public func deleteAll(by author: String) -> Int {
        locked {
            let ids = items.filter { $0.author == author }.compactMap(\.id)
            ids.forEach(remove)
            return ids.count
        }
    }

    /// Only the bench may clear the board.
    @discardableResult
    public func clearAll(by author: String) -> Bool {
        locked {
            guard author == Self.bench, !items.isEmpty else { return false }
            items = []
            pointerUpdates = [:]
            record(.clear)
            return true
        }
    }

    /// What happened after `revision`: the missed changes, or a snapshot when
    /// they are no longer in the history (or the client is ahead).
    public func changes(since revision: Int) -> Delta {
        locked {
            if revision == currentRevision { return .changes([]) }
            let oldest = history.first?.revision ?? currentRevision + 1
            guard revision < currentRevision, revision >= oldest - 1 else {
                return .snapshot(revision: currentRevision, shapes: items)
            }
            return .changes(history.filter { $0.revision > revision })
        }
    }

    /// Drops pointers whose last point is `pointerLifetime` old. True when
    /// something was removed.
    @discardableResult
    public func prune(now: Date = Date()) -> Bool {
        locked {
            let expired = items.filter { $0.kind == .pointer }.compactMap(\.id).filter {
                now.timeIntervalSince(pointerUpdates[$0, default: .distantPast]) >= Self.pointerLifetime
            }
            expired.forEach(remove)
            return !expired.isEmpty
        }
    }

    /// 1 for most of a pointer's life, then fading linearly to 0 when it expires.
    public func pointerOpacity(id: String, now: Date = Date()) -> Double {
        locked {
            guard let updated = pointerUpdates[id] else { return 0 }
            let left = Self.pointerLifetime - now.timeIntervalSince(updated)
            return min(max(left / Self.pointerFade, 0), 1)
        }
    }

    // MARK: Under the lock

    private func remove(_ id: String) {
        items.removeAll { $0.id == id }
        pointerUpdates[id] = nil
        record(.delete(id))
    }

    private func record(_ change: Change) {
        currentRevision += 1
        history.append(Revisioned(revision: currentRevision, change: change))
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }
}
