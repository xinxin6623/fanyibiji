import Foundation

/// 区域选择结果。UI 把退化/空拖拽（`CaptureRegion` 构造失败）映射为
/// `.cancelled`，因此协调器无需单独的"空区域"分支。
enum RegionSelection: Sendable, Equatable {
    case selected(CaptureRegion)
    case cancelled
}

/// 截屏纯编排：授权门 → 取消语义 → 调用采集适配。可 headless 单测；
/// 不直接驱动 UI，不调用 LLM/OCR（AGENTS 模块边界）。
struct ScreenCaptureCoordinator: Sendable {
    private let authorizer: ScreenCaptureAuthorizing
    private let capturer: ScreenCapturer

    init(authorizer: ScreenCaptureAuthorizing, capturer: ScreenCapturer) {
        self.authorizer = authorizer
        self.capturer = capturer
    }

    func capture(_ selection: RegionSelection)
        async -> Result<ScreenshotResult, AgentError> {
        guard authorizer.isAuthorized else {
            return .failure(AgentError(
                category: .permission,
                diagnosticMessage: "screen recording not authorized"))
        }
        switch selection {
        case .cancelled:
            return .failure(AgentError(
                category: .cancelled,
                diagnosticMessage: "region selection cancelled"))
        case let .selected(region):
            do {
                return .success(try await capturer.capture(region))
            } catch let error as AgentError {
                return .failure(error)
            } catch {
                return .failure(AgentError(
                    category: .unknown, diagnosticMessage: "capture failed"))
            }
        }
    }
}
