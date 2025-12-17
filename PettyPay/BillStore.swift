import Foundation
import SwiftUI
import Vision
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine

@MainActor
final class BillStore: ObservableObject {
    struct BillItem: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var price: Decimal?
        var isSelected: Bool = true
        var quantity: Int = 1
        var assignedPeople: Set<UUID> = []
    }

    @Published var items: [BillItem] = []
    @Published var isAnalyzing: Bool = false
    @Published var lastError: String?
    @Published var billImage: UIImage?

    // Toggle preprocessing if your receipts are dim/low-contrast
    private let enablePreprocessing: Bool = true

    func reset() {
        items = []
        lastError = nil
    }

    func analyze(image: UIImage) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Keep for header card
        self.billImage = image

        guard let cgImage = (enablePreprocessing ? preprocess(image) : image).cgImage else {
            lastError = "Could not read image."
            return
        }

        // Accurate first for fidelity, then fallback to fast if nothing found
        let accurateLines = recognizeLines(cgImage: cgImage, level: .accurate, correction: true, orientation: image.cgImageOrientation)
        var result = parseAcceptablePriceLines(from: accurateLines)

        if result.isEmpty {
            let fastLines = recognizeLines(cgImage: cgImage, level: .fast, correction: false, orientation: image.cgImageOrientation)
            result = parseAcceptablePriceLines(from: fastLines)
        }

        if result.isEmpty {
            lastError = "No items with prices found. Try a closer, flatter shot with good light."
        } else {
            lastError = nil
        }

        self.items = result
    }

    // MARK: - Preprocess

    private func preprocess(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // 1) Grayscale
        let mono = CIFilter.colorControls()
        mono.inputImage = ciImage
        mono.saturation = 0.0
        mono.contrast = 1.1
        mono.brightness = 0.0

        // 2) Local contrast enhancement (unsharp mask-like)
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = mono.outputImage
        sharpen.radius = 1.5
        sharpen.intensity = 0.6

        // 3) Slight exposure boost
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = sharpen.outputImage
        exposure.ev = 0.2

        guard let out = exposure.outputImage,
              let cg = context.createCGImage(out, from: out.extent) else {
            return image
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Vision

    private func recognizeLines(cgImage: CGImage,
                                level: VNRequestTextRecognitionLevel,
                                correction: Bool,
                                orientation: CGImagePropertyOrientation) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = correction
        // Slightly higher than default to cut noise on receipts
        request.minimumTextHeight = 0.012
        // Prioritize Italian, then English variants. Adjust to your locale.
        request.recognitionLanguages = ["it_IT", "en_US", "en_GB"]

        // If you frequently get headers/footers noise, you can set regionOfInterest here.
        // request.regionOfInterest = CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.8)

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            self.lastError = "Vision failed: \(error.localizedDescription)"
            return []
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else { return [] }

        // Group recognized text by approximate line using bounding boxes
        struct LineBucket {
            var yCenter: CGFloat
            var pieces: [(x: CGFloat, text: String)]
        }

        var buckets: [LineBucket] = []

        func addToBucket(text: String, bbox: CGRect) {
            let yCenter = bbox.midY
            let xCenter = bbox.minX
            // Find a bucket with similar y
            if let idx = buckets.firstIndex(where: { abs($0.yCenter - yCenter) < 0.02 }) {
                buckets[idx].pieces.append((x: xCenter, text: text))
                // Recompute yCenter average for stability
                let newY = (buckets[idx].yCenter + yCenter) / 2
                buckets[idx].yCenter = newY
            } else {
                buckets.append(LineBucket(yCenter: yCenter, pieces: [(x: xCenter, text: text)]))
            }
        }

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            addToBucket(text: text, bbox: obs.boundingBox)
        }

        // Sort buckets by vertical position (top to bottom), and pieces left to right
        let lines: [String] = buckets
            .sorted(by: { $0.yCenter > $1.yCenter }) // Vision bbox y=1 top, 0 bottom; invert for top->bottom
            .map { bucket in
                bucket.pieces
                    .sorted(by: { $0.x < $1.x })
                    .map(\.text)
                    .joined(separator: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        return lines
    }

    // MARK: - Parsing

    private func parseAcceptablePriceLines(from lines: [String]) -> [BillItem] {
        var result: [BillItem] = []
        result.reserveCapacity(lines.count)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if isHeaderOrTotal(line) { continue }

            if let (name, price) = acceptPriceLine(line) {
                let cleaned = prettifyName(cleanName(name))
                guard !cleaned.isEmpty else { continue }
                result.append(BillItem(name: cleaned, price: price, isSelected: true, quantity: 1, assignedPeople: []))
            }
        }
        return result
    }

    private func isHeaderOrTotal(_ line: String) -> Bool {
        let lower = line.lowercased()

        // Skip obvious totals and payments
        if lower.contains("subtotal") || lower.contains("total") || lower.contains("totale") { return true }
        if lower.contains("change") || lower.contains("cash") || lower.contains("card") { return true }
        if lower.contains("visa") || lower.contains("mastercard") || lower.contains("amex") { return true }
        if lower.contains("tip") || lower.contains("gratuity") { return true }
        if lower.contains("tendered") || lower.contains("paid") { return true }
        // Common headers
        if lower.contains("date") || lower.contains("time") || lower.contains("invoice") || lower.contains("receipt") { return true }
        if lower.contains("fiscal") || lower.contains("p.iva") || lower.contains("partita iva") { return true }

        return false
    }

    // Improved price detection:
    // - Accepts €7,90 / € 7,90 / 7,90€ / 7,90 € / EUR 7,90 / 7.90 etc.
    // - Ignores IVA/VAT and percent lines
    private func acceptPriceLine(_ line: String) -> (name: String, price: Decimal)? {
        let tokens = tokenize(line)

        func isEuroMarkerToken(_ s: String) -> Bool {
            let l = s.lowercased()
            return l == "eur" || l == "euro" || l == "eu" || s.contains("€")
        }
        func isPriceWordMarker(_ s: String) -> Bool {
            let l = s.lowercased()
            return l == "prezzo" || l == "price" || l == "cost" || l == "tot." || l == "total" || l == "totale"
        }
        func isAnyMarker(_ s: String) -> Bool {
            isEuroMarkerToken(s) || isPriceWordMarker(s)
        }
        func isIvaWord(_ s: String) -> Bool {
            let l = s.lowercased()
            return l.hasPrefix("iva") || l == "vat" || l.contains("imposta")
        }
        func isPercentToken(_ s: String) -> Bool {
            s.range(of: #"^\d{1,2}%$"#, options: .regularExpression) != nil
        }
        func normalizeNumber(_ s: String) -> String? {
            // Keep digits, comma, dot, minus; drop everything else
            let cleaned = s.replacingOccurrences(of: "[^0-9.,-]", with: "", options: .regularExpression)
            guard !cleaned.isEmpty else { return nil }
            // Convert comma decimals to dot, but keep thousands reasonably
            if cleaned.contains(",") && !cleaned.contains(".") {
                return cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                return cleaned.replacingOccurrences(of: ",", with: "")
            }
        }
        func parseDecimal(_ s: String) -> Decimal? {
            guard let norm = normalizeNumber(s) else { return nil }
            if norm.filter({ $0 == "." }).count > 1 { return nil }
            return Decimal(string: norm)
        }

        // Helper: determine if token is likely an IVA number (e.g., “IVA 10,00”, “VAT 4,00”, “10%”)
        func isLikelyIvaNumber(at idx: Int) -> Bool {
            if idx > 0, isIvaWord(tokens[idx - 1]) { return true }
            if idx + 1 < tokens.count, isIvaWord(tokens[idx + 1]) { return true }
            if isPercentToken(tokens[idx]) { return true }
            // Also patterns like "IVA: 10,00" or "10,00 IVA"
            if tokens[idx].contains("%") { return true }
            return false
        }

        // Strong patterns: token containing € glued to number
        for (i, t) in tokens.enumerated() where t.contains("€") {
            let num = t.replacingOccurrences(of: "€", with: "")
            if let price = parseDecimal(num), !isLikelyIvaNumber(at: i) {
                var nameTokens = tokens
                nameTokens.remove(at: i)
                nameTokens.removeAll(where: isEuroMarkerToken)
                if nameTokens.joined(separator: " ").range(of: "[A-Za-z]", options: .regularExpression) != nil {
                    return (nameTokens.joined(separator: " "), price)
                }
            }
        }

        // Neighboring euro marker + number or number + euro marker
        for i in tokens.indices {
            let t = tokens[i]
            if isEuroMarkerToken(t) || isPriceWordMarker(t) {
                if i + 1 < tokens.count, let price = parseDecimal(tokens[i + 1]), !isLikelyIvaNumber(at: i + 1) {
                    var nameTokens = tokens
                    nameTokens.remove(at: i + 1)
                    nameTokens.remove(at: i)
                    if nameTokens.joined(separator: " ").range(of: "[A-Za-z]", options: .regularExpression) != nil {
                        return (nameTokens.joined(separator: " "), price)
                    }
                }
                if i > 0, let price = parseDecimal(tokens[i - 1]), !isLikelyIvaNumber(at: i - 1) {
                    var nameTokens = tokens
                    nameTokens.remove(at: i)
                    nameTokens.remove(at: i - 1)
                    if nameTokens.joined(separator: " ").range(of: "[A-Za-z]", options: .regularExpression) != nil {
                        return (nameTokens.joined(separator: " "), price)
                    }
                }
            }
        }

        // Fallback: last numeric token as price (ignore IVA-like numbers)
        if let idx = tokens.indices.reversed().first(where: { parseDecimal(tokens[$0]) != nil && !isLikelyIvaNumber(at: $0) }) {
            if let price = parseDecimal(tokens[idx]) {
                if line.range(of: "[A-Za-z]", options: .regularExpression) != nil {
                    var nameTokens = tokens
                    nameTokens.remove(at: idx)
                    nameTokens.removeAll(where: isAnyMarker)
                    return (nameTokens.joined(separator: " "), price)
                }
            }
        }

        return nil
    }

    private func tokenize(_ line: String) -> [String] {
        line
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
    }

    // MARK: - Cleanup

    private func cleanName(_ name: String) -> String {
        var tokens = name
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }

        func isMarker(_ t: String) -> Bool {
            let l = t.lowercased()
            return l == "eur" || l == "euro" || l == "eu" || l == "price" || l == "cost" || l == "prezzo" || l == "tot." || l == "total" || l == "totale" || t.contains("€")
        }
        func isQtyMarker(_ t: String) -> Bool {
            let l = t.lowercased()
            if l.hasPrefix("x"), Int(l.dropFirst()) != nil { return true }
            if l.hasSuffix("x"), Int(l.dropLast()) != nil { return true }
            return false
        }
        func isCodeLike(_ t: String) -> Bool {
            // Very short or mostly digits with punctuation, but keep common words
            if t.count <= 1 { return true }
            let digits = t.filter(\.isNumber).count
            return digits > 0 && digits >= t.count - 2
        }

        tokens.removeAll { isMarker($0) || isQtyMarker($0) || isCodeLike($0) }

        let joined = tokens.joined(separator: " ")
        let collapsed = joined.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private func prettifyName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Helpers

private extension UIImage {
    // Map UIImageOrientation to CGImagePropertyOrientation for Vision
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
