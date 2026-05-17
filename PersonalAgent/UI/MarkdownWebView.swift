import SwiftUI
import WebKit

/// Markdown 预览:WKWebView + 离线打包的 marked + highlight.js。
///
/// 为什么用 WebView 而非逐行 `AttributedString`:代码块/表格/嵌套
/// 列表/跨行引用是块级多行结构,逐行拼永远补不全(ASCII 图会被
/// 打散)。WebView 一次到位,与 GitHub 渲染一致。
///
/// 安全/隐私:
///  - JS/CSS 全离线打包(不走 CDN;笔记是隐私内容且需离线可用)
///  - 内容经 base64 → `window.__render()` 注入,不拼进 HTML
///  - marked 默认转义 HTML(用户笔记里的 `<script>` 不会执行)
///  - 禁止页面导航(链接点击不跳转,纯阅读)
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")  // 跟随容器底色
        if let dir = Self.resourceDir,
           let html = try? String(
                contentsOf: dir.appendingPathComponent("template.html"),
                encoding: .utf8) {
            // baseURL = 资源目录 → 模板里相对路径 JS/CSS 可解析。
            web.loadHTMLString(html, baseURL: dir)
        }
        context.coordinator.pending = markdown
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.render(markdown, in: web)
    }

    /// 打包资源目录(MarkdownWeb/ 下 template.html + js + css)。
    private static var resourceDir: URL? {
        Bundle.main.url(forResource: "template", withExtension: "html",
                        subdirectory: "MarkdownWeb")?
            .deletingLastPathComponent()
        ?? Bundle.main.url(forResource: "template", withExtension: "html")?
            .deletingLastPathComponent()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// 模板加载完成前到达的内容,完成后补发(避免首帧空白)。
        var pending: String?
        private var loaded = false

        func render(_ md: String, in web: WKWebView) {
            guard loaded else { pending = md; return }
            inject(md, into: web)
        }

        func webView(_ web: WKWebView,
                     didFinish nav: WKNavigation!) {
            loaded = true
            if let p = pending { inject(p, into: web); pending = nil }
        }

        /// 禁止任何导航(链接点击/重定向),纯阅读视图。
        func webView(_ web: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 首次 loadHTMLString 放行,其余(链接点击等)拦截。
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }

        private func inject(_ md: String, into web: WKWebView) {
            let b64 = Data(md.utf8).base64EncodedString()
            web.evaluateJavaScript("window.__render && window.__render('\(b64)')")
        }
    }
}
