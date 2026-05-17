import Foundation
import AppKit

/// 全局快捷键监听边界。抽象成协议便于单测注入桩（无法对真实
/// NSEvent 全局监听做确定性单测，桩手动触发回调验证路由）。
///
/// 两路独立回调：划词翻译 / 截屏 OCR。绑定可经 `update(_:)` 热重载
/// （用户在设置里改快捷键后立即生效，无需重启）。
protocol HotkeyMonitoring: AnyObject {
    var onTranslateSelection: (() -> Void)? { get set }
    var onCaptureOCR: (() -> Void)? { get set }
    /// 划词进草稿：取选中文字 → 原文追加到当前草稿 Tab。
    var onSelectionToNote: (() -> Void)? { get set }
    /// 未授权时抛 `AgentError(.permission)`。
    func start() throws
    func stop()
    /// 热重载绑定（设置变更后调用，无需重启 App）。
    func update(_ config: HotkeyConfig)
}

/// 生产实现：NSEvent 全局 + 应用内监听。
///
/// 注意（诚实范围）：NSEvent 全局监听是**非独占**的，无法真正"注册"
/// 系统级快捷键，也无法检测与其它 App 的快捷键冲突——冲突检测需
/// Carbon `RegisterEventHotKey`，按既有决策本项目用 NSEvent，冲突
/// 检测推迟。本类型只做监听、分派与授权失败提示。
///
/// 绑定由 `HotkeyConfig` 注入并可热重载；默认值见 `HotkeyConfig()`
/// （划词 ⌘⇧C、截屏 OCR ⌘⇧D）。
final class GlobalHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    var onTranslateSelection: (() -> Void)?
    var onCaptureOCR: (() -> Void)?
    var onSelectionToNote: (() -> Void)?

    private let authorizer: AccessibilityAuthorizing
    private var globalToken: Any?
    private var localToken: Any?
    private var config: HotkeyConfig
    private let lock = NSLock()

    init(authorizer: AccessibilityAuthorizing,
         config: HotkeyConfig = HotkeyConfig()) {
        self.authorizer = authorizer
        self.config = config
    }

    func update(_ config: HotkeyConfig) {
        lock.lock()
        self.config = config
        lock.unlock()
    }

    func start() throws {
        var trusted = authorizer.isTrusted
        if !trusted {
            // 主动弹系统授权对话框并登记当前二进制（被动 isTrusted
            // 对开发期未正式签名构建常持续 false，主动 prompt 更可靠）。
            trusted = authorizer.promptIfNeeded()
        }
        guard trusted else {
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
        lock.lock()
        let cfg = config
        lock.unlock()

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 截屏 OCR 优先匹配（保持历史 ⌘⇧D 行为稳定）；两组绑定相同时
        // 截屏 OCR 胜出，但 sanitize/UI 应避免用户配重复绑定。
        if matches(event, mods: mods, binding: cfg.captureOCR) {
            onCaptureOCR?()
            return
        }
        if matches(event, mods: mods, binding: cfg.selectionToNote) {
            onSelectionToNote?()
            return
        }
        if matches(event, mods: mods, binding: cfg.translateSelection) {
            onTranslateSelection?()
        }
    }

    private func matches(_ event: NSEvent,
                         mods: NSEvent.ModifierFlags,
                         binding: KeyBinding) -> Bool {
        event.keyCode == binding.keyCode && mods == binding.modifierFlags
    }
}
