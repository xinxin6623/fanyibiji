import Foundation

/// OCR 纯编排：识别 → 空结果判定 → 整理成 `OCRResult`。可 headless
/// 单测；不做翻译、不调用 LLM（AGENTS 模块边界）。
///
/// 失败可区分：取消→`.cancelled`，空结果→`.invalidInput`，其它→
/// `.unknown`。低置信度不算失败——成功返回，调用方据
/// `overallConfidence` 自行判断（保留信息而非吞掉）。
struct OCRCoordinator: Sendable {
    private let recognizer: OCRRecognizing

    init(recognizer: OCRRecognizing) {
        self.recognizer = recognizer
    }

    func recognize(imageData: Data,
                    languageHints: [String] = [],
                    sourceImageRef: String? = nil)
        async -> Result<OCRResult, AgentError> {
        let lines: [OCRLine]
        do {
            lines = try await recognizer.recognize(
                imageData, languageHints: languageHints)
        } catch let error as AgentError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(AgentError(category: .cancelled,
                                       diagnosticMessage: "ocr cancelled"))
        } catch {
            return .failure(AgentError(category: .unknown,
                                       diagnosticMessage: "ocr failed"))
        }

        let nonEmpty = lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !nonEmpty.isEmpty else {
            return .failure(AgentError(category: .invalidInput,
                                       diagnosticMessage: "no text recognized"))
        }
        return .success(OCRAssembler.assemble(
            nonEmpty, languageHints: languageHints, sourceImageRef: sourceImageRef))
    }
}
