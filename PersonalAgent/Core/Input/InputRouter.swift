import Foundation

/// 输入入口路由：把 `InputEntry` 解析成可进入 P1 查询管线的来源类型，
/// 并在未授权时给出明确 `AgentError(.permission)`。纯逻辑、可 headless
/// 单测；不直接驱动 UI，也不自己发起查询（复用 `ContentQueryViewModel`）。
struct InputRouter: Sendable {
    private let authorizer: AccessibilityAuthorizing

    init(authorizer: AccessibilityAuthorizing) {
        self.authorizer = authorizer
    }

    /// 解析入口。需要授权的入口在未授权时返回 `.permission`，
    /// 调用方据此提示用户去系统设置开启（文案在 View 层本地化）。
    func route(_ entry: InputEntry) -> Result<InputSourceKind, AgentError> {
        if entry.requiresAuthorization && !authorizer.isTrusted {
            return .failure(AgentError(
                category: .permission,
                diagnosticMessage: "accessibility not authorized for \(entry.rawValue)"))
        }
        return .success(entry.sourceKind)
    }
}
