// markdown live-preview 装饰插件
// ============================
// 抄 Obsidian Live Preview / VS Code "Markdown Inline Editor" (CodeSmith) 的
// 三态行为：
//  - 光标远离节点 → 隐藏 markdown 标记（** _ # 等），只见渲染样式
//  - 光标接近/进入节点 → 标记重新显示，可编辑源码
//  - 文档底层始终是原始 markdown 文本，从不改写
//
// CM6 的装饰模型 (Decoration.{mark,replace,widget,line}) 与 VS Code 的
// editor.createTextEditorDecorationType 一一对应；syntaxTree(state) 拿到
// lezer/markdown 解析出的 AST，按节点名分发处理即可。

import { ViewPlugin, Decoration, WidgetType, EditorView } from "@codemirror/view"
import { RangeSetBuilder } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"

// —— widgets ——

class CheckboxWidget extends WidgetType {
  constructor(checked) { super(); this.checked = checked }
  eq(other) { return other.checked === this.checked }
  toDOM() {
    const input = document.createElement("input")
    input.type = "checkbox"
    input.checked = this.checked
    input.className = "cm-md-task-checkbox"
    return input
  }
  // ignoreEvent 默认返回 true：CM6 不把 click 当作 placeCursor，光标不会
  // 跳进 [ ] 区导致 widget 立刻消失。我们的 domEventHandlers 仍能在
  // editor DOM 根上接到冒泡上来的 click 事件做源码切换。
  ignoreEvent() { return true }
}

class HrWidget extends WidgetType {
  toDOM() {
    const hr = document.createElement("hr")
    hr.className = "cm-md-hr"
    return hr
  }
}

// —— 装饰主插件 ——

function overlapsSelection(sel, from, to) {
  // 「光标在节点上」判定：当前 selection 主光标范围与节点 [from,to] 相交
  // 包含端点（用户在 ** 后紧贴右边输入也算「在节点上」）。
  return sel.from <= to && sel.to >= from
}

function buildDecorations(view) {
  const builder = []
  const sel = view.state.selection.main
  const tree = syntaxTree(view.state)

  for (const { from: vFrom, to: vTo } of view.visibleRanges) {
    tree.iterate({
      from: vFrom,
      to: vTo,
      enter(node) {
        // —— Headings ——
        // lezer/markdown 里 ATXHeading1..6 包整行；HeaderMark 是 '#' 那段
        const headingLevel = HEADING_NAME_TO_LEVEL[node.name]
        if (headingLevel) {
          // 行级 class 让整行变大字号
          builder.push(
            Decoration.line({ class: `cm-md-h${headingLevel}` })
              .range(view.state.doc.lineAt(node.from).from)
          )
          return  // 子节点（HeaderMark / 内容）继续递归即可
        }

        // —— Mark tokens（**、__、*、_、~~、` 等）——
        if (MARK_NODE_NAMES.has(node.name)) {
          const parent = node.node.parent
          const parentFrom = parent ? parent.from : node.from
          const parentTo = parent ? parent.to : node.to
          const visible = overlapsSelection(sel, parentFrom, parentTo)
          builder.push(
            Decoration.mark({
              class: visible ? "cm-md-mark" : "cm-md-mark-hidden"
            }).range(node.from, node.to)
          )
          return
        }

        // —— 内联强调样式 ——
        switch (node.name) {
          case "StrongEmphasis":
            builder.push(Decoration.mark({ class: "cm-md-strong" })
              .range(node.from, node.to))
            return
          case "Emphasis":
            builder.push(Decoration.mark({ class: "cm-md-em" })
              .range(node.from, node.to))
            return
          case "Strikethrough":
            builder.push(Decoration.mark({ class: "cm-md-strike" })
              .range(node.from, node.to))
            return
          case "InlineCode":
            builder.push(Decoration.mark({ class: "cm-md-inline-code" })
              .range(node.from, node.to))
            return
          case "Link":
          case "URL":
            builder.push(Decoration.mark({ class: "cm-md-link" })
              .range(node.from, node.to))
            return
          case "Blockquote": {
            const startLine = view.state.doc.lineAt(node.from).number
            const endLine = view.state.doc.lineAt(node.to).number
            for (let n = startLine; n <= endLine; n++) {
              const line = view.state.doc.line(n)
              builder.push(Decoration.line({ class: "cm-md-blockquote" })
                .range(line.from))
            }
            return
          }
          case "FencedCode":
          case "CodeBlock": {
            // 给 code block 每一行加 cm-md-code-block-line，方便整体上底色
            const startLine = view.state.doc.lineAt(node.from).number
            const endLine = view.state.doc.lineAt(node.to).number
            for (let n = startLine; n <= endLine; n++) {
              const line = view.state.doc.line(n)
              let cls = "cm-md-code-block-line"
              if (n === startLine) cls += " cm-md-code-block-first"
              if (n === endLine)   cls += " cm-md-code-block-last"
              builder.push(Decoration.line({ class: cls }).range(line.from))
            }
            return
          }
          case "HorizontalRule":
            // 整行换成 <hr> widget；光标在该行时不换，让用户能编辑
            if (!overlapsSelection(sel, node.from, node.to)) {
              builder.push(Decoration.replace({ widget: new HrWidget(),
                block: false }).range(node.from, node.to))
            }
            return
          case "TaskMarker": {
            // TaskMarker 节点形如 "[ ]" 或 "[x]"
            const text = view.state.doc.sliceString(node.from, node.to)
            const checked = /\[(x|X)\]/.test(text)
            if (!overlapsSelection(sel, node.from, node.to)) {
              builder.push(
                Decoration.replace({
                  widget: new CheckboxWidget(checked)
                }).range(node.from, node.to)
              )
            }
            return
          }
        }

        // —— [[wikilink]]：lezer/markdown 默认不识别，自己扫一遍 ——
        // 见 buildWikiLinks，全局后置处理，这里不做
      }
    })
  }

  // 处理 [[wikilink]]
  buildWikiLinks(view, builder, sel)

  // RangeSetBuilder 要求 from 升序；我们用纯 array.sort 保险
  builder.sort((a, b) =>
    a.from - b.from || a.startSide - b.startSide || a.value.startSide - b.value.startSide)
  return Decoration.set(builder, true)
}

