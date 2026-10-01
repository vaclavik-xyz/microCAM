import XCTest
@testable import MicroCAMCore

final class AnnotationBoardTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func line(_ author: String?, id: String? = nil, kind: AnnotationShape.Kind = .arrow,
              points: Int = 2) -> AnnotationShape {
        AnnotationShape(kind: kind, points: (0..<points).map { AnnotationPoint(x: Double($0) / Double(max(points, 2)), y: 0.5) },
                        color: "#ff3b30", width: 0.006, id: id, author: author)
    }

    func testAddAssignsAnIDAndRejectsShapesWithoutAnAuthor() {
        let board = AnnotationBoard()
        let added = board.add(line("bench"))
        XCTAssertNotNil(added?.id)
        XCTAssertNil(board.add(line(nil)))
        XCTAssertNil(board.add(line("bad author!")))
        XCTAssertEqual(board.shapes.count, 1)
    }

    func testOnlyOwnShapesCanBeDeletedExceptByTheBench() {
        let board = AnnotationBoard()
        board.add(line("bench", id: "b1"))
        board.add(line("viewer", id: "v1"))
        board.add(line("viewer", id: "v2"))
        XCTAssertFalse(board.delete(id: "b1", by: "viewer"))
        XCTAssertFalse(board.delete(id: "v1", by: "other"))
        XCTAssertTrue(board.delete(id: "v1", by: "viewer"))
        XCTAssertTrue(board.delete(id: "v2", by: AnnotationBoard.bench))
        XCTAssertFalse(board.delete(id: "missing", by: AnnotationBoard.bench))
        XCTAssertEqual(board.shapes.map(\.id), ["b1"])
    }

    func testOnlyTheBenchCanClearAll() {
        let board = AnnotationBoard()
        board.add(line("viewer"))
        board.add(line("bench"))
        XCTAssertFalse(board.clearAll(by: "viewer"))
        XCTAssertEqual(board.shapes.count, 2)
        XCTAssertTrue(board.clearAll(by: AnnotationBoard.bench))
        XCTAssertTrue(board.isEmpty)
        XCTAssertFalse(board.clearAll(by: AnnotationBoard.bench))   // nothing to clear: no change
    }

    func testUndoRemovesTheAuthorsLatestShapeAndSkipsPointers() {
        let board = AnnotationBoard()
        board.add(line("bench", id: "a"))
        board.add(line("viewer", id: "v"))
        board.add(line("bench", id: "b"))
        board.add(line("bench", id: "p", kind: .pointer), now: t0)
        XCTAssertEqual(board.undo(by: "bench")?.id, "b")
        XCTAssertEqual(board.undo(by: "bench")?.id, "a")
        XCTAssertNil(board.undo(by: "bench"))
        XCTAssertEqual(board.shapes.map(\.id), ["v", "p"])
    }

    func testDeleteAllRemovesOnlyTheAuthorsShapes() {
        let board = AnnotationBoard()
        board.add(line("bench"))
        board.add(line("viewer"))
        board.add(line("viewer"))
        XCTAssertEqual(board.deleteAll(by: "viewer"), 2)
        XCTAssertEqual(board.shapes.map(\.author), ["bench"])
    }

    func testEveryChangeBumpsTheRevisionOnce() {
        let board = AnnotationBoard()
        XCTAssertEqual(board.revision, 0)
        board.add(line("bench", id: "a"))
        board.add(line("bench", id: "b"))
        board.delete(id: "a", by: "bench")
        XCTAssertEqual(board.revision, 3)
        board.delete(id: "a", by: "bench")   // refused: no change
        board.add(line(nil))
        XCTAssertEqual(board.revision, 3)
        board.clearAll(by: "bench")
        XCTAssertEqual(board.revision, 4)
    }

    func testChangesSinceReturnsWhatAClientMissed() throws {
        let board = AnnotationBoard()
        let a = try XCTUnwrap(board.add(line("bench", id: "a")))
        let b = try XCTUnwrap(board.add(line("viewer", id: "b")))
        board.delete(id: "a", by: "bench")
        XCTAssertEqual(board.changes(since: 3), .changes([]))
        XCTAssertEqual(board.changes(since: 1), .changes([
            .init(revision: 2, change: .add(b)),
            .init(revision: 3, change: .delete("a")),
        ]))
        XCTAssertEqual(board.changes(since: 0), .changes([
            .init(revision: 1, change: .add(a)),
            .init(revision: 2, change: .add(b)),
            .init(revision: 3, change: .delete("a")),
        ]))
        XCTAssertEqual(board.changes(since: 9), .snapshot(revision: 3, shapes: [b]))
    }

    func testChangesSinceGivesASnapshotWhenTooOld() {
        let board = AnnotationBoard()
        for i in 0..<(AnnotationBoard.historyLimit + 10) {
            board.add(line("bench", id: "s\(i)"))
            board.delete(id: "s\(i)", by: "bench")
        }
        XCTAssertEqual(board.changes(since: 1), .snapshot(revision: board.revision, shapes: []))
        guard case .changes(let recent) = board.changes(since: board.revision - 2) else { return XCTFail() }
        XCTAssertEqual(recent.count, 2)
    }

    func testAPointerIsUpdatedInPlace() {
        let board = AnnotationBoard()
        board.add(line("bench", id: "a"))
        board.add(line("bench", id: "p", kind: .pointer), now: t0)
        board.add(line("bench", id: "b"))
        let updated = board.add(line("bench", id: "p", kind: .pointer, points: 5), now: t0 + 1)
        XCTAssertEqual(updated?.points.count, 5)
        XCTAssertEqual(board.shapes.map(\.id), ["a", "p", "b"])
        XCTAssertEqual(board.changes(since: 3), .changes([.init(revision: 4, change: .update(updated!))]))
    }

    func testUpdatesByAnotherAuthorOrToAnotherKindAreRefused() {
        let board = AnnotationBoard()
        board.add(line("viewer", id: "x"))
        XCTAssertNil(board.add(line("other", id: "x")))
        XCTAssertNil(board.add(line("viewer", id: "x", kind: .ellipse)))
        XCTAssertEqual(board.revision, 1)
    }

    func testPointersExpireAfterTheirLastPoint() {
        let board = AnnotationBoard()
        board.add(line("bench", id: "p", kind: .pointer), now: t0)
        board.add(line("bench", id: "p", kind: .pointer, points: 3), now: t0 + 1)
        XCTAssertFalse(board.prune(now: t0 + 3.4))
        XCTAssertTrue(board.hasPointers)
        XCTAssertTrue(board.prune(now: t0 + 3.5))
        XCTAssertTrue(board.isEmpty)
        XCTAssertFalse(board.hasPointers)
    }

    func testPointerOpacityFadesAtTheEnd() {
        let board = AnnotationBoard()
        board.add(line("bench", id: "p", kind: .pointer), now: t0)
        XCTAssertEqual(board.pointerOpacity(id: "p", now: t0 + 1.9), 1)
        XCTAssertEqual(board.pointerOpacity(id: "p", now: t0 + 2.25), 0.5, accuracy: 0.001)
        XCTAssertEqual(board.pointerOpacity(id: "p", now: t0 + 2.5), 0)
        XCTAssertEqual(board.pointerOpacity(id: "missing", now: t0), 0)
    }

    func testASixthPointerReplacesTheOldest() {
        let board = AnnotationBoard()
        for i in 0..<6 { board.add(line("v\(i)", id: "p\(i)", kind: .pointer), now: t0 + Double(i)) }
        XCTAssertEqual(board.shapes.map(\.id), ["p1", "p2", "p3", "p4", "p5"])
    }

    func testShapeAndPointLimits() {
        let board = AnnotationBoard()
        for _ in 0..<AnnotationRequest.maxShapes { XCTAssertNotNil(board.add(line("bench"))) }
        XCTAssertNil(board.add(line("bench")))
        XCTAssertNotNil(board.add(line("bench", kind: .pointer)))   // pointers have their own limit

        let points = AnnotationBoard()
        XCTAssertNotNil(points.add(line("bench", kind: .pen, points: 4_999)))
        XCTAssertNil(points.add(line("bench", kind: .pen, points: 2)))
        XCTAssertEqual(points.add(line("bench", kind: .pointer, points: 300))?.points.count, 200)
    }

    func testPhotoShapesAreThePersistentOnesAndOnlyForPhotos() {
        let board = AnnotationBoard()
        board.add(line("bench", id: "a"))
        board.add(line("bench", id: "p", kind: .pointer))
        XCTAssertEqual(board.photoShapes(for: .photo).map(\.id), ["a"])
        XCTAssertEqual(board.photoShapes(for: .timelapse), [])
        XCTAssertEqual(board.persistent.map(\.id), ["a"])
    }

    func testConcurrentAddsStayConsistent() {
        let board = AnnotationBoard()
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            for j in 0..<20 { board.add(line("v\(i)", id: "s\(i)-\(j)")) }
        }
        XCTAssertEqual(board.shapes.count, 160)
        XCTAssertEqual(board.revision, 160)
        XCTAssertEqual(Set(board.shapes.compactMap(\.id)).count, 160)
    }
}
