import Foundation

/// 把识别行整理成 TC `OCRResult`：纯逻辑、可 headless 单测。
/// fullText 按行拼接；overallConfidence 取行置信度均值（空→0）。
enum OCRAssembler {
    static func assemble(_ lines: [OCRLine],
                         languageHints: [String],
                         sourceImageRef: String?) -> OCRResult {
        let blocks = lines.map {
            OCRBlock(text: $0.text, boundingBox: $0.boundingBox,
                     confidence: $0.confidence)
        }
        let fullText = lines.map(\.text).joined(separator: "\n")
        let overall = lines.isEmpty
            ? 0
            : lines.map(\.confidence).reduce(0, +) / Double(lines.count)
        return OCRResult(
            fullText: fullText,
            overallConfidence: overall,
            blocks: blocks,
            languageHints: languageHints,
            sourceImageRef: sourceImageRef)
    }
}
