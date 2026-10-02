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
    }

    func testRejectsOtherMessages() {
        XCTAssertNil(StreamPageState.decode("hello"))
        XCTAssertNil(StreamPageState.decode(#"{"drawing":true}"#))
    }
}
