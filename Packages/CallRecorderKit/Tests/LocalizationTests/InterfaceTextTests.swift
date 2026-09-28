import Foundation
import Testing

// The Mac app's interface is written in both languages side by side: tr("Итоги", "Summary"). A Russian literal
// anywhere else would show up untranslated in the English interface, so the app's sources are read here and
// every Russian string literal must be the first argument of tr(...). Texts only the developer reads (the
// problem report) are marked with forDeveloper(...).

/// The repository, found from this file's place in it.
private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // LocalizationTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // CallRecorderKit
    .deletingLastPathComponent() // Packages
    .deletingLastPathComponent()

private struct Literal {
    let line: Int
    let text: String
    /// The code just before the opening quote, without spaces and line breaks.
    let before: String
}

/// The string literals of Swift source, outside comments. Interpolations are skipped as a whole, so the quotes of
/// a literal inside `\( … )` do not end the outer one.
private func literals(in source: String) -> [Literal] {
    let characters = Array(source)
    var found: [Literal] = []
    var index = 0
    var line = 1

    func skipString(from start: Int) -> Int {
        // start is just after the opening quote; returns the index after the closing quote.
        var i = start
        while i < characters.count {
            let c = characters[i]
            if c == "\n" { line += 1 }
            if c == "\\", i + 1 < characters.count {
                if characters[i + 1] == "(" {
                    i = skipInterpolation(from: i + 2)
                    continue
                }
                i += 2
                continue
            }
            if c == "\"" { return i + 1 }
            i += 1
        }
        return i
    }

    func skipInterpolation(from start: Int) -> Int {
        var depth = 1
        var i = start
        while i < characters.count, depth > 0 {
            let c = characters[i]
            if c == "\"" {
                i = skipString(from: i + 1)
                continue
            }
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            if c == "\n" { line += 1 }
            i += 1
        }
        return i
    }

    while index < characters.count {
        let c = characters[index]
        if c == "\n" {
            line += 1
            index += 1
        } else if c == "/", index + 1 < characters.count, characters[index + 1] == "/" {
            while index < characters.count, characters[index] != "\n" { index += 1 }
        } else if c == "/", index + 1 < characters.count, characters[index + 1] == "*" {
            index += 2
            while index + 1 < characters.count, !(characters[index] == "*" && characters[index + 1] == "/") {
                if characters[index] == "\n" { line += 1 }
                index += 1
            }
            index += 2
        } else if c == "\"" {
            let startLine = line
            let isMultiline = index + 2 < characters.count && characters[index + 1] == "\"" && characters[index + 2] == "\""
            let before = String(characters[max(0, index - 80)..<index]).filter { !$0.isWhitespace }
            let end: Int
            if isMultiline {
                var i = index + 3
                while i + 2 < characters.count, !(characters[i] == "\"" && characters[i + 1] == "\"" && characters[i + 2] == "\"") {
                    if characters[i] == "\n" { line += 1 }
                    i += 1
                }
                end = min(characters.count, i + 3)
            } else {
                end = skipString(from: index + 1)
            }
            found.append(Literal(line: startLine, text: String(characters[index..<end]), before: before))
            index = end
        } else {
            index += 1
        }
    }
    return found
}

private func hasCyrillic(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
}

private func appSources() throws -> [URL] {
    let app = repository.appending(path: "CallRecorder/App")
    let enumerator = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}

@Test func theScannerSkipsInterpolationsAndComments() {
    let source = #"""
    // "Комментарий"
    let a = tr("Удалить «\(title ?? "")»?", "Delete “\(title ?? "")”?")
    let b = "Итоги"
    """#
    let russian = literals(in: source).filter { hasCyrillic($0.text) }
    #expect(russian.count == 2)
    #expect(russian[0].before.hasSuffix("tr("))
    #expect(russian[1].line == 3)
    #expect(!russian[1].before.hasSuffix("tr("))
}

@Test func everyRussianTextOfTheMacAppHasAnEnglishTwin() throws {
    let sources = try appSources()
    #expect(sources.count > 20, "the app's sources were not found at \(repository.path)")
    var untranslated: [String] = []
    for file in sources {
        let source = try String(contentsOf: file, encoding: .utf8)
        for literal in literals(in: source) where hasCyrillic(literal.text) {
            let allowed = literal.before.hasSuffix("tr(") || literal.before.hasSuffix("forDeveloper(")
                || literal.before.contains("plural(")
            if !allowed {
                untranslated.append("\(file.lastPathComponent):\(literal.line) \(literal.text.prefix(60))")
            }
        }
    }
    #expect(untranslated.isEmpty, "Russian text without an English version: \(untranslated.joined(separator: "; "))")
}
