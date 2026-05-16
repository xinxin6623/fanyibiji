# Project Board

## 总体目标

构建一个个人使用的 macOS 助理型 App MVP。参考 Easydict 的能力边界，
默认干净重写，打通截屏、OCR、划线或剪贴板取词、LLM 查询、免费翻译、
指定 TTS API 和结构化结果记录。

## 执行策略（2026-05-16 经 James 确认重排）

放弃原"水平分层"顺序，改为 **先定契约 → 最薄垂直闭环 → 再扩重路径 → 收敛硬化**。
理由：原顺序要等截屏+OCR 等最重、最易失败的环节做完才能跑通首个端到端闭环，
风险集中在后期；且缺少显式核心契约层，模块间契约会漂移、无法独立验证。

阶段划分（P0→P4），每阶段内任务对稳定契约编程，可独立 build/test。

## 验证标准（每个任务必须满足，经 James 确认）

1. 纯逻辑写单元测试（契约、错误分支、持久化读写、provider 失败隔离）。
2. 每个任务完成后执行：
   ```bash
   xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent
   xcodebuild test  -project PersonalAgent.xcodeproj -scheme PersonalAgent
   ```
3. 关键路径手动验收一次，并对照 `prd-mvp.md` §10 验收标准逐条核对。
4. 任务完成后同步更新本看板与 `relay-task.md`。

## 状态枚举

- `TODO`：尚未开始。
- `READY`：信息足够，可进入 Admin 规划或执行。
- `IN_PROGRESS`：正在处理。
- `BLOCKED`：被外部决策、依赖或环境阻塞。
- `DONE`：已完成并通过当前阶段验收。

## 阶段总览

| 阶段 | 目标 | 关键产物 | 状态 |
| --- | --- | --- | --- |
| P-1 | 文档与工程骨架 | 文档、可构建 SwiftUI 工程 | DONE |
| P0 | 核心契约层 | 纯类型与协议、统一错误模型 | DONE |
| P1 | 最薄垂直闭环 | 剪贴板→LLM→JSONL→展示 跑通 | READY |
| P2 | 截屏/OCR 重路径 | 快捷键、截屏、OCR、取词入口 | TODO |
| P3 | 次要 Provider | 免费翻译、指定 TTS | TODO |
| P4 | 收敛与硬化 | 容灾矩阵、本地化、历史读取 | TODO |

## 任务看板

| ID | 阶段 | 任务 | 状态 | 依赖 | 交付物 |
| --- | --- | --- | --- | --- | --- |
| T00 | P-1 | 项目文档骨架 | DONE | 无 | `AGENTS.md`、`relay-task.md`、`project-board.md` |
| T01 | P-1 | MVP PRD | DONE | T00 | `prd-mvp.md` |
| T02 | P-1 | SwiftUI App 骨架 | DONE | T01 | 可构建的 macOS App 工程 |
| TC  | P0 | 核心契约层 | DONE | T02 | 纯 Swift 模型 + ProviderAdapter 协议 + AgentError |
| T03 | P1 | 本地配置与密钥边界 | READY | TC | 本地配置模型、Keychain/API key 边界 |
| T07a | P1 | 最小 LLM Provider | TODO | TC、T03 | OpenAI-compatible provider（validate/timeout/cancel）|
| T11a | P1 | 最小 JSONL 持久化 | TODO | TC | ResultModel 的 JSONL 写入与读取 |
| T-UI1 | P1 | 主窗口接入垂直闭环 | TODO | T07a、T11a | 粘贴文本→查询→展示→落盘 UI |
| T04 | P2 | 全局快捷键与输入入口 | TODO | TC | 快捷键注册、入口路由 |
| T05 | P2 | 截屏区域选择 | TODO | T04 | 截屏区域选择与图片输出 |
| T06 | P2 | Vision OCR | TODO | T05 | OCRResult 与 Vision OCR pipeline |
| T08 | P2 | 划线/剪贴板取词 | TODO | T04 | 选中文本或剪贴板输入链路 |
| T09 | P3 | 免费翻译 Provider | TODO | T03、TC | 一个稳定翻译 provider |
| T10 | P3 | 指定 TTS Provider | BLOCKED | T03、TC | 可配置 TTS provider 与播放链路 |
| T07b | P3 | LLM Provider 硬化 | TODO | T07a | 多模型适配、重试、流式（如需）|
| T12 | P4 | 收敛与硬化 | TODO | P1–P3 | 容灾矩阵、本地化完整性、历史读取接口 |

