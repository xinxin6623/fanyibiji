// 打包入口：把 CM6 全家桶 + 自家的 markdown live-preview 插件聚合成一个
// IIFE，挂到 window.CM6 上给 inline-editor.html 用。
//
// 之所以包一层而非直接用 esm.sh，是为了：
// ① 离线、可重复构建；② 一次 evaluateScript 就能装好所有依赖，避免桥协议
// 里要处理「依赖还没就绪」的边界态。

import {EditorView, keymap, lineNumbers, drawSelection, highlightActiveLine,
        highlightActiveLineGutter, placeholder, WidgetType, Decoration,
        ViewPlugin} from "@codemirror/view"
import {EditorState, RangeSetBuilder, Compartment, Prec} from "@codemirror/state"
import {defaultKeymap, history, historyKeymap, undo, redo,
        indentWithTab} from "@codemirror/commands"
import {markdown, markdownLanguage} from "@codemirror/lang-markdown"
import {syntaxTree, syntaxHighlighting, defaultHighlightStyle, HighlightStyle,
        bracketMatching, indentOnInput, foldGutter} from "@codemirror/language"
import {searchKeymap, highlightSelectionMatches} from "@codemirror/search"
import {tags} from "@lezer/highlight"

import {livePreview} from "./live-preview.mjs"

// 暴露给 inline-editor.html 的最小 API 面：
//   CM6.create({parent, doc, onChange}) -> EditorView
//   CM6.setDoc(view, doc)
//   CM6.insertAtCursor(view, text)
//   CM6.getDoc(view) -> string
//   CM6.undo / CM6.redo
//   CM6.setTheme(view, 'dark'|'light')
//
// 主题用 Compartment + reconfigure 切，避免重建 view（光标会丢）。
const themeCompartment = new Compartment()

const baseTheme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "15px",
    fontFamily: '-apple-system, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif',
    backgroundColor: "transparent",
    color: "var(--md-fg)"
  },
  ".cm-scroller": {
    fontFamily: "inherit",
    lineHeight: "1.75",
    padding: "20px 24px"
  },
  ".cm-content": {
    caretColor: "var(--cm-caret)",
    paddingBottom: "30vh"
  },
  ".cm-line": { padding: "0" },
  ".cm-cursor": { borderLeftWidth: "2px" },

  // —— 标题（GitHub 风：H1/H2 带底边，纵向层级清晰）——
  ".cm-md-h1": {
    fontSize: "1.95em", fontWeight: "700", lineHeight: "1.25",
    color: "var(--md-heading)",
    margin: "0.55em 0 0.35em",
    paddingBottom: "0.28em",
    borderBottom: "1px solid var(--md-h1-border)"
  },
  ".cm-md-h2": {
    fontSize: "1.55em", fontWeight: "700", lineHeight: "1.3",
    color: "var(--md-heading)",
    margin: "0.5em 0 0.3em",
    paddingBottom: "0.22em",
    borderBottom: "1px solid var(--md-h2-border)"
  },
  ".cm-md-h3": { fontSize: "1.28em", fontWeight: "700",
                 color: "var(--md-heading)", margin: "0.45em 0 0.2em" },
  ".cm-md-h4": { fontSize: "1.12em", fontWeight: "700",
                 color: "var(--md-heading)", margin: "0.4em 0 0.18em" },
  ".cm-md-h5": { fontSize: "1.04em", fontWeight: "700",
                 color: "var(--md-heading)" },
  ".cm-md-h6": { fontSize: "0.95em", fontWeight: "700",
                 color: "var(--md-fg-muted)", letterSpacing: "0.02em" },

  // —— 强调 ——
  ".cm-md-strong": { fontWeight: "700", color: "var(--md-strong)" },
  ".cm-md-em":     { fontStyle: "italic", color: "var(--md-em)" },
  ".cm-md-strike": { textDecoration: "line-through", color: "var(--md-fg-muted)" },

  // —— 内联代码：红色字 + 浅灰底（GitHub 风）——
  ".cm-md-inline-code": {
    fontFamily: '"SF Mono", ui-monospace, Menlo, Consolas, monospace',
    fontSize: "0.88em",
    color: "var(--md-code-fg)",
    background: "var(--md-code-bg)",
    padding: "1.5px 6px",
    borderRadius: "4px",
    border: "1px solid var(--md-code-border)"
  },

  // —— 三态标记 ——
  ".cm-md-mark":        { color: "var(--md-mark-soft)", fontWeight: "400" },
  ".cm-md-mark-hidden": { display: "none" },

  // —— 引用：左竖条 + 淡背景 ——
  ".cm-md-blockquote": {
    borderLeft: "3px solid var(--md-quote-border)",
    paddingLeft: "12px",
    background: "var(--md-quote-bg)",
    color: "var(--md-quote-fg)"
  },

  // —— 链接 ——
  ".cm-md-link":     { color: "var(--md-link)",     textDecoration: "var(--md-link-decoration, underline)" },
  ".cm-md-wikilink": { color: "var(--md-wikilink)", fontWeight: "500" },

  // —— Task 复选框 ——
  ".cm-md-task-checkbox": {
    display: "inline-block",
    width: "16px", height: "16px",
    margin: "0 6px -3px 0",
    verticalAlign: "baseline",
    cursor: "pointer",
    accentColor: "var(--md-link)"
  },

  // —— 分隔线 ——
  ".cm-md-hr": {
    border: "0",
    borderTop: "1px solid var(--md-hr)",
    margin: "0.8em 0"
  },

  // —— Code block 容器：line class 由 live-preview 装饰主插件下发 ——
  ".cm-md-code-block-line": {
    background: "var(--md-code-bg)",
    fontFamily: '"SF Mono", ui-monospace, Menlo, Consolas, monospace',
    fontSize: "0.92em",
    paddingLeft: "12px !important",
    paddingRight: "12px !important",
    borderLeft: "1px solid var(--md-code-border)",
    borderRight: "1px solid var(--md-code-border)"
  },
  ".cm-md-code-block-first": {
    borderTop: "1px solid var(--md-code-border)",
    borderTopLeftRadius: "6px",
    borderTopRightRadius: "6px",
    paddingTop: "6px !important",
    marginTop: "0.2em"
  },
  ".cm-md-code-block-last": {
    borderBottom: "1px solid var(--md-code-border)",
    borderBottomLeftRadius: "6px",
    borderBottomRightRadius: "6px",
    paddingBottom: "6px !important",
    marginBottom: "0.2em"
  }
})

