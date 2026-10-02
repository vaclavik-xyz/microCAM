import XCTest
@testable import MicroCAMCore

final class ViewerURLTests: XCTestCase {
    /// Network.framework describes a resolved Bonjour address with its
    /// interface ("192.168.1.140%en0"); that is no valid URL host, and 0.5.1
    /// silently did nothing on Connect.
    func testDropsTheInterfaceFromAResolvedAddress() {
        XCTAssertEqual(ViewerURL.stream(host: "192.168.1.140%en0", port: 8090, language: "cs")?.absoluteString,
                       "http://192.168.1.140:8090/?embedded=1&lang=cs")
    }

    func testPlainAddress() {
        XCTAssertEqual(ViewerURL.stream(host: "10.0.0.5", port: 9000, language: "en")?.absoluteString,
                       "http://10.0.0.5:9000/?embedded=1&lang=en")
    }

    func testRejectsNonsense() {
        XCTAssertNil(ViewerURL.stream(host: "", port: 8090, language: "en"))
        XCTAssertNil(ViewerURL.stream(host: "%en0", port: 8090, language: "en"))
    }
}
