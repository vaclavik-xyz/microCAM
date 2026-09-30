import XCTest
@testable import MicroCAMCore

final class ErrorDetailsTests: XCTestCase {
    func testIncludesDomainCodeAndUnderlyingChain() {
        let root = NSError(domain: NSOSStatusErrorDomain, code: -12780)
        let middle = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                             userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed",
                                        NSUnderlyingErrorKey: root])
        XCTAssertEqual(ErrorDetails.describe(middle),
                       "The operation could not be completed (AVFoundationErrorDomain -11800 ← NSOSStatusErrorDomain -12780)")
    }

    func testNilErrorHasAFallback() {
        XCTAssertEqual(ErrorDetails.describe(nil, fallback: "writer"), "writer")
    }
}
