import SwiftUI
import WebKit
import os.log

/// 行内实时渲染 Markdown 编辑器（WKWebView 内嵌 TOAST UI Editor，WYSIWYG）。
///
/// 取代「编辑/预览」分栏：用户看到的就是渲染后的样子，工具栏支持标题/
/// 列表/任务清单/表格/代码块/引用/链接/图片等常用语义。Markdown 源仍由
/// `viewModel.text` 兜底（TOAST 在 WYSIWYG 模式下用 `getMarkdown()` 序列化
/// 回 markdown），保持 ViewModel 是真理源不变。
///
/// 安全/隐私：
///  - JS/CSS 全离线打包（不走 CDN）；
///  - 内容经 base64 → `window.__setMarkdown()` 注入，不拼进 HTML；
///  - 禁止页面导航跳走；
///  - 链接默认在编辑态可点击，但 navigation 拦截后只回弹给 Swift 处理。
///
/// 桥协议：
///  - JS→Swift：`postMessage({type: 'ready'})` 表示 editor 就绪；
///    `postMessage({type: 'change', md: '...'})` 表示用户改动。
///  - Swift→JS：`window.__setMarkdown(b64)` 全量重置；
///    `window.__insertText(b64)` 在光标处插入文本。
struct MarkdownInlineEditorView: NSViewRepresentable {

    @Binding var text: String
    /// 视图层主动告知 ViewModel：JS 已就绪，可以做首屏推送/后续指令。
    /// 通常 NoteEditorView 会用它把 `text` 推一次。
    var onReady: () -> Void = {}
    /// makeCoordinator 完成、coordinator 创建好后立刻回调一次。
    /// ViewModel 据此持弱引用，后续 `insert(_:)` 走 `insertAtCursor` 在
    /// 光标处插入而非覆盖整段，保住用户当前光标位置。
    var onCoordinatorReady: (Coordinator) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        let coord = Coordinator(text: $text, onReady: onReady)
        // SwiftUI 会在 makeCoordinator 完成后再走 makeNSView。这里同步抛
        // 出 coordinator 引用给 ViewModel；ViewModel 持弱引用即可。
        DispatchQueue.main.async { onCoordinatorReady(coord) }
        return coord
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "swift")
        config.userContentController = userContent

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        // 开发期开 Web Inspector（macOS 13.3+），右键 → Inspect Element
        // 能看 JS console / DOM / 网络面板，排查 TOAST UI 起不来时必备。
        if #available(macOS 13.3, *) {
            web.isInspectable = true
        }
        context.coordinator.web = web

        if let dir = Self.resourceDir {
            let htmlURL = dir.appendingPathComponent("inline-editor.html")
            // 用 `loadFileURL` + 显式 `allowingReadAccessTo` 比 `loadHTMLString`
            // + baseURL 更稳：明确授权 dir 子文件访问，避开历史上 WebKit 对
            // `loadHTMLString(_:baseURL:)` 同目录子资源加载的偶发拒绝。
            web.loadFileURL(htmlURL, allowingReadAccessTo: dir)
            MarkdownInlineEditorView.log.info(
                "loading \(htmlURL.path, privacy: .public)")
        } else {
            MarkdownInlineEditorView.log.error(
                "InlineEditor resource dir not found in bundle")
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        // 仅当 viewModel.text 与 editor 内的 markdown 不一致时下推。
        // Coordinator 自己最后一次 push 的快照对齐，避免每次 SwiftUI 重绘
        // 都推一份（推一份会清掉用户当前光标位置）。
        context.coordinator.syncFromOutside(markdown: text)
    }

    private static var resourceDir: URL? {
        Bundle.main.url(forResource: "inline-editor", withExtension: "html",
                        subdirectory: "InlineEditor")?
            .deletingLastPathComponent()
        ?? Bundle.main.url(forResource: "inline-editor", withExtension: "html")?
            .deletingLastPathComponent()
    }

    /// JS 报上来的错误打到 Console.app：
    /// `log stream --predicate 'subsystem == "com.james.personalagent" AND category == "InlineEditor"' --info`
    private static let log = Logger(
        subsystem: "com.james.personalagent", category: "InlineEditor")

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var text: String
        let onReady: () -> Void
        weak var web: WKWebView?
        private var ready = false
        /// JS 端 editor 当前内容快照（双路径维护：① JS 上报 change 时记下；
        /// ② Swift 主动 setMarkdown 后也记下）。Swift 推下来的 markdown 与
        /// 它相等就跳过——避免回环（JS→Swift→state→重绘→updateNSView 又
        /// 推 JS 一遍）并避免清光标。
        private var jsContent: String = ""

        init(text: Binding<String>, onReady: @escaping () -> Void) {
            self._text = text
            self.onReady = onReady
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ uc: WKUserContentController,
                                   didReceive msg: WKScriptMessage) {
            guard let dict = msg.body as? [String: Any],
                  let type = dict["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                let hasEditor = (dict["hasEditor"] as? Bool) ?? false
                if !hasEditor {
                    MarkdownInlineEditorView.log.error(
                        "ready but editor not initialized — see JS errors")
                }
                // 首屏推送当前 viewModel.text；JS 内部已守门一致即跳过。
                pushToJS(text)
                onReady()
            case "change":
                guard let md = dict["md"] as? String else { return }
                jsContent = md
                if text != md {
                    DispatchQueue.main.async { [weak self] in
                        self?.text = md
                    }
                }
            case "error":
                let m = (dict["msg"] as? String) ?? "<no msg>"
                MarkdownInlineEditorView.log.error("JS: \(m, privacy: .public)")
            default: break
            }
        }

        // MARK: - 主动同步

        /// SwiftUI 重绘时 ViewModel 推下来的新 markdown。
        /// - 与 JS 当前内容一致 → 跳过（避免清光标）
        /// - 不一致 → setMarkdown 全量覆盖（撤销/重做/loadDraft 等场景）
        func syncFromOutside(markdown: String) {
            guard ready else {
                // 还没 ready，记下来 ready 时再推。`text` 经 Binding 已最新。
                return
            }
            // 等价：JS editor 当前就是这个值（要么是 JS 上报来的，要么是
            // 我们刚推的）→ 跳过，避免清光标。
            if markdown == jsContent { return }
            pushToJS(markdown)
        }

        /// 在光标处插入（不是覆盖）。供 ViewModel 的 `insert(_:)` 使用，
        /// 避免覆盖整段文本破坏光标/选区。
        func insertAtCursor(_ snippet: String) {
            guard ready, let web else { return }
            let b64 = Data(snippet.utf8).base64EncodedString()
            web.evaluateJavaScript("window.__insertText && window.__insertText('\(b64)')")
        }

        private func pushToJS(_ markdown: String) {
            guard let web else { return }
            // 同步登记：推完之后 JS editor 内容就是这个值；下一次重绘
            // 再次 syncFromOutside 同一 markdown 时直接跳过。
            jsContent = markdown
            let b64 = Data(markdown.utf8).base64EncodedString()
            web.evaluateJavaScript(
                "window.__setMarkdown && window.__setMarkdown('\(b64)')")
        }

        // MARK: - WKNavigationDelegate

        func webView(_ web: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 首次 loadHTMLString 放行；用户点笔记里的链接 → 默认浏览器，
            // 不让 WebView 自己跳走（会清掉编辑器实例）。
            if action.navigationType == .other {
                decisionHandler(.allow); return
            }
            if let url = action.request.url, action.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
