import XCTest

/// Every text the user sees must exist in every language. English (`en`) is
/// the source language; each other `Resources/<lang>.lproj` must translate
/// every key, and the stream page's JS dictionary must cover the same keys
/// in every language. See "Localization" in README.md.
final class LocalizationTests: XCTestCase {
    /// Keys whose translation is meant to be identical to English, per language.
    static let sameAsEnglish: [String: Set<String>] = [
        "cs": ["microCAM", "URL", "Port", "Token", "Video"],
    ]
    /// Stream page keys meant to be identical to English, per language.
    static let streamSameAsEnglish: [String: Set<String>] = [
        "cs": [],
    ]
    /// Files allowed to contain Czech text (folder names on disk, translations).
    static let czechAllowed: Set<String> = [
        "Sources/MicroCAMCore/FolderLanguage.swift",
        "Sources/MicroCAMApp/Streaming/StreamPage.swift", // its STRINGS dictionary
    ]

    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let development = "en"

    // MARK: Helpers

    func languages() throws -> [String] {
        let resources = repo.appendingPathComponent("Resources")
        return try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) }.sorted()
    }

    func strings(_ table: String, _ lang: String) throws -> [String: String] {
        let url = repo.appendingPathComponent("Resources/\(lang).lproj/\(table).strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(url.path) is not a strings table")
    }

    /// Format specifiers become the scanner's placeholder, `%%` becomes `%`.
    static func normalized(_ key: String) -> String {
        let spec = try! NSRegularExpression(pattern: #"%(\d+\$)?(lld|ld|d|@|lf|f)"#)
        let replaced = spec.stringByReplacingMatches(in: key, range: NSRange(key.startIndex..., in: key),
                                                     withTemplate: SwiftLiteralScanner.placeholder)
        return replaced.replacingOccurrences(of: "%%", with: "%")
    }

    static func placeholders(_ text: String) -> [String] {
        let spec = try! NSRegularExpression(pattern: #"%(\d+\$)?(lld|ld|d|@|lf|f)"#)
        return spec.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
            .sorted()
    }

    func swiftFiles(_ dir: String) throws -> [(path: String, text: String)] {
        let root = repo.appendingPathComponent(dir)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return try enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .map { (dir + "/" + $0.path.dropFirst(root.path.count + 1), try String(contentsOf: $0, encoding: .utf8)) }
            .sorted { $0.path < $1.path }
    }

    func sourceLiterals() throws -> [SwiftLiteralScanner.Literal] {
        try swiftFiles("Sources/MicroCAMApp").flatMap {
            try SwiftLiteralScanner.localizableLiterals(in: $0.text, file: $0.path)
        }
    }

    // MARK: Tests

    func testScannerFindsLocalizableLiterals() throws {
        let source = #"""
        Text("Hello") // Text("comment")
        Text(verbatim: "not me")
        Button("Save \(name) now") { }
        Label(title, systemImage: "camera")
        x.help("Tip")
        let s = String(localized: "Moved: \(count)")
        MyText("no")
        """#
        let keys = try SwiftLiteralScanner.localizableLiterals(in: source, file: "t").map(\.key)
        let p = SwiftLiteralScanner.placeholder
        XCTAssertEqual(keys, ["Hello", "Save \(p) now", "Tip", "Moved: \(p)"])
        XCTAssertEqual(Self.normalized("Moved: %lld of %@, 5 %%"), "Moved: \(p) of \(p), 5 %")
    }

    func testEveryLocalizableLiteralIsInEveryLanguage() throws {
        let literals = try sourceLiterals()
        XCTAssertFalse(literals.isEmpty)
        var missing: [String] = []
        for lang in try languages() {
            let keys = Set(try strings("Localizable", lang).keys.map(Self.normalized))
            for literal in literals where !keys.contains(literal.key) {
                missing.append("\(literal.file):\(literal.line): \"\(literal.key.replacingOccurrences(of: SwiftLiteralScanner.placeholder, with: "%@"))\" is missing in \(lang).lproj/Localizable.strings")
            }
        }
        XCTAssertTrue(missing.isEmpty, "\n" + missing.joined(separator: "\n"))
    }

    func testNoUnusedKeys() throws {
        let used = Set(try sourceLiterals().map(\.key))
        let unused = try strings("Localizable", development).keys.filter { !used.contains(Self.normalized($0)) }.sorted()
        XCTAssertTrue(unused.isEmpty, "keys no longer used in Sources/MicroCAMApp (remove them from every language):\n"
                      + unused.joined(separator: "\n"))
    }

    func testEveryLanguageTranslatesEveryKey() throws {
        let langs = try languages()
        XCTAssertTrue(langs.contains(development))
        XCTAssertTrue(langs.contains("cs"))
        var problems: [String] = []
        for table in ["Localizable", "InfoPlist"] {
            let english = try strings(table, development)
            for lang in langs {
                let other = try strings(table, lang)
                for key in english.keys.sorted() where other[key] == nil {
                    problems.append("\(lang).lproj/\(table).strings: missing \"\(key)\"")
                }
                for key in other.keys.sorted() where english[key] == nil {
                    problems.append("\(lang).lproj/\(table).strings: \"\(key)\" is not in \(development).lproj")
                }
                for (key, value) in other.sorted(by: { $0.key < $1.key }) {
                    if value.trimmingCharacters(in: .whitespaces).isEmpty {
                        problems.append("\(lang).lproj/\(table).strings: empty value for \"\(key)\"")
                    }
                    guard lang != development, let en = english[key] else { continue }
                    if value == en, !(Self.sameAsEnglish[lang] ?? []).contains(key) {
                        problems.append("\(lang).lproj/\(table).strings: \"\(key)\" is not translated (same as English; "
                                        + "add it to LocalizationTests.sameAsEnglish if that is intended)")
                    }
                    if Self.placeholders(value) != Self.placeholders(en) {
                        problems.append("\(lang).lproj/\(table).strings: \"\(key)\" has placeholders \(Self.placeholders(value)), English has \(Self.placeholders(en))")
                    }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "\n" + problems.joined(separator: "\n"))
    }

    func testStringsFilesHaveNoDuplicateKeys() throws {
        var problems: [String] = []
        let keyPattern = try NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*="#, options: .anchorsMatchLines)
        for lang in try languages() {
            for table in ["Localizable", "InfoPlist"] {
                let text = try String(contentsOf: repo.appendingPathComponent("Resources/\(lang).lproj/\(table).strings"), encoding: .utf8)
                var seen = Set<String>()
                for match in keyPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let key = String(text[Range(match.range(at: 1), in: text)!])
                    if !seen.insert(key).inserted { problems.append("\(lang).lproj/\(table).strings: duplicate \"\(key)\"") }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "\n" + problems.joined(separator: "\n"))
    }

    func testInfoPlistDeclaresTheLanguagesAndTranslatesUsageTexts() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleDevelopmentRegion"] as? String, development)
        XCTAssertEqual((plist["CFBundleLocalizations"] as? [String])?.sorted(), try languages())
        let usage = plist.keys.filter { $0.hasSuffix("UsageDescription") }.sorted()
        XCTAssertFalse(usage.isEmpty)
        for lang in try languages() {
            let table = try strings("InfoPlist", lang)
            for key in usage { XCTAssertNotNil(table[key], "\(lang).lproj/InfoPlist.strings: missing \(key)") }
        }
    }

    func testStreamPageDictionaryCoversEveryLanguageAndKey() throws {
        let page = try String(contentsOf: repo.appendingPathComponent("Sources/MicroCAMApp/Streaming/StreamPage.swift"), encoding: .utf8)
        let start = try XCTUnwrap(page.range(of: "const STRINGS = "), "STRINGS dictionary not found in StreamPage.swift")
        let end = try XCTUnwrap(page.range(of: "; // end STRINGS", range: start.upperBound..<page.endIndex))
        let json = Data(page[start.upperBound..<end.lowerBound].utf8)
        let dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: [String: String]],
                                 "STRINGS must be strict JSON: {\"en\": {…}, \"cs\": {…}}")
        XCTAssertEqual(dict.keys.sorted(), try languages(), "the stream page must offer the same languages as the app")
        let english = try XCTUnwrap(dict[development])
        var problems: [String] = []
        for (lang, table) in dict.sorted(by: { $0.key < $1.key }) {
            for key in english.keys.sorted() where table[key] == nil { problems.append("stream page \(lang): missing \"\(key)\"") }
            for key in table.keys.sorted() where english[key] == nil { problems.append("stream page \(lang): \"\(key)\" is not in \(development)") }
            for (key, value) in table where value.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("stream page \(lang): empty value for \"\(key)\"")
            }
            if lang != development {
                for (key, value) in table where value == english[key] && !(Self.streamSameAsEnglish[lang] ?? []).contains(key) {
                    problems.append("stream page \(lang): \"\(key)\" is not translated (same as English)")
                }
            }
        }
        // Every key the markup and script ask for must exist.
        let used = try NSRegularExpression(pattern: #"data-i18n(?:-title|-aria)?="([A-Za-z0-9]+)"|\bt\("([A-Za-z0-9]+)""#)
        let html = String(page[end.upperBound...]) + String(page[..<start.lowerBound])
        for match in used.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            let key = String(html[Range(range, in: html)!])
            if english[key] == nil { problems.append("stream page uses \"\(key)\", which is not in STRINGS.\(development)") }
        }
        XCTAssertTrue(problems.isEmpty, "\n" + problems.joined(separator: "\n"))
    }

    /// All text lives in the strings tables; code and comments are English.
    func testNoHardcodedCzechInSources() throws {
        let czech = CharacterSet(charactersIn: "ěščřžýáíéůúňťďĚŠČŘŽÝÁÍÉŮÚŇŤĎ")
        var hits: [String] = []
        for file in try swiftFiles("Sources/MicroCAMApp") + swiftFiles("Sources/MicroCAMCore") where !Self.czechAllowed.contains(file.path) {
            for (index, line) in file.text.components(separatedBy: .newlines).enumerated()
            where line.rangeOfCharacter(from: czech) != nil {
                hits.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(hits.isEmpty, "Czech text outside the strings tables:\n" + hits.joined(separator: "\n"))
    }
}
