import SwiftUI
import AppKit

/// Claude 经典配色（集中一处，主窗口统一引用）。
///
/// 浅色取自 Claude / Anthropic 桌面端观感：暖米白底 + 赤陶橙强调 +
/// 近白卡片 + 低对比暖灰分隔。深色为同一调性的暖墨版本：偏暖的近黑
/// 底 + 略亮卡片 + 暖灰分隔，避免纯黑导致赤陶橙刺眼。
/// 所有色值集中在此，View 层不再散落魔法色；改主题只动这一个文件。
enum ClaudeTheme {

    /// 赤陶橙——主强调色（按钮 tint、选中态、进度条）。深色微调更亮
    /// 一点点以保持在暖墨底上的对比度。
    static let accent = Color(light: 0xC96442, dark: 0xE07A55)

    /// 窗口/页面底色——浅色暖米白 / 深色暖墨近黑。
    static let background = Color(light: 0xFAF9F5, dark: 0x1E1C19)

    /// 卡片与可编辑区底色——比 background 略亮，制造分层。
    static let card = Color(light: 0xFFFFFF, dark: 0x2A2724)

    /// 分隔线 / 可拖动分隔条——低对比暖灰。
    static let separator = Color(light: 0xE5E2D9, dark: 0x3A3631)

    /// 次要文字（提示、占位、时间戳）——暖中灰。
    static let secondaryText = Color(light: 0x6B6657, dark: 0xA8A294)

    /// 主文字——浅色近黑暖墨 / 深色暖米白。
    static let primaryText = Color(light: 0x2B2A26, dark: 0xEDE9DF)
}

extension Color {
    /// 0xRRGGBB 整型字面量建色，便于主题集中维护。
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// 明暗双色——由 NSColor dynamicProvider 桥接到 SwiftUI Color，
    /// 系统外观切换时自动重绘。
    init(light: UInt32, dark: UInt32) {
        let ns = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(
                from: [.darkAqua, .vibrantDark,
                       .accessibilityHighContrastDarkAqua,
                       .accessibilityHighContrastVibrantDark]) != nil
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
        self.init(nsColor: ns)
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