## 任务详情

### P-1 已完成

T00 文档骨架、T01 MVP PRD、T02 SwiftUI 骨架均已 DONE 并通过构建验证
（`xcodebuild build/test` 通过，无 Easydict 源码复制）。详见 git 历史。

### TC 核心契约层（P0，已完成）

- 目标：定义整个数据流的稳定骨架，纯 Swift、零 I/O、可 100% 单测。
- 状态：DONE（2026-05-16，`xcodebuild build/test` 通过，10/10 单测绿）。
- 依赖：T02。
- 交付物：
  - `InputSource`（screenshot / selectedText / clipboard / manualInput）
  - `OCRResult`（文本、置信度、行块、语言提示、原图引用）
  - `QueryContext`（id、source、inputText、createdAt、languageHints、userAction）
  - `ResultModel`（id、contextId、provider、content、tags、error、createdAt）
  - `ProviderAdapter` 协议（validate / 执行 / 统一错误 / 可取消）
  - `AgentError` 统一错误模型（权限/网络/超时/取消/输入无效/持久化）
- 验收标准：所有类型有单元测试；不含任何网络/磁盘/系统权限调用；
  `xcodebuild test` 通过；与 `prd-mvp.md` §5 数据流一致。
- 落点：`Core/Models/{AgentError,InputSource,OCRResult,QueryContext,
  ResultModel}.swift`、`Core/Services/ProviderAdapter.swift`、
  `PersonalAgentTests/TCContractsTests.swift`。
- 编码契约（T11a 必须沿用）：`JSONEncoder` snake_case + `.iso8601`；
  **`.iso8601` 不含亚秒**，落盘时间精度到秒，历史比对/去重按秒处理。
- 决策落地：ProviderAdapter 基础协议 + LLM/Translate/TTS 子协议；
  错误统一 `throws AgentError`；`validate()` 仅形状检查、零网络。
- 备注：后续每个模块只对本层协议编程，禁止跨层私有耦合。

### T03 本地配置与密钥边界（P1）

- 目标：定义本地配置模型和敏感信息保存边界。
- 状态：TODO。
- 依赖：TC。
- 交付物：配置模型、Keychain 或本地安全配置方案、缺失配置的明确错误。
- 验收标准：API key 不进入仓库；配置缺失时返回 `AgentError` 明确分支；
  单测覆盖"有 key / 无 key / 非法 key"。
- 备注：不要修改或覆盖 `.env`；不需要真实 API key 即可完成边界。

### T07a 最小 LLM Provider（P1）

- 目标：实现一个 OpenAI-compatible LLM provider 的最小可用版本。
- 状态：TODO。
- 依赖：TC、T03。
- 交付物：实现 `ProviderAdapter` 的 LLM adapter，含 validate、timeout、
  cancel、结构化错误。
- 验收标准：文本输入能转成 `ResultModel`；超时/取消/鉴权失败可区分；
  单测用桩网络层覆盖成功与各失败分支。
- 备注：API key 只走 T03 的本地配置或 Keychain。

### T11a 最小 JSONL 持久化（P1）

- 目标：把 `ResultModel` 以 JSONL 追加写入本地并可读取。
- 状态：TODO。
- 依赖：TC。
- 交付物：JSONL 写入/读取接口，写入失败时内存保留并返回错误。
- 验收标准：每条记录含 id、source、content、provider、created_at、tags、
  error；单测覆盖写入、读取、写入失败兜底；不保存明文 API key。

### T-UI1 主窗口接入垂直闭环（P1）

