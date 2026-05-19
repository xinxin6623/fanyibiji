# 架构设计 — 笔记原料包导出(草稿 + 相关翻译历史)

_2026-05-17 设计稿；2026-05-18 复查：已按推荐方案实现并合并，`xcodebuild build/test` 通过_

## 0. 实现状态

- 状态：DONE，已落地在 PR #3/#4 后续迭代中。
- 当前代码采用本文推荐的 D1-b（引用 id 集合）、D2-a（sidecar 文件）、
  B 整段文本兜底，以及多草稿 Tab 方案。
- 关键文件：
  - `UI/NoteEditorViewModel.swift`：维护 `referencedResultIDs`。
  - `UI/NoteDocumentsViewModel.swift`：多草稿 Tab 与历史草稿重开。
  - `Core/Persistence/NoteDraftStore.swift`：`notes/`、manifest、sidecar。
  - `Core/Services/NotePackComposer.swift`：原料包纯函数合成。
  - `UI/MainWindowView.swift`：当前 Tab 导出原料包。
  - `PersonalAgentTests/TNoteEditorTests.swift`：覆盖编辑、原料包、多草稿测试。

## 1. 目标与边界

**做什么:** 笔记区加「导出原料包」——把草稿全文 + **与草稿相关的**翻译历史(清洗过)合成**一个 .md**,用户选位置导出,交给下游知识库 Claude 做结构化/复利。

**不做什么(已对齐):**
- App 不调 LLM、不结构化、不选 skill、不并入知识库 —— 全交下游 Claude
- 不碰翻译只读管线、不改 NoteDraftStore 写入语义
- results.jsonl 仍只读

## 2. 相关性判定 = C(A 为主 B 兜底)

| | 机制 | 现状 |
|---|---|---|
| A 源追 | 插入草稿时记下来源 `ResultModel.id`,导出时按 id 精确取 jsonl 条目 | ❌ 现 `insert` 只传纯文本,**无源追** → 本设计要补 |
| B 文本兜底 | 草稿全文里出现过的译文,反查 jsonl 对应条目 | 用户编辑过译文会漏,作兜底 |

**判断:** A 准但只覆盖"点按钮插入"的;用户手敲/粘贴的译文 A 抓不到 → B 兜底。两者并集去重。

## 3. 数据流

```
[结果卡 .success(model)]  model: ResultModel(id, content, ...)
        │ 点"插入到编辑区"
        ▼
NoteEditorViewModel.insert(snippet, sourceResultID: model.id)   ← 改签名
        │ 记录 (插入字符区间 → result.id) 进 sourceMap
        ▼
[草稿 text] + [sourceMap: 内存+随草稿持久化]
        │ 点"导出原料包"
        ▼
NotePackComposer.compose(draft, sourceMap, allResults):
   A: sourceMap 里的 result.id → 取 jsonl 条目
   B: 草稿文本包含匹配 jsonl 译文 → 补
   并集去重 → 清洗(原文→译文,丢 id/时间戳/provider/tags)
        ▼
NSSavePanel 选位置 → 写出单个 .md(复用现有"保存笔记"另存模式)
```

## 4. 导出文件格式

```markdown
# 笔记原料包 · 2026-05-17 16:40

## 草稿
<note-draft 全文,原样>

## 相关翻译历史
> 共 N 条,A源追 x 条 / B文本兜底 y 条

1. 原文:...
   译文:...
2. ...
```
清洗:只留原文+译文(translation 的 text + 反查的源文本)。丢弃 id/createdAt/provider/tags/audio 类型条目。

## 5. 改动清单(跨文件,命中 pbxproj 坑)

| 文件 | 改动 | 类型 |
|---|---|---|
| `UI/NoteEditorViewModel.swift` | `insert` 加 `sourceResultID: UUID?` 参；维护 `sourceMap: [(range, UUID)]`;插入/编辑后区间维护 | 改 |
| `UI/MainWindowView.swift:285` | `insert(text)` → `insert(text, sourceResultID: model.id)`;加「导出原料包」按钮 + NSSavePanel | 改 |
| `Core/Notes/NotePackComposer.swift` | **新增**:纯函数,输入(draft, sourceMap, [ResultModel])→ 输出 md 字符串。A∪B 去重+清洗 | 新增 |
| `Core/Persistence/NoteDraftStore.swift` | sourceMap 随草稿持久化(草稿 .md 旁存 sidecar `.note-draft.sourcemap.json`,或并入) | 改 |
| `PersonalAgent.xcodeproj/project.pbxproj` | 新增 NotePackComposer.swift **手动登记 4 处** | 改 |
| `PersonalAgentTests/TNotePackTests.swift` | **新增**单测 | 新增 |

## 6. 关键设计决策(请 James 拍板)

### D1. sourceMap 怎么随草稿活下来?
草稿被编辑后,字符区间会移位,sourceMap 要跟着维护。两个方案:

- **D1-a 精确区间维护**:insert/编辑都重算 range。准,但 `text` didSet 里要做区间偏移运算,复杂、易错。
- **D1-b 退化为 id 集合**:不记精确区间,只记"这草稿引用过哪些 result.id"集合。编辑不影响。A 退化为"导出草稿引用过的所有 id 条目",配合 B 文本匹配。**推荐**——简单稳健,且导出本就是给 LLM 当原料,不需要字符级精确。

### D2. sourceMap 存哪?
- **D2-a sidecar 文件**:`note-draft.md` 旁存 `note-draft.sourcemap.json`。草稿文件保持纯净(用户/下游直接看草稿不被污染)。**推荐**。
- D2-b 并入草稿:草稿里塞 HTML 注释存 id。会污染用户看到的草稿。

