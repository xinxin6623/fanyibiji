import Foundation

/// 输入入口类型：决定一次查询的取材来源，映射到 TC 契约的
/// `InputSourceKind`。`manualInput` 不依赖系统权限；`screenshot` /
/// `selection` 依赖辅助功能/录屏授权（实际采集在 P2 后续任务）。
enum InputEntry: String, Sendable, CaseIterable {
    case screenshot
    case selection
    case manualInput

    var sourceKind: InputSourceKind {
        switch self {
        case .screenshot:  return .screenshot
        case .selection:   return .selectedText
        case .manualInput: return .manualInput
        }
    }

    /// 是否需要系统授权（全局监听/辅助功能）才能采集。
    var requiresAuthorization: Bool {
        switch self {
        case .screenshot, .selection: return true
        case .manualInput:            return false
        }
    }
}