- 目标：用最薄 UI 跑通端到端，证明架构成立。
- 状态：TODO。
- 依赖：T07a、T11a。
- 交付物：主窗口"粘贴文本 → 触发查询 → 展示结构化结果 → 落盘"。
- 验收标准：手动跑通一次剪贴板→LLM→JSONL；失败状态在 UI 可区分；
  UI 只消费结构化结果，不拼接 provider 私有错误；文案可本地化。

### T04 全局快捷键与输入入口（P2）

- 目标：建立全局快捷键和输入路由。
- 状态：TODO。
- 依赖：TC。
- 交付物：快捷键注册、输入入口、动作分发，复用 P1 已验证的查询管线。
- 验收标准：能区分截图、取词、手动输入入口；快捷键冲突与授权失败有提示。

### T05 截屏区域选择（P2）

- 目标：实现区域截图和图片元信息输出。
- 状态：TODO。
- 依赖：T04。
- 交付物：截图 UI、区域选择、NSImage/Data 输出。
- 验收标准：支持取消、多屏基本场景、屏幕录制权限失败提示；
  截图模块不直接调用 LLM。

### T06 Vision OCR（P2）

- 目标：用 Apple Vision 实现本地 OCR。
- 状态：TODO。
- 依赖：T05。
- 交付物：`OCRResult`、文本整理、失败状态。
- 验收标准：图片输入返回结构化结果；空结果/低置信度/权限失败可区分；
  OCR 层不做翻译。

### T08 划线/剪贴板取词（P2）

- 目标：实现选中文本或剪贴板输入链路。
- 状态：TODO。
- 依赖：T04。
- 交付物：文本提取入口、剪贴板保护、失败状态。
- 验收标准：取词失败不触发空查询；不永久破坏用户剪贴板。
- 备注：MVP 用剪贴板兜底；正式版再补 Accessibility/AppleScript/模拟复制。

### T09 免费翻译 Provider（P3）

- 目标：接入一个免费翻译 provider。
- 状态：TODO。
- 依赖：T03、TC。
- 交付物：`TranslationResult` 与一个实现 `ProviderAdapter` 的 adapter。
- 验收标准：可完成基本翻译；provider 失败不影响 LLM 主流程（隔离性单测）。
- 备注：逆向 Web API 必须隔离在可替换 provider 层，不得成为核心依赖。

### T10 指定 TTS Provider（P3，BLOCKED）

- 目标：接入指定 TTS API 并完成播放链路。
- 状态：BLOCKED。
- 依赖：T03、TC。
- 阻塞：等 James 决策 TTS 供应商、鉴权方式、音频格式、是否流式。
- 交付物：`TTSProvider`、播放层、失败兜底。
- 验收标准：按配置请求音频并播放；鉴权/网络/格式/文本过长错误可区分。
- 备注：可先做占位接口与配置，不阻塞 P1/P2。

### T07b LLM Provider 硬化（P3）

- 目标：在最小 LLM provider 基础上补多模型适配、重试与流式（如需）。
- 状态：TODO。
- 依赖：T07a。
- 验收标准：新增能力不破坏 P1 已验证的最小闭环回归。

### T12 收敛与硬化（P4）

- 目标：补齐容灾矩阵与交付质量。
- 状态：TODO。
- 依赖：P1–P3。
- 交付物：`prd-mvp.md` §8 八种失败路径全覆盖、统一 cancel/timeout、
  本地化完整性、历史读取接口。
- 验收标准：失败注入测试通过；`prd-mvp.md` §10 验收标准逐条满足。

## 看板维护规则

- 每次任务完成后更新状态、备注和下一推荐任务。
- 新任务必须有 ID、阶段、目标、状态、依赖、交付物和验收标准。
- 不在看板记录长过程日志；只记录能影响后续执行的事实。
- 遇到阻塞标记 `BLOCKED`，并写清缺的决策或依赖。
- 阶段内任务必须对 TC 契约层编程，禁止跨层私有耦合。
