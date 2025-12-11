import Foundation
import SwiftUI
import Vision
import UIKit
import Combine

@MainActor
final class BillStore: ObservableObject {
    struct BillItem: Identifiable, Hashable {
        let id = UUID()
        var name: String
        // Treat price as unit price
        var price: Decimal?
        var isSelected: Bool = true
        var quantity: Int = 1
        // People assigned to this item (Person.id values)
        var assignedPeople: Set<UUID> = []
    }

    @Published var items: [BillItem] = []
    @Published var isAnalyzing: Bool = false
    @Published var lastError: String?
    @Published var billImage: UIImage?

    func reset() {
        items = []
        lastError = nil
        // Keep billImage
    }

    func analyze(image: UIImage) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let cgImage = image.cgImage else {
            lastError = "Could not read image."
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01
        request.recognitionLanguages = ["en_US", "en_GB"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            lastError = "Vision failed: \(error.localizedDescription)"
            return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            lastError = "No text found."
            return
        }

        // Extract top candidate strings per line
        var lines: [String] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            lines.append(text)
        }

        // Basic filtering: remove obvious headers or totals
        let filtered = lines.filter { line in
            let lower = line.lowercased()
            if line.count < 2 { return false }
            // Skip totals/subtotals/tax
            if lower.contains("subtotal") || lower.contains("total") || lower.contains("tax") {
                return false
            }
            // Skip lines that are mostly separators or codes
            if lower.contains("visa") || lower.contains("mastercard") || lower.contains("amex") {
                return false
            }
            return true
        }

        // Parse and aggregate by (normalizedName, unitPrice)
        var order: [(String, Decimal?)] = [] // preserves first-seen order of unique keys
        var bucket: [AggregationKey: AggregationValue] = [:]

        for line in filtered {
            let parsed = parseLineForNamePriceQuantity(line)
            guard !parsed.name.isEmpty else { continue }

            let key = AggregationKey(nameKey: normalizeName(parsed.name), unitPrice: parsed.price)
            if bucket[key] == nil {
                order.append((parsed.name, parsed.price))
                bucket[key] = AggregationValue(displayName: parsed.name, unitPrice: parsed.price, quantity: parsed.quantity)
            } else {
                bucket[key]!.quantity += parsed.quantity
            }
        }

        // Build items preserving first-seen order
        var result: [BillItem] = []
        result.reserveCapacity(order.count)
        for (displayNameCandidate, unitPrice) in order {
            let key = AggregationKey(nameKey: normalizeName(displayNameCandidate), unitPrice: unitPrice)
            if let agg = bucket[key] {
                result.append(
                    BillItem(
                        name: prettifyName(agg.displayName),
                        price: agg.unitPrice,
                        isSelected: true,
                        quantity: max(1, agg.quantity),
                        assignedPeople: []
                    )
                )
            }
        }

        // If nothing parsed, surface a gentle error
        if result.isEmpty {
            lastError = "Couldn’t parse any items. Try cropping tighter around the receipt body."
        } else {
            lastError = nil
        }