function buildWikiLinks(view, builder, sel) {
  const re = /\[\[([^\[\]\n]+?)\]\]/g
  for (const { from, to } of view.visibleRanges) {
    const text = view.state.doc.sliceString(from, to)
    let m
    while ((m = re.exec(text)) !== null) {
      const start = from + m.index
      const end = start + m[0].length
      const visible = overlapsSelection(sel, start, end)
      // 整体上 wikilink 颜色
      builder.push(Decoration.mark({ class: "cm-md-wikilink" })
        .range(start, end))
      // 两端的 [[ ]] 标记按 3-state 隐藏
      builder.push(Decoration.mark({
        class: visible ? "cm-md-mark" : "cm-md-mark-hidden"
      }).range(start, start + 2))
      builder.push(Decoration.mark({
        class: visible ? "cm-md-mark" : "cm-md-mark-hidden"
      }).range(end - 2, end))
    }
  }
}

const HEADING_NAME_TO_LEVEL = {
  ATXHeading1: 1, ATXHeading2: 2, ATXHeading3: 3,
  ATXHeading4: 4, ATXHeading5: 5, ATXHeading6: 6
}

// 所有「不想让用户在 reading 状态看到的标记字符」节点名
// 见 https://github.com/lezer-parser/markdown - 各节点定义
const MARK_NODE_NAMES = new Set([
  "HeaderMark",        // # ## ### …
  "EmphasisMark",      // * _
  "StrongEmphasisMark",// (lezer 仍叫 EmphasisMark，但 strong 两端一组)
  "CodeMark",          // `
  "StrikethroughMark", // ~~
  "QuoteMark",         // >
  "LinkMark"           // [ ]( )
])

const plugin = ViewPlugin.fromClass(class {
  constructor(view) {
    this.decorations = buildDecorations(view)
  }
  update(update) {
    if (update.docChanged || update.viewportChanged || update.selectionSet ||
        update.geometryChanged) {
      this.decorations = buildDecorations(update.view)
    }
  }
}, {
  decorations: v => v.decorations,
  provide: plugin => EditorView.atomicRanges.of(view => {
    // 让 hidden 标记成原子区，光标跳过它们而不是「卡」在隐藏字符之间
    return view.plugin(plugin)?.decorations || Decoration.none
  })
})

// 点击 task checkbox 时把源码里 [ ] / [x] 翻一翻
//
// 关键点：用 view.posAtDOM(target) 取**实时位置**，不靠 widget 创建时的
// 快照值。widget 复用 + 文档前部行数变化时，旧 data-pos 会错。
//
// mousedown 阶段：stopPropagation 防止其他可能存在的处理；click 阶段
// 才查源码做切换。
const clickHandler = EditorView.domEventHandlers({
  mousedown(event, view) {
    const target = event.target
    if (!(target instanceof HTMLInputElement)) return false
    if (!target.classList.contains("cm-md-task-checkbox")) return false
    event.stopPropagation()
    return false
  },
  click(event, view) {
    const target = event.target
    if (!(target instanceof HTMLInputElement)) return false
    if (!target.classList.contains("cm-md-task-checkbox")) return false
    const pos = view.posAtDOM(target)
    if (pos < 0) return false
    // posAtDOM 对 replace widget 返回其 from
    const slice = view.state.doc.sliceString(pos, pos + 3)
    let replacement = null
    if (slice === "[ ]") replacement = "[x]"
    else if (/\[[xX]\]/.test(slice)) replacement = "[ ]"
    if (replacement) {
      view.dispatch({
        changes: { from: pos, to: pos + 3, insert: replacement }
      })
      event.preventDefault()
      return true
    }
    return false
  }
})

export function livePreview() {
  return [plugin, clickHandler]
}
