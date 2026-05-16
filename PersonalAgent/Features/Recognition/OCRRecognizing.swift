import Foundation

/// 单行识别结果（Vision 原始产物的中性表示，归一化坐标）。
struct OCRLine: Sendable, Equatable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect
}

/// OCR 识别边界。抽象成协议便于单测注入桩，真实识别走 Vision 薄适配
/// （不在单测触碰 Vision/真实图片）。OCR 层只识别，不做翻译（AGENTS）。
protocol OCRRecognizing: Sendable {
    func recognize(_ imageData: Data, languageHints: [String]) async throws -> [OCRLine]
}
