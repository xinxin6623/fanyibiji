import Foundation

struct OCRBlock: Codable, Sendable, Equatable {
    let text: String
    let boundingBox: CGRect
    let confidence: Double
}

struct OCRResult: Codable, Sendable, Equatable {
    let fullText: String
    let overallConfidence: Double
    let blocks: [OCRBlock]
    let languageHints: [String]
    let sourceImageRef: String?

    init(
        fullText: String,
        overallConfidence: Double,
        blocks: [OCRBlock] = [],
        languageHints: [String] = [],
        sourceImageRef: String? = nil
    ) {
        self.fullText = fullText
        self.overallConfidence = overallConfidence
        self.blocks = blocks
        self.languageHints = languageHints
        self.sourceImageRef = sourceImageRef
    }
}
