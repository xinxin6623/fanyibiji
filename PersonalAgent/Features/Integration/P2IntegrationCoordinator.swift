import Foundation

/// P2 整合编排层（纯逻辑、可 headless 单测）。
///
/// 把 T04/T05/T06 的已验证编排件接成一条链：
///   入口路由（授权门）→ 区域选择 → 截屏 → OCR → 产出查询文本。
///
/// 边界（AGENTS 模块边界）：本类型**不**调用 LLM、**不**驱动 UI、
/// **不**碰真实屏幕/Vision——这些经注入的 `ScreenCaptureCoordinator`/
/// `OCRCoordinator` 与 UI 层 overlay 完成。本层只做"把图变成可查询文本"
/// 这一步的编排与统一错误分类，失败保持 `AgentError` 语义不被吞掉。
struct P2IntegrationCoordinator: Sendable {

    /// 一次截屏取词的产物：OCR 文本 + 结构化结果（供调用方落盘/调试）。
    struct CapturedText: Sendable, Equatable {
        let text: String
        let ocr: OCRResult
    }

    /// 区域选择的提供方。抽象成闭包便于单测注入（真实实现是 overlay 窗口，
    /// 属 UI 层；本层不依赖 AppKit）。
    typealias RegionProvider = @Sendable () async -> RegionSelection

    private let router: InputRouter
    private let capture: ScreenCaptureCoordinator
    private let ocr: OCRCoordinator

    init(router: InputRouter,
         capture: ScreenCaptureCoordinator,
         ocr: OCRCoordinator) {
        self.router = router
        self.capture = capture
        self.ocr = ocr
    }

    /// 截屏取词全链。任一环节失败按其 `AgentError` 语义原样返回
    /// （授权→`.permission`，取消→`.cancelled`，空文本→`.invalidInput`），
    /// 不二次包装、不静默降级。
    ///
    /// - Parameter selectRegion: 区域选择回调（UI overlay 注入）。
    func captureText(selectRegion: RegionProvider)
        async -> Result<CapturedText, AgentError> {

        // 1. 入口授权门（截屏入口需录屏/辅助功能授权）。
        switch router.route(.screenshot) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        // 2. 区域选择（UI overlay；用户 ESC/空拖拽 → cancelled）。
        let selection = await selectRegion()

        // 3. 截屏（授权再校验 + 取消 + 采集失败分类，复用 T05 协调器）。
        let shot: ScreenshotResult
        switch await capture.capture(selection) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            shot = result
        }

        // 4. OCR（空结果→.invalidInput，取消→.cancelled，复用 T06 协调器）。
        switch await ocr.recognize(imageData: shot.imageData) {
        case .failure(let error):
            return .failure(error)
        case .success(let ocrResult):
            return .success(CapturedText(text: ocrResult.fullText, ocr: ocrResult))
        }
    }
}
