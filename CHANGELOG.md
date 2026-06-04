# fanyibiji · CHANGELOG

> 每次改动告一段落记一条。详细记录写在各自模块（commit message / `relay-task.md` / `project-board.md`），本文件是**强标签化的检索索引**。

## 格式规范（严格）

```
## YYYY-MM-DD #<type> scope:<name> [#<extra-tag>...] - <一句话主题>

- Why: <一句话动机，不复述 what>
- 详见: <path 或 commit hash>
```

**硬约束**：
- 日期必须 ISO 格式 `YYYY-MM-DD`
- 类型标签必须以 `#` 开头，从下面字典选一个为主标签
- 作用域必须 `scope:<name>` 形式，name 用 kebab-case；多模块改动用多个 `scope:`
- Why 一行不超过 80 字符
- **不贴 diff、不复述 what**——那些进 commit 或模块自己的文档

## 类型标签字典

| 标签 | 含义 |
|---|---|
| `#feat` | 新功能 |
| `#fix` | bug 修复 |
| `#refactor` | 重构（无行为变化） |
| `#perf` | 性能优化 |
| `#docs` | 文档变更 |
| `#test` | 测试相关 |
| `#chore` | 构建/依赖/工具链/初始化 |
| `#infra` | 基础设施 / 部署 / 同步 / 运维 |
| `#archive` | 归档/弃用 |
| `#breaking` | 破坏性变更（叠加） |
| `#deprecated` | 标记弃用（叠加） |
| `#wip` | 进行中（叠加） |

## scope 字典（本项目）

| scope | 对应 |
|---|---|
| `init` | 三件套初始化 |
| `note-editor` | 右侧笔记编辑器（CodeMirror 6 / TOAST UI / 持久化） |
| `note-pack` | 笔记原料包导出 |
| `dict` | 词典通道与单词卡 |
| `tts` | TTS（讯飞双引擎 / 豆包） |
| `llm` | LLM Provider / 系统提示词 |
| `translate` | 免费翻译 Provider |
| `ocr` | 截屏 + Vision OCR |
| `hotkey` | 全局快捷键 |
| `secret` | 密钥存储（Keychain → FileSecretStore） |
| `ui` | 主界面 / 主题 / 设置页 |
| `sync` | Syncthing 跨机同步 |
| `docs` | 项目内文档 |

## 检索示例

```bash
grep -E "^## .* #feat .* scope:note-editor" CHANGELOG.md   # 笔记编辑器新功能
grep "#breaking" CHANGELOG.md                              # 所有破坏性变更
grep "^## 2026-05" CHANGELOG.md                            # 2026-05 所有动作
grep "scope:sync" CHANGELOG.md                             # 同步基础设施改动
```

---

## 2026-06-04 #infra scope:sync scope:secret - secrets.enc 排出 Syncthing 防跨机解不开 + T22 立项

- Why: T17 FileSecretStore 用本机硬件 UUID 派生根密钥，secrets.enc 同步到别机 GCM 解不开 → key 全静默失效
- 详见: 两台机各自 `.stignore` 加 `secrets.enc` + `secrets.sync-conflict-*.enc` 排除（`.stignore` 不跨机同步，要逐机配）；mac mini 端清 4 个历史 sync-conflict 残留（secrets/tts-config/results）入废纸篓；mac mini 本机重录 LLM/讯飞/豆包 key 验证可用，笔记本本机 key 本来 work；永久方案 `project-board.md` T22（PBKDF2-SHA256 + verifier 文件格式 v2 + UnlockView 启动 gate + 记住到本机 Keychain 勾选 + 不允许空密码，PLANNED）；AGENTS.md §3.2 加 Syncthing 跨机同步注意事项段

## 2026-06-01 #feat scope:note-editor scope:sync - 笔记顶栏 ⟳ 刷新按钮 + ⌘R，跨机同步无需重启 app

- Why: Syncthing 推过来的 manifest / 新 draft 在运行中的 app 里看不到，原来要重启 app 才刷新
- 详见: `NoteDocumentsViewModel.reload()`（diff manifest，新增 entry 入 tab、消失 entry 仅 clean 时关，selectedID 保留）/ `NoteEditorViewModel.reloadFromDisk()`（dirty/saving/failed 时跳过，保护用户内存内容）/ `MainWindowView.noteTabBar`（plus 旁的 `arrow.clockwise` 按钮 + `keyboardShortcut("r", modifiers: .command)`）

## 2026-06-01 #infra scope:sync - Syncthing mini 端接入 + manifest conflict 合并恢复

- Why: relay-task §-1 写"三端 P2P 上线"但 mini 端实际未接入；接入过程因启动验证 app 触发 manifest 重写而导致 mini 旧 3-entry 覆盖 MacBook 8-entry 成 winner，需手动合并恢复
- 详见: `brew install syncthing` + `brew services start syncthing`；REST API 加 MacBook device(no autoAccept) + 配两个 folder + 写 .stignore（按 ADMIN §6.3）；mini 沙盒 `notes/manifest.sync-conflict-*-P733ZOD.json` 8-entry 合 winner 3-entry → 11 entries 写回 manifest.json，备份 `notes/manifest.before-merge-20260601-230341.bak`；secrets/tts-config/results conflict 副本按用户决策原样保留

