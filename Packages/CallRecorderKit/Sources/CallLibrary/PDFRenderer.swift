import Foundation
import Localization
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum PDFRendererError: LocalizedError {
    case unreadableDocument
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .unreadableDocument: tr("Не удалось подготовить документ для PDF.", "Could not prepare the document for the PDF.")
        case .emptyResult: tr("PDF получился пустым.", "The PDF came out empty.")
        }
    }
}

/// Turns the export HTML into an A4 PDF split into pages, with the system's own text layout.
@MainActor
public enum PDFRenderer {
    /// A4 in points.
    static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    static let margin: CGFloat = 48

    public static func pdf(fromHTML html: String) throws -> Data {
        #if canImport(UIKit)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        // UIPrintPageRenderer has no public setters for its page geometry; key-value coding is the documented way
        // to render it off-screen into a PDF.
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: margin, dy: margin), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        guard data.length > 0 else { throw PDFRendererError.emptyResult }
        return data as Data
        #elseif canImport(AppKit)
        guard let text = NSAttributedString(html: Data(html.utf8), documentAttributes: nil) else {
            throw PDFRendererError.unreadableDocument
        }
        let width = page.width - margin * 2
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: page.height))
        view.textStorage?.setAttributedString(text)
        view.isVerticallyResizable = true
        view.sizeToFit()

        let file = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        let info = NSPrintInfo()
        info.paperSize = page.size
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = file

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw PDFRendererError.emptyResult }
        let data = try Data(contentsOf: file)
        guard !data.isEmpty else { throw PDFRendererError.emptyResult }
        return data
        #endif
    }
}
