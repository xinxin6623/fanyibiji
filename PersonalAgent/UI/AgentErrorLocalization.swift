import SwiftUI

// category → 本地化文案键的唯一映射。放 UI 层（LocalizedStringKey 属 SwiftUI，
// 不能进 Core 模型层污染分层）。所有展示错误的 View 共用，新增 Category 只改这里。
extension AgentError.Category {
    var localizationKey: LocalizedStringKey {
        switch self {
        case .invalidInput:     return "error.invalid_input"
        case .network:          return "error.network"
        case .timeout:          return "error.timeout"
        case .cancelled:        return "error.cancelled"
        case .permission:       return "error.permission"
        case .persistence:      return "error.persistence"
        case .providerRejected: return "error.provider_rejected"
        case .unknown:          return "error.unknown"
        }
    }
}