## 2026-06-01 #infra scope:sync - Syncthing 接入 mac mini，3 端 mesh 拓扑成型

- Why: mac mini M4 到家，要加入既有 MacBook↔ECS 同步网；走 REST API 避免开浏览器
- 详见: ~/Documents/my_huoshan_web/ADMIN.md §6.2（mini Device ID + 当前拓扑声明 + 变更日志 2026-06-01）

## 2026-06-01 #docs scope:init - 三件套入口文档落地

- Why: 项目历经 T00–T17 + 多轮 P5 增量已成熟，需 agent 入口、人类导航、可 grep 的演绎记录
- 详见: AGENTS.md（已合并通用守则 4 段） / INDEX.md / 本文件 / CLAUDE.md→AGENTS.md 软链

## 2026-05-30 #feat scope:note-editor - 词卡只存音频链接（不下载 MP3）

- Why: 词卡 MD 直接指远端音频更简洁，省盘空间，跟 Syncthing 同步友好
- 详见: commit b6af2ac

## 2026-05-30 #infra scope:sync - Syncthing 上线，App 数据三端 P2P 实时同步到火山云 ECS

- Why: MacBook ↔ Mac mini ↔ ECS 三端要笔记草稿/词卡秒级互通，结束手动 rsync
- 详见: ~/Documents/my_huoshan_web/ADMIN.md §6（folder `pa-appsupport` + `pa-words`，`.stignore` 排除 `tts-audio/` / `_audio/`）

## 2026-05-30 #feat scope:dict scope:note-editor - 词典出 markdown 卡 + 编辑器 Cmd+Click 跳浏览器

- Why: 双击词条直接产可入库的 md（含有道详解外链），编辑器里 ⌘+点击链接跳浏览器符合直觉
- 详见: commit 3e70b15

## 2026-05-30 #refactor scope:note-editor - 笔记编辑器 TOAST UI → CodeMirror 6 live-preview

- Why: TOAST UI WYSIWYG 黑盒太多 + 中文 IME 偶发抖动；CM6 装饰渲染保留 markdown 源码可控
- 详见: commit c98145e / tools/cm6-build/

## 2026-05-29 #feat scope:ui scope:tts scope:llm - 设置页四 tab 化 + LLM 参数化 + 豆包 TTS 第三引擎

- Why: 5 tab 拥挤；LLM baseUrl/model 硬编码不灵活；用户要接豆包 V1 一句话 TTS
- 详见: commit d3bafd2（豆包 cluster `volcano_tts` / `loudness_ratio` 坑见 memory project_doubao_tts）

## 2026-05-19 #feat scope:ui - Claude 配色主题 + TTS 顶栏化 + 动态双色夜间模式

- Why: 默认 SwiftUI 配色单调；TTS 频繁用需要顶栏化省鼠标行程
- 详见: commit 5e7410f / 6d5dabc

## 2026-05-18 #feat scope:dict - 有道词典通道 V4 + 单词卡片本地存储

- Why: 翻译之外要"查词"语义，词条要可沉淀到 ~/knowledge/words/ 复用
- 详见: commit 33a7ff8

## 2026-05-18 #feat scope:tts - TTS 真·实时调速 + 引擎切换按钮

- Why: 调速要边听边调，不要停了再放；普通/超拟人切换要一键
- 详见: commit ae72e88

## 2026-05-17 #feat scope:note-editor scope:secret - 划词进草稿 + 草稿撤销重做 + 密钥改 FileSecretStore

- Why: 开发期重签致 Keychain ACL 漂移反复弹密码；划词要能直接喂草稿不用复制
- 详见: commit 7e75ec76 / e75ec76（AES-GCM + 硬件 UUID 派生根密钥，PR #5）

## 2026-05-17 #feat scope:note-editor scope:note-pack - 笔记编辑区 + 多草稿 Tab + 原料包导出

- Why: 翻译结果要能沉淀成结构化笔记，导出 md 给下游知识库 Claude 消化
- 详见: PR #3/#4（commits 1faf8f1 / dc29c3e）/ design-note-export-pack.md

## 2026-05-17 #feat scope:ui scope:translate scope:hotkey - Easydict 风格 UI + 划词翻译 + 设置体系

- Why: 临时 MVP UI 不够日常用；选中文字按热键直接翻译是核心场景
- 详见: PR #1/#2（T13/T14/T15）

## 2026-05-16 #feat scope:tts - 讯飞 TTS 双引擎（普通 + 超拟人）

- Why: MVP 需要稳定 TTS 闭环；超拟人音色质量明显更好
- 详见: project-board.md T10 / commits 见 §P3

## 2026-05-16 #chore scope:init - SwiftUI 工程骨架 + 契约层 + 垂直闭环

- Why: P0–P1 阶段产物：稳定契约 → 剪贴板→LLM→JSONL→展示 端到端跑通
- 详见: project-board.md T00–TC / T07a / T11a / T-UI1

<!-- 新条目加在这里上方，保持最新在最上 -->
