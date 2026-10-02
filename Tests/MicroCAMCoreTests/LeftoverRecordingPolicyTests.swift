import XCTest
@testable import MicroCAMCore

final class LeftoverRecordingPolicyTests: XCTestCase {
    /// The bench Mac kept a 214 KB file without a moov atom (ended in its first
    /// seconds) and opened Finder on every launch.
    func testUnplayableGoesToTheTrash() {
        XCTAssertEqual(LeftoverRecordingPolicy.action(playableSeconds: nil, hasStorage: true), .trash)
        XCTAssertEqual(LeftoverRecordingPolicy.action(playableSeconds: 0, hasStorage: false), .trash)
    }

    func testPlayableIsRecoveredOnceThereIsAFolder() {
        XCTAssertEqual(LeftoverRecordingPolicy.action(playableSeconds: 42, hasStorage: true), .recover)
        XCTAssertEqual(LeftoverRecordingPolicy.action(playableSeconds: 42, hasStorage: false), .keep)
    }
}
