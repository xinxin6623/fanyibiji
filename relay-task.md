# Relay Task

_updated: 2026-05-17 (笔记原料包 + 多草稿 Tab)_
_project: /Users/qoragufimo390gmail.com/Documents/New project 3 (PersonalAgent)_
_branch: main_

## 任务
笔记区新增「原料包导出 + 多草稿并行 Tab」。App 侧只采集+导出
(草稿 + 相关翻译历史 → 单 .md),结构化交下游知识库 Claude。
本轮功能闭环:xcodebuild build + 全量 test 全绿。

## 当前进度
- [x] NotePackComposer 纯函数(A源追∪B文本兜底,清洗)
- [x] ResultModel 加 sourceText + 改写入点存原文
- [x] NoteDraftStore 多文件 + manifest + sidecar
- [x] NoteEditorViewModel 加源追(内部逻辑不动)
- [x] NoteDocumentsViewModel 多 Tab 编排
- [x] MainWindowView Tab条+历史+原料包导出按钮
- [x] pbxproj 2 新文件各 4 处 + xcstrings 6 键
- [x] 单测 31 用例(TNote 三套)+ 全量 test 全绿
- [~] 真机手验:由 James 把关,未由 agent 验收
- [ ] **未 commit**(等 James 要求再提交)

## 下一步
无必须接力工程项。可选:
1. 真机验收:Tab 新建/切换/关闭留盘、历史草稿重开、
   原料包导出内容(原文→译文配对是否齐)、跨 Tab 不串。
2. James 要求时 commit(本轮所有改动未提交)。
3. 下游闭环验证:导出的原料包用 `/kb add <文件>` 喂知识库。

## 关键文件
- 合成器:`PersonalAgent/Core/Services/NotePackComposer.swift`
- 多文档:`PersonalAgent/UI/NoteDocumentsViewModel.swift`
- 存储:`PersonalAgent/Core/Persistence/NoteDraftStore.swift`(多文件化)
- 模型:`PersonalAgent/Core/Models/ResultModel.swift`(+sourceText)
- 写入点:`PersonalAgent/UI/ContentQueryViewModel.swift`(两处带 sourceText)
- UI:`PersonalAgent/UI/MainWindowView.swift`(notePane/Tab/导出)
- 测试:`PersonalAgentTests/TNoteEditorTests.swift`(含 TNotePack/TNoteDocuments)
- 设计文档:`design-note-export-pack.md`、`知识库结构.md`
- 落盘:`~/Library/Application Support/com.james.personalagent/notes/`
  (draft-<id>.md / .draft-<id>.sourcemap.json / manifest.json)

## 上下文要点(接手前必读)
1. 构建后 `pkill -x PersonalAgent` 再 `open
   build/DerivedData/Build/Products/Debug/PersonalAgent.app`。
2. SourceKit 跨文件 "Cannot find type" 海量误报,以 xcodebuild 为准。
3. 全量 test 偶发 "TEST FAILED" 无 error/无 fail 用例 = 测试宿主
   占用,`pkill -x` 后重跑即全绿(已确认非代码问题)。
4. 职责边界:App **不调 LLM、不结构化**,只导原料包;结构化是
   下游知识库 Claude(`/kb` + `~/knowledge`)的活。
5. 旧 note-draft.md 不迁移(James 明确不怕丢),全新 notes/ 体系。
6. pbxproj 显式引用,新增 .swift 必手动补 4 处。
