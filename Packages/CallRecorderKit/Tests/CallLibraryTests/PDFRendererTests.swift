import Foundation
import Testing
@testable import CallLibrary

@MainActor
@Test func aLongExportBecomesAMultiPagePDF() throws {
    let lines = (0..<400).map { "<p>Строка \($0): длинный текст разговора, который не помещается на одну страницу.</p>" }
    let html = "<!DOCTYPE html><html><body><h1>Созвон</h1>\(lines.joined())</body></html>"

    let data = try PDFRenderer.pdf(fromHTML: html)

    #expect(data.starts(with: Data("%PDF".utf8)))
    let pages = String(decoding: data, as: UTF8.self).components(separatedBy: "/Type /Page").count - 1
    #expect(pages > 1)
}
