# Relay Task

_updated: 2026-05-17 16:00_
_project: /Users/qoragufimo390gmail.com/Documents/New project 3 (PersonalAgent / fanyibiji)_
_branch: main_

## 任务
给 PersonalAgent 翻译 App 加右侧笔记编辑区：左右可拖动分栏，右侧
Markdown 编辑/预览双模式，译文一键插入，草稿独立归档 +「保存笔记」
另存导出。本轮功能闭环，构建+14 单测全绿。

## 当前进度
- [x] NoteDraftStore 原子写持久化
- [x] NoteEditorViewModel（防抖自动保存 + insert + 导出回调）
- [x] NoteEditorView（双模式 + NSSavePanel 另存导出）
- [x] MainWindowView 左右分栏 + 结果卡"插入到编辑区"按钮
- [x] pbxproj 4 文件登记、本地化键、14 单测全绿、构建通过
- [x] 三轮 bug 修复（保存状态机短路 / 空操作无反馈 / 保存语义→另存）
- [~] 真机手验：由 James 把关，未由 agent 验收

## 下一步
当前没有必须接力的工程下一步。

如需继续，可选动作：
1. 真机验收分栏拖动手感、Markdown 预览（当前仅逐行行内渲染，
   表格/嵌套引用等块级语法未做完整解析——如需增强见下）
2. 实现「最终笔记生成」：调 LLM 对草稿做结构化处理，处理时抓
   `results.jsonl` 原始翻译历史（设计意图已定，代码未写）
3. 用户要求 commit 时再提交（本轮所有改动未 commit）

## 关键文件 / 路径
- 持久化：`PersonalAgent/Core/Persistence/NoteDraftStore.swift`
- 编排：`PersonalAgent/UI/NoteEditorViewModel.swift`
- 视图：`PersonalAgent/UI/NoteEditorView.swift`（NSSavePanel 在此）
- 分栏/插入按钮：`PersonalAgent/UI/MainWindowView.swift`
- 测试：`PersonalAgentTests/TNoteEditorTests.swift`
- 草稿落盘：`~/Library/Application Support/com.james.personalagent/notes/note-draft.md`
- 本轮存档：`/Users/qoragufimo390gmail.com/baidu/Archives/2026-05-17-笔记编辑区与保存语义迭代.md`
- 相关 auto memory：`feedback_2026-05-17_macos-swift-pitfalls.md`、`project_2026-05-17_note-editor.md`

## 阻塞 / 风险 / 待用户决策
- 无阻塞。Markdown 预览仅行内级渲染是已知取舍，James 如需块级
  （表格/列表嵌套）需明确要求再做。

## 上下文要点（接手前必读）
1. 构建后必须 `pkill -x PersonalAgent` 再 `open
   build/DerivedData/Build/Products/Debug/PersonalAgent.app`；仓库另有
   旧的 `.DerivedData/` 产物，open 错会看到旧 UI。
2. 保存有两条独立路径：内部草稿防抖自动保存（防丢，1.5s）+「保存
   笔记」按钮弹 NSSavePanel 让用户选位置导出（互不影响）。
3. SourceKit 跨文件报错在此工程是稳定误报，以 xcodebuild 为准。
4. pbxproj 是显式引用式，新增 .swift 必须手动补 4 处条目。
5. 翻译结果只读管线没动；笔记区是完全独立模块。
