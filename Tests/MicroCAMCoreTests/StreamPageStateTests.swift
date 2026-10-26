import XCTest
@testable import MicroCAMCore

final class StreamPageStateTests: XCTestCase {
    /// The JSON exactly as the page's report() builds it.
    func testDecodesThePageReport() {
        let json = ##"{"drawing":true,"tool":"text","color":"#ffd60a","size":"large","shapes":2,"photoEnabled":false,"frozen":false,"offline":false,"job":"PR-1"}"##
        let state = StreamPageState.decode(json)
        XCTAssertEqual(state?.drawing, true)
        XCTAssertEqual(state.flatMap { AnnotationShape.Kind(rawValue: $0.tool) }, .text)
        XCTAssertEqual(state.flatMap { AnnotationTextSize(rawValue: $0.size) }, .large)
        XCTAssertEqual(state?.shapes, 2)
        XCTAssertEqual(state?.job, "PR-1")
        XCTAssertNil(state?.gallery)
    }

    /// A camera Mac with the photo browser reports whether it is open.
    func testDecodesTheGalleryState() {
        let json = ##"{"drawing":false,"tool":"arrow","color":"#ff3b30","size":"medium","shapes":0,"photoEnabled":true,"frozen":false,"offline":false,"job":"","gallery":true}"##
        XCTAssertEqual(StreamPageState.decode(json)?.gallery, true)
        XCTAssertNil(StreamPageState.decode(json)?.docked)
        let docked = json.replacingOccurrences(of: #""gallery":true"#, with: #""gallery":true,"docked":true"#)
        XCTAssertEqual(StreamPageState.decode(docked)?.docked, true)
    }

    func testRejectsOtherMessages() {
        XCTAssertNil(StreamPageState.decode("hello"))
        XCTAssertNil(StreamPageState.decode(#"{"drawing":true}"#))
    }
}