// lezer-highlight → class 映射。用 class 而非 color 让 CSS 变量做明暗
// 主题切换（HighlightStyle.define color 字段会被注入成 inline style，
// 无法跟 prefers-color-scheme 切；class 模式完全靠 inline-editor.html
// 里的 .tok-* 规则定义颜色）。
const highlightStyle = HighlightStyle.define([
  { tag: tags.heading,       fontWeight: "bold" },
  { tag: tags.strong,        fontWeight: "bold" },
  { tag: tags.emphasis,      fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.keyword,       class: "tok-keyword" },
  { tag: tags.atom,          class: "tok-atom" },
  { tag: tags.number,        class: "tok-number" },
  { tag: tags.string,        class: "tok-string" },
  { tag: tags.comment,       class: "tok-comment" },
  { tag: tags.variableName,  class: "tok-variable" },
  { tag: tags.function(tags.variableName), class: "tok-function" },
  { tag: tags.typeName,      class: "tok-type" },
  { tag: tags.url,           class: "tok-url" },
  { tag: tags.link,          class: "tok-url" }
])

function makeExtensions({ onChange }) {
  const updateListener = EditorView.updateListener.of(u => {
    if (u.docChanged && onChange) {
      onChange(u.state.doc.toString())
    }
  })
  return [
    history(),
    drawSelection(),
    highlightActiveLine(),
    bracketMatching(),
    indentOnInput(),
    markdown({ base: markdownLanguage, codeLanguages: [] }),
    syntaxHighlighting(highlightStyle, { fallback: true }),
    livePreview(),
    EditorView.lineWrapping,
    keymap.of([
      ...defaultKeymap,
      ...historyKeymap,
      ...searchKeymap,
      indentWithTab
    ]),
    themeCompartment.of(baseTheme),
    updateListener
  ]
}

function create({ parent, doc = "", onChange }) {
  const state = EditorState.create({
    doc,
    extensions: makeExtensions({ onChange })
  })
  return new EditorView({ state, parent })
}

function setDoc(view, doc) {
  const current = view.state.doc.toString()
  if (current === doc) return
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: doc }
  })
}

function insertAtCursor(view, text) {
  const { from, to } = view.state.selection.main
  view.dispatch({
    changes: { from, to, insert: text },
    selection: { anchor: from + text.length }
  })
  view.focus()
}

function getDoc(view) {
  return view.state.doc.toString()
}

function setTheme(view, mode) {
  // baseTheme 已经吃 css 变量，主题切换主要靠 inline-editor.html 里的
  // body 根 class，这里保留接口供未来注入暗色 EditorView.theme 用。
  // 当前实现：reconfigure 同一 baseTheme 即可触发重绘（color-scheme 变了）。
  view.dispatch({ effects: themeCompartment.reconfigure(baseTheme) })
}

function doUndo(view) { undo(view); view.focus() }
function doRedo(view) { redo(view); view.focus() }

export {
  create, setDoc, insertAtCursor, getDoc, setTheme, doUndo as undo, doRedo as redo,
  EditorView, EditorState
}
