import Foundation
import AppKit

/// 剪贴板读取边界。抽象成协议便于单测注入桩，不在测试触碰系统剪贴板。
///
/// MVP 取词策略：只读当前剪贴板兜底，不模拟 ⌘C、不写回——天然不破坏
/// 用户剪贴板（AGENTS「取词不能永久破坏用户剪贴板」）。
/// Accessibility/AppleScript/模拟复制属正式版，按看板 T08 备注推迟。
protocol PasteboardReading: Sendable {
    func readString() -> String?
}

/// 生产实现：`NSPasteboard.general` 只读。
struct SystemPasteboard: PasteboardReading {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
