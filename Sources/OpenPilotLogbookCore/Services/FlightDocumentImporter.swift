import AppKit
import Foundation
import PDFKit
import Vision

public enum FlightDocumentImporter {
    private static let maximumFiles = 25
    private static let maximumFileBytes = 52_428_800
    private static let maximumPDFPages = 200
    private static let maximumExtractedTextBytes = 10_485_760
    private static let maximumImagePixels = 50_000_000
    private static let maximumCandidates = 10_000

    public static func candidates(from urls: [URL], suggestions: SuggestionBundle) throws -> [ImportCandidate] {
        guard urls.count <= maximumFiles else {
            throw importError("Select no more than \(maximumFiles) documents at once.")
        }
        var candidates: [ImportCandidate] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= maximumFileBytes else {
                throw importError("\(url.lastPathComponent) is not a regular file within the 50 MiB import limit.")
            }
            let text = try extractText(from: url)
            guard text.utf8.count <= maximumExtractedTextBytes else {
                throw importError("\(url.lastPathComponent) produced more than 10 MiB of text.")
            }
            candidates.append(contentsOf: TextFlightParser.parseCandidates(from: text, suggestions: suggestions))
            guard candidates.count <= maximumCandidates else {
                throw importError("The selected documents contain more than \(maximumCandidates) candidate records.")
            }
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
        guard document.pageCount <= maximumPDFPages else {
            throw importError("\(url.lastPathComponent) contains more than \(maximumPDFPages) pages.")
        }
        var output: [String] = []
        var extractedBytes = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(text)
                extractedBytes += text.utf8.count
                guard extractedBytes <= maximumExtractedTextBytes else {
                    throw importError("\(url.lastPathComponent) produced more than 10 MiB of text.")
                }
                continue
            }
            let image = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
            let text = try recognizeText(in: image)
            output.append(text)
            extractedBytes += text.utf8.count
            guard extractedBytes <= maximumExtractedTextBytes else {
                throw importError("\(url.lastPathComponent) produced more than 10 MiB of text.")
            }
        }
        return output.joined(separator: "\n")
    }

    private static func recognizeText(in url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url) else { return "" }
        return try recognizeText(in: image)
    }

    private static func recognizeText(in image: NSImage) throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let (pixels, overflow) = cgImage.width.multipliedReportingOverflow(by: cgImage.height)
        guard !overflow, pixels <= maximumImagePixels else {
            throw importError("The selected image exceeds the 50-megapixel OCR limit.")
        }
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

    private static func importError(_ message: String) -> NSError {
        NSError(domain: "BlackboxDocumentImport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