### D3. B 文本匹配粒度?
译文整段命中才算 / 还是子串命中?建议**整段命中**(逐条 jsonl 译文文本是否作为子串出现在草稿),避免短译文误命中一片。

## 7. 复用的现成模式

- NSSavePanel 另存:照搬现有「保存笔记」(NoteEditorView 里),`markExported(to:)` 回显
- 纯函数 + 注入:NotePackComposer 仿 `XunfeiTTSAuth`/`TTSFrameCollector` 纯类型,零 IO,易单测
- sidecar 原子写:仿 NoteDraftStore 的临时文件+replace

## 8. 单测点(零网络零 IO)

- A: sourceMap 有 id → 命中对应 jsonl 条目
- B: 草稿含某译文文本但无 id → 文本兜底命中
- A∪B 去重:同条被 A 和 B 同时命中只出一次
- 清洗:audio 类型条目被排除;输出无 id/时间戳
- 空草稿 / 空历史 / 无相关条目 → 合理空态文案
- sourceMap sidecar 损坏/缺失 → 降级纯 B,不崩

---

# 附:多草稿并行 + Tab(2026-05-17 追加需求)

草稿从单文件单草稿 → **多草稿并行,Tab 切换**;新建/关闭 Tab;保存与导出原料包均针对**当前 Tab**。

## A. 分层(已定:新增上层 VM,几乎不动 NoteEditorViewModel)

```
NoteDocumentsViewModel(新增,@MainActor)
  ├─ documents: [DocumentTab]   每项 = { id, NoteEditorViewModel 实例 }
  ├─ selectedID: UUID           当前 Tab
  ├─ newDocument() / closeDocument(id) / select(id)
  └─ 每个 NoteEditorViewModel 几乎原样复用(单草稿逻辑不变)
```

**判断:** 这是最干净的隔离——现有 `NoteEditorViewModel` 的 text/saveStatus/防抖/lastPersistedText/sourceMap **一行不改其内部逻辑**,只是从"全局唯一"变成"每 Tab 一个实例"。所有已修过的坑(状态机短路/空操作反馈/保存语义)自动每 Tab 各自成立。

## B. 存储(已定:notes/ 目录多 .md + manifest)

```
~/Library/Application Support/com.james.personalagent/notes/
  ├── manifest.json                  Tab 顺序、id、标题缓存、selectedID
  ├── draft-<uuid>.md                每草稿一文件
  ├── .draft-<uuid>.sourcemap.json   每草稿一份 sidecar(原料包 A 源追用)
  └── (旧 note-draft.md 不再用;首启迁移见 D5)
```
`NoteDraftStore` 从"绑定单 fileURL"改为**按 draft id 定位文件**;原子写/sidecar 语义不变,只是路径参数化。manifest 也走原子写。

## C. Tab 行为(已定 — 不怕丢,简化)

- **标题** = 草稿首行非空文本(截断),空 → "未命名";随输入实时刷新,缓存进 manifest
- **关闭** = 仅从 Tab 条移除,**草稿文件留盘到 notes/**(全量留存,不删不归档)。**不弹确认**(用户明确不怕丢 + 文件本就留着 + 防抖自动保存)
- **新建** = 空草稿 + 新 Tab + 自动选中
- **历史草稿列表** = 列出 notes/ 下所有未在 Tab 打开的草稿(首行标题 + 时间),点击重新作为 Tab 打开。这是关闭后唯一的重开入口
- ~~D5 旧 note-draft.md 迁移~~ **已砍**(James 不怕丢,旧文件不管,直接全新 notes/ 体系)

## D. 增量改动清单(在原清单基础上)

| 文件 | 改动 | 类型 |
|---|---|---|
| `UI/NoteDocumentsViewModel.swift` | **新增**:多文档/Tab 编排 + 历史草稿列举 | 新增 |
| `UI/NoteEditorViewModel.swift` | 内部逻辑不动;`init` 接收 draft id;`save`/导出语义不变 | 微调 |
| `Core/Persistence/NoteDraftStore.swift` | 单 fileURL → 按 draft id 定位;新增 manifest 读写 + 列举 notes/ 下全部草稿 | 改 |
| `UI/MainWindowView.swift` | 笔记区顶部加 Tab 条 + 历史草稿入口;"插入"/"导出原料包"作用于 `documents.selected` | 改 |
| `Core/Notes/NotePackComposer.swift` | 不变(本就按单草稿+其 sourceMap 工作,上层传当前 Tab 的即可) | 不变 |
| `PersonalAgent.xcodeproj/project.pbxproj` | NoteDocumentsViewModel.swift + NotePackComposer.swift **各手动登记 4 处** | 改 |
| `PersonalAgentTests/TNoteDocumentsTests.swift` | **新增**单测 | 新增 |

## E. 多草稿单测点

- 新建 → documents +1,selected 指向新的,文件落盘
- 关闭 → 仅从 documents 移除,**notes/ 文件仍在**(留存验证)
- 历史草稿列表 = notes/ 下未在 Tab 打开的草稿;点击重开 → 回到 documents
- 切 Tab → 各自 text/saveStatus 互不串(隔离性)
- 标题取首行;首行空 → "未命名";首行变更 → 标题与 manifest 同步
- manifest 损坏 → 不崩,降级扫 notes/ 目录重建

## F. 与原料包导出的交互(关键,别串)

"导出原料包"按钮作用于**当前选中 Tab**:取该 Tab 的 NoteEditorViewModel.text + 它**自己的** sourceMap → NotePackComposer。多 Tab 各有独立 sourceMap,绝不能跨 Tab 取 result.id,否则原料包混入别的草稿的翻译历史。这是多草稿引入后最易出的 bug,单测必须覆盖"两 Tab 各自插入不同 result,导出 A 不含 B 的条目"。
