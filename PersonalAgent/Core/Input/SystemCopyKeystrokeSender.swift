import Foundation
import CoreGraphics

/// 生产实现：用 `CGEvent` 向系统合成 ⌘C 键盘事件。
///
/// 需辅助功能权限（"控制电脑"，与全局热键同一权限，已在
/// `GlobalHotkeyMonitor.start()` 处统一校验/引导，故此处不再重复检查）。
///
/// keyCode 8 = ANSI 'C'；通过 `.maskCommand` flag 带上 ⌘。事件注入到
/// `.cghidEventTap`，等价用户真实按键，前台应用据此执行复制。
struct SystemCopyKeystrokeSender: CopyKeystrokeSending {
    private static let keyC: CGKeyCode = 8

    func sendCopyKeystroke() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        // 取词期间屏蔽本地已存在的修饰键状态，避免用户当时按着的
        // 其它修饰键污染合成的 ⌘C。
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)

        guard let keyDown = CGEvent(keyboardEventSource: source,
                                    virtualKey: Self.keyC, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: Self.keyC, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
