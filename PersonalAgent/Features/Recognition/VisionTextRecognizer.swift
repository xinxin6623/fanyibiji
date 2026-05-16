import Foundation
import Vision
import ImageIO

/// Apple Vision 文本识别薄适配（系统边界，不做单测；可测逻辑在
/// `OCRAssembler`/`OCRCoordinator`，类比 Keychain/SC 先例）。
/// 本地推理、无网络、无特殊权限；只识别不翻译。
struct VisionTextRecognizer: OCRRecognizing {

    func recognize(_ imageData: Data,
                   languageHints: [String]) async throws -> [OCRLine] {
        guard let source = CGImageSourceCreateWithData(
                imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "undecodable image")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    return continuation.resume(throwing: AgentError(
                        category: .unknown, diagnosticMessage: "vision failed"))
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [OCRLine] = observations.compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return OCRLine(text: top.string,
                                   confidence: Double(top.confidence),
                                   boundingBox: obs.boundingBox)
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if !languageHints.isEmpty {
                request.recognitionLanguages = languageHints
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: AgentError(
                    category: .unknown, diagnosticMessage: "vision handler failed"))
            }
        }
    }
}
