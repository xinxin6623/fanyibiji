import Foundation
import AppKit

/// 全局快捷键监听边界。抽象成协议便于单测注入桩（无法对真实
/// NSEvent 全局监听做确定性单测，桩手动触发回调验证路由）。
protocol HotkeyMonitoring: AnyObject {
    var onTrigger: (() -> Void)? { get set }
    /// 未授权时抛 `AgentError(.permission)`。
    func start() throws
    func stop()
}

/// 生产实现：NSEvent 全局 + 应用内监听。
///
/// 注意（诚实范围）：NSEvent 全局监听是**非独占**的，无法真正"注册"
/// 系统级快捷键，也无法检测与其它 App 的快捷键冲突——冲突检测需
/// Carbon `RegisterEventHotKey`，按 James 决策本任务用 NSEvent，
/// 冲突检测推迟。本类型只做监听与授权失败提示。
final class GlobalHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    var onTrigger: (() -> Void)?

    private let authorizer: AccessibilityAuthorizing
    private var globalToken: Any?
    private var localToken: Any?

    /// 默认快捷键：⌘⇧A（可配置 UI 属后续任务）。
    private let requiredModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private let requiredKey = "a"

    init(authorizer: AccessibilityAuthorizing) {
        self.authorizer = authorizer
    }

    func start() throws {
        guard authorizer.isTrusted else {
            throw AgentError(category: .permission,
                             diagnosticMessage: "accessibility not authorized for hotkey")
        }
        stop()
        globalToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        // 应用内事件不会被全局监听捕获，需本地监听并回传事件以不吞键。
        localToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalToken { NSEvent.removeMonitor(globalToken) }
        if let localToken { NSEvent.removeMonitor(localToken) }
        globalToken = nil
        localToken = nil
    }

    deinit { stop() }

    private func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(requiredModifiers),
              event.charactersIgnoringModifiers?.lowercased() == requiredKey else {
            return
        }
        onTrigger?()
    }
}
