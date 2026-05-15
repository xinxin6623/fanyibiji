# 可行性审查文档 — Personal Agent MVP

- **审查时间戳**：2026-05-15 12:50:18 CST (UTC+0800)
- **审查范围**：当前项目目录全部文档与 `PersonalAgent` Xcode 工程骨架
- **审查人**：Claude (claude-opus-4-7)
- **审查方法**：文档一致性核对 + 实机构建/测试验证 + GPL 合规扫描

---

## 0. 结论速览

| 维度 | 结论 | 说明 |
| --- | --- | --- |
| 总体可行性 | **可行** | 需求边界清晰，技术路线均为 macOS 原生成熟能力 |
| T02 骨架状态 | **实际已 DONE，文档标记错误** | 文档写 `BLOCKED`，实机 `BUILD SUCCEEDED` + `TEST SUCCEEDED` |
| 阻塞项 | **已解除（文档未同步）** | 本机已装 Xcode 26.5，非文档所述"未安装完整 Xcode" |
| 高风险项 | 2 个待 James 决策 | TTS 供应商未定、免费翻译 provider 法律/稳定性 |
| 立即应做 | 同步文档 + 首次 git commit | 仓库当前 0 commit，全部文件未纳入版本控制 |

---

## 1. 实机验证结果（本次审查实测）

| 验证项 | 命令 | 结果 |
| --- | --- | --- |
| 工程文件语法 | `plutil -lint project.pbxproj` | `OK` |
| App 构建 | `xcodebuild build -scheme PersonalAgent -destination platform=macOS` | **BUILD SUCCEEDED** |
| 单元测试 | `xcodebuild test ...` | **TEST SUCCEEDED**（1 用例通过） |
| GPL 合规扫描 | `grep -rn "Easydict\|tisfeng" PersonalAgent*` | 无任何匹配，未复制源码 |
| 部署目标 | `MACOSX_DEPLOYMENT_TARGET` | `13.0`，符合规划 |
| Bundle ID | `PRODUCT_BUNDLE_IDENTIFIER` | `com.james.personalagent`，符合 T02 计划 |

> 工程骨架真实可构建可测试，T02 验收标准全部满足。

---

## 2. 文档一致性问题（必须修正）

### 2.1 

### 2.2 中：仓库零提交
- `git log` → *"current branch 'main' does not have any commits yet"*；所有文件均为 `??` 未跟踪。
- 没有任何版本快照，误删/回滚无保护，"最近变更摘要"无 Git 支撑。
- **行动**：建立 `.gitignore`（排除 `DerivedData/`、`*.xcuserstate`、本地配置/密钥）后做首次 commit。

### 2.3 低：Swift 版本表述不一致
- 规范文档写 `Swift 5.9`，工程实际 `SWIFT_VERSION = 5.0`（语言模式，非工具链版本，Xcode 26 工具链远高于此）。
- 不影响构建，但建议在文档注明"5.0 指语言兼容模式"或显式设为 `5.9` 以消除歧义。

---

## 3. 需求与架构可行性

### 3.1 技术路线 — 全部可行
| 功能 | 技术方案 | 可行性 | 备注 |
| --- | --- | --- | --- |
| 截屏区域选择 | ScreenCaptureKit / CGWindowListCreateImage | 高 | macOS 原生，需屏幕录制权限兜底 |
| OCR | Vision `VNRecognizeTextRequest` | 高 | 本地、离线、零成本，最稳的一环 |
| 划线/取词 | MVP 剪贴板兜底 → 后续 Accessibility | 高 | 决策已收敛，风险已规避 |
| LLM 查询 | OpenAI-compatible HTTP provider | 高 | 协议标准，需 timeout/cancel/validate |
| 免费翻译 | 逆向 Web API（隔离层） | **中** | 见 §4 风险，已要求隔离不做核心依赖 |
| TTS | 可配置 provider 接口 | **中** | 供应商/鉴权/格式未定，接口先行合理 |
| 结构化结果 | JSONL 本地历史 | 高 | 轻量、可演进至 SQLite/SwiftData |

### 3.2 架构判断（第一性原理视角）
- **modular monolith + 标准数据流（Input→Recognition→QueryContext→Provider→Result→Persistence）合理**：当前是无状态工具流，未引入重型 Event Bus 是正确的克制。
- **ResultModel 作为唯一持久化订阅点**：为未来笔记/知识库/任务看板预留了正确的接缝，符合"状态跃迁"判断。
- **目录骨架**与 T02 计划一致（`App/UI/Core/Features/Resources`），空目录用 `.gitkeep` 占位，合理。
- 无过度设计：T02 未提前实现任何业务逻辑，边界守得住。

