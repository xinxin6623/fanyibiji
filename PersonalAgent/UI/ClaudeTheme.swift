import SwiftUI

/// Claude 经典配色（集中一处，主窗口统一引用）。
///
/// 取自 Claude / Anthropic 桌面端观感：暖米白底 + 赤陶橙强调 +
/// 近白卡片 + 低对比暖灰分隔。所有 hex 在此定义，View 层不再散落
/// 魔法色值（改主题只动这一个文件）。深色模式暂沿用同一组（产品
/// 当前只跑浅色；后续要适配再按 colorScheme 分支）。
enum ClaudeTheme {

    /// 赤陶橙——主强调色（按钮 tint、选中态、进度条）。
    static let accent = Color(hex: 0xC96442)

    /// 窗口/页面底色——暖米白。
    static let background = Color(hex: 0xFAF9F5)

    /// 卡片与可编辑区底色——近白（比 background 略亮，制造分层）。
    static let card = Color(hex: 0xFFFFFF)

    /// 分隔线 / 可拖动分隔条——低对比暖灰。
    static let separator = Color(hex: 0xE5E2D9)

    /// 次要文字（提示、占位、时间戳）——暖中灰。
    static let secondaryText = Color(hex: 0x6B6657)

    /// 主文字——近黑暖墨。
    static let primaryText = Color(hex: 0x2B2A26)
}

extension Color {
    /// 0xRRGGBB 整型字面量建色，便于主题集中维护。
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - 原生 AppKit tooltip 桥接

/// SwiftUI 的 `.help()` 在 `.buttonStyle(.plain)` + 自定义 label 时
/// tracking area 常建不全 → 悬浮无提示。这里直接挂 NSView 的
/// `toolTip`，走 AppKit 原生悬浮提示（系统延迟约 1 秒，符合需求），
/// 对纯图标按钮稳定生效。
private struct ToolTipView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.toolTip = text
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    /// 无文字图标按钮的悬浮说明：覆盖一层透明 AppKit tooltip 视图，
    /// 鼠标停留约 1 秒后系统弹出 `text`。`text` 走本地化后再传入。
    func nativeTooltip(_ text: String) -> some View {
        overlay(ToolTipView(text: text).allowsHitTesting(false))
    }
}
