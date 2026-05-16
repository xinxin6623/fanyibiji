import Foundation
import ApplicationServices

/// 辅助功能授权查询边界。抽象成协议便于单测注入授权/拒绝桩，
/// 不在测试中触碰真实系统授权状态。
protocol AccessibilityAuthorizing: Sendable {
    var isTrusted: Bool { get }
    /// 主动检查并在未授权时弹系统授权对话框（同时把当前二进制登记进
    /// 辅助功能列表）。返回当下是否已授权。
    @discardableResult
    func promptIfNeeded() -> Bool
}

/// 生产实现。`isTrusted` 用被动 `AXIsProcessTrusted()`（零副作用，
/// 供单测/headless 安全调用）。`promptIfNeeded()` 用
/// `AXIsProcessTrustedWithOptions(.. prompt: true)`：开发期未正式签名
/// 的 App 被动检查常持续返回 false，主动 prompt 会弹系统对话框并把
/// 当前签名二进制正确登记到辅助功能列表，比被动检查可靠。
struct SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func promptIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// 单测桩。
struct StaticAccessibilityAuthorizer: AccessibilityAuthorizing {
    let isTrusted: Bool
    @discardableResult
    func promptIfNeeded() -> Bool { isTrusted }
}