---

## 4. 风险登记册

| # | 风险 | 等级 | 影响 | 缓解 / 待决 |
| --- | --- | --- | --- | --- |
| R1 | 免费翻译逆向 Web API：稳定性 + 服务条款/法律灰区 | **高** | provider 随时失效；若未来分发涉合规 | 已隔离为可替换层；建议 MVP 起就备一个官方免费额度 API 作为可切换项 |
| R2 | 指定 TTS 供应商/鉴权/音频格式/是否流式全未定 | **高** | T10 无法落地实现，仅能做空接口 | **需 James 决策**（见 §6） |
| R3 | GPL-3.0 边界 | 中 | 若未来闭源/分发且复制了 Easydict 源码则违约 | 当前扫描干净；保持干净重写，分发前重审签名/公证/许可 |
| R4 | macOS 权限链（屏幕录制/Accessibility/剪贴板） | 中 | 权限失败导致功能静默失效 | PRD 已要求每类失败可区分；需在 T04/T05/T08 落实测试 |
| R5 | 仓库零提交，无版本保护 | 中 | 误操作不可回滚 | 立即首次 commit + `.gitignore` |
| R6 | 文档交接过时（T02 状态错误） | 中 | 新会话决策被误导 | 本审查后立即同步 §2.1 |
| R7 | API key 泄露 | 中 | 密钥进仓库/日志 | T03 须落地 Keychain/本地配置；`.gitignore` 先行 |
| R8 | LLM/TTS 长文本与超时 | 低 | 请求卡死或截断 | provider 统一 timeout/cancel；TTS 长文本分段 |

---

## 5. 关键路径与依赖

```
T02(DONE) ──┬─> T03 配置/密钥边界 ──┬─> T07 LLM Provider ──┐
            │                       │                      ├─> T11 结构化结果/历史
            ├─> T04 快捷键/输入 ──┬─> T05 截屏 ─> T06 OCR ─┘
            │                     └─> T08 取词 ─────────────┐
            └─> T10 TTS(被R2阻塞) ─────────────────────────┘
                T09 免费翻译(依赖T03/T07, 受R1制约)
```

- **关键路径**：T03 → T07 → T11（LLM 主闭环），应优先推进。
- **可并行**：T04/T05/T06（输入+OCR 链）与 T03/T07（密钥+LLM）相互独立。
- **建议暂缓**：T10（被 R2 阻塞，只能做空接口，不投入实现）。

---

## 6. 需 James 决策的事项（阻塞后续）

1. **TTS 供应商**：哪家 API？鉴权方式（API key / OAuth）？音频返回格式（mp3/wav/pcm）？是否要求流式播放？ — 不定则 T10 只能空接口。
2. **免费翻译 provider 第一版**：接受逆向 Web API 的失效/合规风险，还是优先用某官方免费额度 API？
3. **未来是否对外分发**：决定 GPL/签名/公证策略；若可能分发，须从现在起严守干净重写并记录来源。
4. **首次 commit 授权**：是否现在建立 `.gitignore` 并做初始提交（不含任何密钥/DerivedData）。

---

## 7. 建议行动清单（按优先级）

| 优先级 | 行动 | 理由 |
| --- | --- | --- |
| P0 | 同步文档：T02→DONE，M1 完成，下一任务→T03 | 消除 §2.1 错误交接 |
| P0 | 建 `.gitignore` + 首次 git commit | 消除 §2.2/R5/R7 无版本保护 |
| P1 | James 决策 §6 第 1、2 项 | 解除 T10/T09 设计阻塞 |
| P1 | 进入 T03：落地 Keychain/本地配置边界 | 关键路径起点，R7 缓解前置 |
| P2 | 文档注明 Swift 版本语义 | 消除 §2.3 歧义 |
| P2 | T09/T10 设计先行：定义可替换 provider 协议 | 把 R1/R2 风险隔离在接口后 |

---

## 8. 审查声明

- 本文档改动文件：仅新增本文件 `feasibility-review.md`，未修改任何现有文档或代码。
- 已运行验证：`plutil -lint`、`xcodebuild build`、`xcodebuild test`、GPL 源码扫描、Git/Xcode 环境检查 — 均见 §1。
- 未运行验证：App 实际 UI 运行交互（骨架仅占位文案，无交互逻辑，无需 UI 测试）。
- 剩余风险：见 §4 风险登记册，其中 R1/R2 需 James 决策方可关闭。
