import AppKit
import SwiftUI

/// app 内划词朗读：监听 app 内部鼠标松开，若当前焦点文本控件有选区，
/// 在鼠标上方 20px 弹一个「朗读」浮层；点击后把选中文字交回调。
///
/// **仅 app 内**：用 `addLocalMonitorForEvents`（只收本进程事件），
/// 不碰全局事件，**无需辅助功能权限**。选区文字直接读 first responder
/// 的 `NSTextView.selectedText`——结果区/历史/输入框/笔记编辑区底层
/// 都是 NSTextView（SwiftUI Text(.textSelection)/TextEditor 皆然），
/// 故一处监听覆盖全部可选文字区。
@MainActor
final class SelectionSpeakController {

    /// 点击浮层「朗读」后回调（选中文字非空、已 trim）。
    var onSpeak: ((String) -> Void)?

    private var monitor: Any?
    private var panel: NSPanel?
    /// 不点击自动消失定时器（James 指定 2 秒）。
    private var autoDismiss: Timer?
    /// 上次 dismiss 时间。dismiss 后极短时间内（含点小喇叭那次
    /// mouseUp）忽略选区检测，否则选区还在会立刻重弹，看似“点完
    /// 不消失”。

    /// 鼠标上方偏移（James 指定 20px）。
    private let yOffset: CGFloat = 20
    /// 浮层不点击存活秒数。
    private let autoDismissSeconds: TimeInterval = 2
    /// dismiss 后忽略 mouseUp 的去抖窗口。
    private var lastDismiss: Date = .distantPast
    private let suppressWindow: TimeInterval = 0.35

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) {
            [weak self] event in
            // 不拦截事件，原样返回；只在松手后下一拍检查选区
            // （此刻 NSTextView 的 selectedRange 已更新）。
            DispatchQueue.main.async { self?.handleMouseUp() }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        dismiss()
    }

    // MARK: - 选区检测

    private func handleMouseUp() {
        // 刚 dismiss 过（点小喇叭那次 mouseUp、或点别处关掉）→ 去抖
        // 窗口内不重弹，否则选区还在会立刻又弹一个，看似不消失。
        if Date().timeIntervalSince(lastDismiss) < suppressWindow {
            return
        }
        // 浮层还在 → 这次点击要么命中按钮（action 自己 dismiss），
        // 要么点了别处，统一收掉，不重弹。
        if panel != nil {
            dismiss()
            return
        }
        guard let text = currentSelectedText(), !text.isEmpty else {
            dismiss()
            return
        }
        showPanel(for: text)
    }

    /// 取当前 key window first responder 的选中文字。first responder
    /// 可能是 NSTextView 本身，或其 field editor 链上的对象。
    private func currentSelectedText() -> String? {
        guard let window = NSApp.keyWindow,
              let tv = Self.textView(from: window.firstResponder) else {
            return nil
        }
        let ns = tv.string as NSString
        let r = tv.selectedRange()
        guard r.length > 0, r.location + r.length <= ns.length else { return nil }
        return ns.substring(with: r)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func textView(from responder: NSResponder?) -> NSTextView? {
        if let tv = responder as? NSTextView { return tv }
        // SwiftUI Text(.textSelection) 的 responder 有时是承载视图，
        // field editor 才是 NSTextView——向上找一层。
        if let v = responder as? NSView,
           let tv = v.window?.fieldEditor(false, for: v) as? NSTextView,
           tv.selectedRange().length > 0 {
            return tv
        }
        return nil
    }

    // MARK: - 浮层

    private func showPanel(for text: String) {
        dismiss()
        let mouse = NSEvent.mouseLocation  // 屏幕坐标（左下原点）

        let host = NSHostingController(
            rootView: SpeakBubble { [weak self] in
                self?.dismiss()
                self?.onSpeak?(text)
            })
        let size = host.view.fittingSize

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.contentViewController = host
        // 鼠标正上方 20px：x 居中于鼠标，y 在鼠标之上。
        p.setFrameOrigin(NSPoint(
            x: mouse.x - size.width / 2,
            y: mouse.y + yOffset))
        p.orderFront(nil)
        panel = p

        // 不点击 2 秒自动消失（James 指定）。
        autoDismiss?.invalidate()
        autoDismiss = Timer.scheduledTimer(
            withTimeInterval: autoDismissSeconds, repeats: false) {
                [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
    }

    private func dismiss() {
        autoDismiss?.invalidate()
        autoDismiss = nil
        lastDismiss = Date()
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 浮层内容：单个「朗读」胶囊按钮，Claude 配色。
private struct SpeakBubble: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "speaker.wave.2")
                Text("tts.speak_input")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(ClaudeTheme.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(4)
    }
}
