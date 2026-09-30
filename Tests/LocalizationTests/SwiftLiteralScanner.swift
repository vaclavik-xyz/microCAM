import Foundation

/// Finds the string literals SwiftUI and `String(localized:)` look up in
/// `Localizable.strings`. A deliberately small lexer: it skips comments and
/// other literals, and turns each literal into its lookup key with
/// interpolations replaced by `SwiftLiteralScanner.placeholder`.
enum SwiftLiteralScanner {
    static let placeholder = "\u{FFFC}"

    /// Calls whose first unlabelled string-literal argument is a
    /// `LocalizedStringKey` (or `String.LocalizationValue`).
    static let localizedCalls = [
        "Text", "Label", "Button", "Toggle", "Picker", "TextField", "SecureField", "LabeledContent",
        "Section", "Menu", "CommandMenu", "ShareLink", "ProgressView", "Link", "GroupBox", "Stepper",
        "DatePicker", "ColorPicker", "Slider", "LocalizedStringKey", "Window", "WindowGroup",
        ".help", ".navigationTitle", ".alert", ".confirmationDialog", ".accessibilityLabel",
        "String(localized:", "LocalizedStringResource(",
    ]

    struct Literal: Hashable {
        let key: String
        let file: String
        let line: Int
    }

    struct Problem: Error, CustomStringConvertible {
        let description: String
    }

    /// Localizable literals in `source`. Throws for a literal form the
    /// scanner cannot turn into a key (multi-line or raw strings).
    static func localizableLiterals(in source: String, file: String) throws -> [Literal] {
        let chars = Array(source)
        var result: [Literal] = []
        var i = 0
        var lineStarts = [0]
        for (index, c) in chars.enumerated() where c == "\n" { lineStarts.append(index + 1) }
        func line(at index: Int) -> Int { lineStarts.lastIndex { $0 <= index }! + 1 }
        while i < chars.count {
            if let end = skipCommentOrLiteral(chars, at: i) { i = end; continue }
            guard let call = localizedCalls.first(where: { matches(chars, at: i, call: $0) }) else { i += 1; continue }
            var j = i + call.count
            if !call.hasSuffix("(") && !call.hasSuffix(":") {
                guard j < chars.count, chars[j] == "(" else { i = j; continue }
                j += 1
            }
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            if call == "Text", matches(chars, at: j, word: "verbatim:") { i = j; continue }
            if j < chars.count, chars[j] == "#" || (chars[j] == "\"" && matches(chars, at: j, word: "\"\"\"")) {
                throw Problem(description: "\(file):\(line(at: j)): use a single-line, non-raw literal for localized text")
            }
            if j < chars.count, chars[j] == "\"" {
                let (key, end) = try readLiteral(chars, at: j, file: file, line: line(at: j))
                if !key.isEmpty { result.append(Literal(key: key, file: file, line: line(at: j))) }
                i = end
            } else {
                i = j
            }
        }
        return result
    }

    // MARK: Lexing

    private static func matches(_ chars: [Character], at i: Int, word: String) -> Bool {
        let w = Array(word)
        return i + w.count <= chars.count && Array(chars[i..<i + w.count]) == w
    }

    private static func matches(_ chars: [Character], at i: Int, call: String) -> Bool {
        guard matches(chars, at: i, word: call) else { return false }
        // Whole identifier only: `MyText(` or `.textButton(` must not match.
        if !call.hasPrefix("."), i > 0, chars[i - 1].isLetter || chars[i - 1].isNumber || chars[i - 1] == "_" || chars[i - 1] == "." {
            return false
        }
        let next = i + call.count
        if !call.hasSuffix("(") && !call.hasSuffix(":"), next < chars.count,
           chars[next].isLetter || chars[next].isNumber || chars[next] == "_" { return false }
        return true
    }

    /// End index of a comment or string literal starting at `i`, else nil.
    private static func skipCommentOrLiteral(_ chars: [Character], at i: Int) -> Int? {
        if matches(chars, at: i, word: "//") {
            var j = i
            while j < chars.count, chars[j] != "\n" { j += 1 }
            return j
        }
        if matches(chars, at: i, word: "/*") {
            var j = i + 2
            while j < chars.count, !matches(chars, at: j, word: "*/") { j += 1 }
            return min(chars.count, j + 2)
        }
        // Raw literal: #"…"# or #"""…"""#
        if chars[i] == "#" {
            var hashes = 0
            while i + hashes < chars.count, chars[i + hashes] == "#" { hashes += 1 }
            let start = i + hashes
            guard start < chars.count, chars[start] == "\"" else { return nil }
            let quotes = matches(chars, at: start, word: "\"\"\"") ? "\"\"\"" : "\""
            let close = quotes + String(repeating: "#", count: hashes)
            var j = start + quotes.count
            while j < chars.count, !matches(chars, at: j, word: close) { j += 1 }
            return min(chars.count, j + close.count)
        }
        if matches(chars, at: i, word: "\"\"\"") {
            var j = i + 3
            while j < chars.count, !matches(chars, at: j, word: "\"\"\"") { j += chars[j] == "\\" ? 2 : 1 }
            return min(chars.count, j + 3)
        }
        if chars[i] == "\"" {
            return (try? readLiteral(chars, at: i, file: "", line: 0))?.1
        }
        return nil
    }

    /// Reads `"…"` at `i`; returns the key text and the index after the closing quote.
    private static func readLiteral(_ chars: [Character], at i: Int, file: String, line: Int) throws -> (String, Int) {
        var key = ""
        var j = i + 1
        while j < chars.count {
            let c = chars[j]
            if c == "\"" { return (key, j + 1) }
            if c == "\n" { break }
            if c == "\\" {
                guard j + 1 < chars.count else { break }
                let e = chars[j + 1]
                switch e {
                case "(":
                    j = try skipInterpolation(chars, at: j + 2, file: file, line: line)
                    key += placeholder
                    continue
                case "n": key += "\n"
                case "t": key += "\t"
                case "\"": key += "\""
                case "\\": key += "\\"
                case "'": key += "'"
                case "u":
                    var k = j + 3
                    var hex = ""
                    while k < chars.count, chars[k] != "}" { hex.append(chars[k]); k += 1 }
                    if let v = UInt32(hex, radix: 16), let s = Unicode.Scalar(v) { key += String(s) }
                    j = k + 1
                    continue
                default: key.append(e)
                }
                j += 2
                continue
            }
            key.append(c)
            j += 1
        }
        throw Problem(description: "\(file):\(line): unterminated string literal")
    }

    /// Index after the `)` closing an interpolation that starts at `i`.
    private static func skipInterpolation(_ chars: [Character], at i: Int, file: String, line: Int) throws -> Int {
        var depth = 1
        var j = i
        while j < chars.count {
            if chars[j] == "\"" {
                j = try readLiteral(chars, at: j, file: file, line: line).1
                continue
            }
            if chars[j] == "(" { depth += 1 }
            if chars[j] == ")" { depth -= 1; if depth == 0 { return j + 1 } }
            j += 1
        }
        throw Problem(description: "\(file):\(line): unterminated interpolation")
    }
}
