import XCTest

/// microCAM is published as open source: nothing in the repository may name
/// the maintainer's own machines (they were used during development and
/// testing), their Tailscale addresses or tailnet host names. Checks every
/// file git tracks. Use generic stand-ins instead: "bench Mac", "reception
/// Mac", `<bench-host>`, 192.0.2.x, or 100.64.0.1 as a Tailscale example.
final class NoDeviceNamesTests: XCTestCase {
    static let forbiddenNames = ["macbench", "macrecepce", "personal-mbp", "filip"]
    /// Tailscale's CGNAT range 100.64.0.0/10 (100.64.x.x – 100.127.x.x).
    static let tailscaleAddress = try! NSRegularExpression(
        pattern: #"(?<![\d.])100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}(?![\d])"#)
    /// Range bounds and documentation examples, never a real device.
    static let allowedAddresses: Set<String> = ["100.64.0.0", "100.64.0.1", "100.127.255.254", "100.127.255.255",
                                                "100.100.100.100"]
    static let tailnetHost = try! NSRegularExpression(pattern: #"[A-Za-z0-9-]\.ts\.net\b"#)

    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func trackedFiles() throws -> [String] {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", repo.path, "ls-files", "-z"]
        let pipe = Pipe()
        git.standardOutput = pipe
        try git.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        XCTAssertEqual(git.terminationStatus, 0, "git ls-files failed")
        return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    }

    func testRepositoryNamesNoPrivateDevicesOrAddresses() throws {
        let files = try trackedFiles()
        XCTAssertTrue(files.contains("Package.swift"), "expected to run inside the git checkout")
        let ownPath = String(#filePath.dropFirst(repo.path.count + 1))
        var hits: [String] = []
        for path in files {
            // Binary files (images) are not text; skip what does not decode.
            guard let text = try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let place = "\(path):\(index + 1)"
                let lower = line.lowercased()
                if path != ownPath {
                    for name in Self.forbiddenNames where lower.contains(name) { hits.append("\(place): \(name)") }
                }
                let range = NSRange(line.startIndex..., in: line)
                for match in Self.tailscaleAddress.matches(in: line, range: range) {
                    let address = String(line[Range(match.range, in: line)!])
                    if !Self.allowedAddresses.contains(address) { hits.append("\(place): Tailscale address \(address)") }
                }
                if Self.tailnetHost.firstMatch(in: line, range: range) != nil { hits.append("\(place): tailnet host name") }
            }
        }
        XCTAssertTrue(hits.isEmpty, "private device names or addresses in the repository:\n" + hits.joined(separator: "\n"))
    }

    func testPatternsCatchWhatTheyShould() {
        func address(_ s: String) -> Bool { Self.tailscaleAddress.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        XCTAssertTrue(address("ssh 100.64.0.1"))
        XCTAssertTrue(address("http://100.127.255.254:8090/"))
        XCTAssertFalse(address("100.128.0.1"))
        XCTAssertFalse(address("100.63.255.255"))
        XCTAssertFalse(address("10.100.64.1"))
        let host = "bench.example" + ".ts.net"   // split so this file passes its own check
        XCTAssertNotNil(Self.tailnetHost.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)))
    }
}
