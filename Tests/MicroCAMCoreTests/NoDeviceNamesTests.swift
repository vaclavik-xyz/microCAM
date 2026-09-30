import XCTest

/// microCAM is published as open source: the app and its UI must not name the
/// maintainer's own machines (they were used during development and testing).
final class NoDeviceNamesTests: XCTestCase {
    static let forbidden = ["macbench", "macrecepce", "personal-mbp", "filip"]

    func testSourcesAndResourcesNameNoPrivateDevices() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var hits: [String] = []
        for dir in ["Sources", "Resources"] {
            let root = repo.appendingPathComponent(dir)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                return XCTFail("cannot list \(root.path)")
            }
            for case let file as URL in files {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                    let lower = line.lowercased()
                    for name in Self.forbidden where lower.contains(name) {
                        hits.append("\(dir)/\(file.path.dropFirst(root.path.count + 1)):\(index + 1): \(name)")
                    }
                }
            }
        }
        XCTAssertTrue(hits.isEmpty, "private device names in the app:\n" + hits.joined(separator: "\n"))
    }
}
