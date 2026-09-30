import XCTest
@testable import MicroCAMCore

final class StreamAccessPolicyTests: XCTestCase {
    func testAllowsLocalAndTailscale() {
        for host in ["127.0.0.1", "10.0.0.5", "172.16.0.1", "172.31.255.255", "192.168.1.140",
                     "169.254.10.1", "100.100.100.100", "100.64.0.1", "100.127.255.254",
                     "::1", "fe80::1%en0", "fd7a:115c:a1e0::1", "fd12:3456::1", "fc00::1", "::ffff:192.168.1.5"] {
            XCTAssertTrue(StreamAccessPolicy.isAllowed(host), host)
        }
    }
    func testRejectsPublicAndGarbage() {
        for host in ["8.8.8.8", "172.32.0.1", "100.128.0.1", "100.63.255.255", "192.169.0.1",
                     "2001:4860:4860::8888", "::ffff:8.8.8.8", "example.com", "", "999.1.1.1"] {
            XCTAssertFalse(StreamAccessPolicy.isAllowed(host), host)
        }
    }
}
