import Foundation
import ApplicationServices

/// 辅助功能授权查询边界。抽象成协议便于单测注入授权/拒绝桩，
/// 不在测试中触碰真实系统授权状态。
protocol AccessibilityAuthorizing: Sendable {
    var isTrusted: Bool { get }
}

/// 生产实现：`AXIsProcessTrusted()`。不在此处弹系统对话框（避免单测/
/// headless 误触发），引导用户开启的 UI 文案在 View 层本地化。
struct SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
    var isTrusted: Bool { AXIsProcessTrusted() }
}

/// 单测桩。
struct StaticAccessibilityAuthorizer: AccessibilityAuthorizing {
    let isTrusted: Bool
}
