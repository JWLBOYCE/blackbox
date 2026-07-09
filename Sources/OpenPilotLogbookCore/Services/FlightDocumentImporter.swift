import AppKit
import Foundation
import PDFKit
import Vision

public enum FlightDocumentImporter {
    public static func candidates(from urls: [URL], suggestions: SuggestionBundle) throws -> [ImportCandidate] {
        var candidates: [ImportCandidate] = []
        for url in urls {
            let text = try extractText(from: url)
            candidates.append(contentsOf: TextFlightParser.parseCandidates(from: text, suggestions: suggestions))
        }
        return candidates
    }

    private static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try extractPDFText(from: url)
        }
        if ["png", "jpg", "jpeg", "heic", "tiff"].contains(ext) {
            return try recognizeText(in: url)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var output: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(text)
                continue
            }
            let image = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
            output.append(try recognizeText(in: image))
        }
        return output.joined(separator: "\n")
    }

    private static func recognizeText(in url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url) else { return "" }
        return try recognizeText(in: image)
    }

    private static func recognizeText(in image: NSImage) throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-GB", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
