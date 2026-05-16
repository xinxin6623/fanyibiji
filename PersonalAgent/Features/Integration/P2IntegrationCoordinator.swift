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

    private let screenAuth: ScreenCaptureAuthorizing
    private let capture: ScreenCaptureCoordinator
    private let ocr: OCRCoordinator

    /// 注意（职责归位）：截屏链**只**依赖录屏权限
    /// （`CGPreflightScreenCaptureAccess`），不再经 `InputRouter` 的辅助
    /// 功能门——辅助功能（`AXIsProcessTrusted`）仅全局热键 `⌘⇧D` 需要，
    /// 由 `GlobalHotkeyMonitor.start()` 单独检查；按钮触发截屏不需要
    /// "控制电脑"权限。此前把 T04 的热键入口门套在截屏链上是接线缺陷。
    init(screenAuth: ScreenCaptureAuthorizing,
         capture: ScreenCaptureCoordinator,
         ocr: OCRCoordinator) {
        self.screenAuth = screenAuth
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

        // 1. 录屏授权门。首次未授权时主动 requestAccess() 触发系统授权
        //    对话框（协调器自身纯逻辑不弹窗，故在此显式触发，给用户授权
        //    机会而非直接死在 .permission）。授权后本进程仍需重启才生效
        //    （macOS 录屏权限硬限制），故仍返回 .permission 引导用户。
        if !screenAuth.isAuthorized {
            _ = screenAuth.requestAccess()
            return .failure(AgentError(
                category: .permission,
                diagnosticMessage: "screen recording not authorized"))
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