        self.items = result
    }

    // MARK: - Aggregation

    private struct AggregationKey: Hashable {
        let nameKey: String
        let unitPrice: Decimal?
    }

    private struct AggregationValue {
        var displayName: String
        var unitPrice: Decimal?
        var quantity: Int
    }

    // MARK: - Parsing helpers

    // Returns a tuple with normalized name, unit price (if found), and quantity (>=1)
    private func parseLineForNamePriceQuantity(_ line: String) -> (name: String, price: Decimal?, quantity: Int) {
        // Tokenize by spaces
        let rawTokens = line
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .map { String($0) }

        // Try to find a price-like token anywhere; prefer last plausible token
        let priceIndex: Int? = rawTokens.indices.reversed().first { idx in
            priceFromToken(rawTokens[idx]) != nil
        }
        let unitPrice: Decimal? = priceIndex.flatMap { priceFromToken(rawTokens[$0]) }

        // Detect quantity patterns in tokens (x2, 2x, qty 2, 2 pcs, etc.)
        let detectedQty = detectQuantity(in: rawTokens)
        let quantity = max(1, detectedQty ?? 1)

        // Build name tokens by removing price token and common qty tokens
        var nameTokens: [String] = []
        for (idx, tok) in rawTokens.enumerated() {
            if let pIdx = priceIndex, idx == pIdx { continue } // exclude price token
            if isQuantityToken(tok) { continue }               // exclude qty token itself
            nameTokens.append(tok)
        }

        let name = nameTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return (name: name, price: unitPrice, quantity: quantity)
    }

    // Quantity detection across tokens
    private func detectQuantity(in tokens: [String]) -> Int? {
        // Patterns:
        // - x2 or X2
        // - 2x or 2X
        // - qty 2, qty:2, q:2
        // - 2 pcs, 2 pc, 2pk, 2pk.
        // - a bare leading integer may be quantity if followed by text (heuristic)
        let lower = tokens.map { $0.lowercased() }

        // Direct forms like x2 / 2x
        for tok in lower {
            if let q = parseXQuantity(tok) { return q }
        }

        // qty forms
        for i in 0..<lower.count {
            let tok = lower[i]
            if tok == "qty" || tok == "qty:" || tok == "q" || tok == "q:" {
                if i + 1 < lower.count, let q = Int(lower[i + 1].filter(\.isNumber)), q > 0 {
                    return q
                }
            } else if tok.hasPrefix("qty") || tok.hasPrefix("q:") || tok.hasPrefix("qty:") {
                if let q = Int(tok.filter(\.isNumber)), q > 0 { return q }
            }
        }

        // pc/pcs/pk forms
        for i in 0..<lower.count {
            if let q = Int(lower[i].filter(\.isNumber)), q > 0, i + 1 < lower.count {
                let next = lower[i + 1].trimmingCharacters(in: .punctuationCharacters)
                if ["pc", "pcs", "pk", "pk.", "pack"].contains(next) {
                    return q
                }
            }
        }

        // Heuristic: leading integer quantity like "2 Burger 7.99"
        if let first = lower.first, let q = Int(first.filter(\.isNumber)), q > 0, lower.count >= 2 {
            // Avoid cases where first token is actually a price (contains '.' and two decimals)
            if priceFromToken(first) == nil {
                return q
            }
        }

        return nil
    }

    private func parseXQuantity(_ token: String) -> Int? {
        // x2, X2, 2x, 2X
        let t = token.lowercased()
        if t.hasPrefix("x") {
            if let q = Int(t.dropFirst().filter(\.isNumber)), q > 0 { return q }
        }
        if t.hasSuffix("x") {
            if let q = Int(t.dropLast().filter(\.isNumber)), q > 0 { return q }
        }
        return nil
    }

    private func isQuantityToken(_ token: String) -> Bool {
        let t = token.lowercased()
        if t == "qty" || t == "qty:" || t == "q" || t == "q:" { return true }
        if t.hasPrefix("qty") || t.hasPrefix("q:") { return true }
        // tokens like x2 / 2x are quantity markers; keep them out of the name
        if parseXQuantity(t) != nil { return true }
        // tokens that are just a count and then a unit marker will be filtered in detect stage
        return false
    }

    private func priceFromToken(_ token: String) -> Decimal? {
        // Strip currency symbols and non-numeric except dot/comma/minus
        let cleaned = token.replacingOccurrences(of: "[^0-9.,-]", with: "", options: .regularExpression)
        if cleaned.isEmpty { return nil }

        // Normalize comma as thousands separator; keep last dot as decimal separator
        // e.g., "1,234.50" -> "1234.50", "12,34" -> "1234" (best effort)
        let noCommas = cleaned.replacingOccurrences(of: ",", with: "")
        // Require at least one digit
        guard noCommas.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }

        // Heuristic: price should have at most one '.'; allow pure integers as well
        let dotCount = noCommas.filter { $0 == "." }.count
        if dotCount > 1 { return nil }

        return Decimal(string: noCommas)
    }

    private func normalizeName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prettifyName(_ name: String) -> String {
        // Trim and collapse whitespace; keep original case
        name
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

