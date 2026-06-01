# fanyibiji（PersonalAgent）

个人 macOS 助理 App：截屏 OCR + 划词翻译 + LLM 查询 + 双引擎 TTS + 笔记原料包导出，配 Syncthing 跨机实时同步到火山云 ECS。

> 🤖 Agent 上手先读 [`AGENTS.md`](./AGENTS.md) 的操作守则；改动告一段落后追加 [`CHANGELOG.md`](./CHANGELOG.md)（强标签格式见文件顶部）。

## 项目结构

```
fanyibiji/
├── PersonalAgent/                源代码（Swift / SwiftUI macOS App）
├── PersonalAgent.xcodeproj/      Xcode 工程文件（显式引用式 pbxproj）
├── PersonalAgentTests/           XCTest 单测
└── tools/                        辅助工具（含 cm6-build：CodeMirror 6 编辑器 bundle 源）
```

## 子模块导航

| 路径 | 用途 |
|---|---|
| [`PersonalAgent/`](./PersonalAgent/) | App 主代码：`App/`（组合根/生命周期）、`Core/`（契约/配置/持久化/服务）、`Features/`（Provider/采集/识别/整合）、`UI/`（SwiftUI + WKWebView 笔记编辑器）、`Resources/` |
| [`PersonalAgent.xcodeproj/`](./PersonalAgent.xcodeproj/) | Xcode 工程；显式引用式 pbxproj，**新增 Swift 文件需手动补 4 处** |
| [`PersonalAgentTests/`](./PersonalAgentTests/) | XCTest 单测（按 T 编号组织：T03/T04/.../T16/T17） |
| [`tools/cm6-build/`](./tools/) | CodeMirror 6 live-preview 编辑器构建脚本，产物落到 `PersonalAgent/Resources/InlineEditor/` |

### 设计 / 历史档（项目根）

| 文档 | 用途 |
|---|---|
| [`project-board.md`](./project-board.md) | 任务看板（T00–T17，P-1 → P5 增量，状态 / 依赖 / 交付物） |
| [`relay-task.md`](./relay-task.md) | 接力单（当前会话事实、关键决策、下一步） |
| [`prd-mvp.md`](./prd-mvp.md) | MVP PRD 立项快照（数据流、容灾、验收） |
| [`design-note-export-pack.md`](./design-note-export-pack.md) | 笔记原料包导出设计稿（已实现，T16） |
| [`知识库结构.md`](./知识库结构.md) | `~/knowledge/` 体系与 App 侧边界 |
| [`feasibility-review.md`](./feasibility-review.md) | 立项可行性分析（历史档） |
| [`T02-admin-plan.md`](./T02-admin-plan.md) | SwiftUI 骨架执行规划（历史档） |
| [`想法.md`](./想法.md) / [`gimini想法.md`](./gimini想法.md) | 原始需求与 Gemini 侧记录（历史档） |
| [`临时位置.md`](./临时位置.md) | App 运行时数据落盘位置速查表（含 Syncthing 同步声明） |
| [`handoff.md`](./handoff.md) | 已废弃，跳转到 relay-task.md |

## 常用操作

```bash
# 构建（开发期，本地自签）
xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent \
  -derivedDataPath build CODE_SIGN_IDENTITY="-"

# 测试（跑前先杀残留进程，否则 runner 挂起）
pkill -x PersonalAgent; xcodebuild test -project PersonalAgent.xcodeproj -scheme PersonalAgent

# 重建笔记编辑器 bundle（改了 tools/cm6-build/src/ 之后）
cd tools/cm6-build && pnpm build

# 看 InlineEditor 诊断日志
/usr/bin/log show --predicate 'subsystem == "com.james.personalagent" AND category == "InlineEditor"' --info --last 1m

# 看跨机同步状态（Syncthing → 火山云 ECS）
ssh volcano 'systemctl is-active syncthing@james'
```

## 运行时数据位置

详见 [`临时位置.md`](./临时位置.md)。要点：

- `~/Library/Application Support/com.james.personalagent/` — 配置 / `secrets.enc` / `results.jsonl` / `notes/` 草稿 / `tts-audio/`
- `~/knowledge/words/` — 词典双击保存的词卡（与笔记知识库并存，可被 `[[wiki-link]]` 命中）
- **跨机同步**（2026-05-30 上线）：上述两路径经 Syncthing folder `pa-appsupport` / `pa-words` 实时同步到火山云 ECS（`volcano`），三端 P2P；运维详见 `~/Documents/my_huoshan_web/ADMIN.md §6`

## 相关链接

- 📓 演绎记录：[CHANGELOG.md](./CHANGELOG.md)
- 🤖 Agent 守则：[AGENTS.md](./AGENTS.md)
- 🌐 仓库：github.com/xinxin6623/fanyibiji
- 🖥️ 同步服务器：火山云 ECS `volcano`（115.190.215.222），运维入口 `~/Documents/my_huoshan_web/ADMIN.md`
