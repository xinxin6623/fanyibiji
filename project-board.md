# Project Board

## 总体目标

构建一个个人使用的 macOS 助理型 App MVP。它参考 Easydict 的能力边界，
但默认干净重写，先打通截屏、OCR、划线或剪贴板取词、LLM 查询、免费翻译、
指定 TTS API 和结构化结果记录。

## 当前里程碑

- 当前里程碑：M2 本地配置与密钥边界准备。
- 当前状态：基础规则、`relay-task.md` 交接文档、项目看板、MVP PRD 和 SwiftUI 工程骨架
  已建立；T02 已完成构建和测试验证。
- 下一推荐任务：进入 `T03 本地配置与密钥边界`。
- 当前待确认项：TTS API 供应商、免费翻译 provider 和未来分发策略；这些
  不阻塞 T02 App 骨架。

## 状态枚举

- `TODO`：尚未开始。
- `READY`：信息足够，可以进入 Admin 规划或执行。
- `IN_PROGRESS`：正在处理。
- `BLOCKED`：被外部决策、依赖或环境阻塞。
- `DONE`：已完成并通过当前阶段验收。

## 任务看板

| ID | 任务 | 状态 | 依赖 | 交付物 |
| --- | --- | --- | --- | --- |
| T00 | 项目文档骨架 | DONE | 无 | `AGENTS.md`、`relay-task.md`、`project-board.md` |
| T01 | MVP PRD | DONE | T00 | `prd-mvp.md` |
| T02 | SwiftUI App 骨架 | DONE | T01 | 可构建的 macOS App 工程 |
| T03 | 本地配置与密钥边界 | READY | T02 | 本地配置模型、Keychain/API key 边界 |
| T04 | 全局快捷键与输入入口 | TODO | T02 | 快捷键注册、入口路由 |
| T05 | 截屏区域选择 | TODO | T04 | 截屏区域选择与图片输出 |
| T06 | Vision OCR | TODO | T05 | OCRResult 与 Vision OCR pipeline |
| T07 | LLM Provider | TODO | T03、T06 | OpenAI-compatible provider |
| T08 | 划线/剪贴板取词 | TODO | T04 | 选中文本或剪贴板输入链路 |
| T09 | 免费翻译 Provider | TODO | T03、T07 | 一个稳定翻译 provider |
| T10 | 指定 TTS Provider | TODO | T03 | 可配置 TTS provider 与播放链路 |
| T11 | 结构化结果与本地历史 | TODO | T07、T09、T10 | ResultModel 与本地历史记录 |

## 任务详情

### T00 项目文档骨架

- 目标：建立 Agent 规则、交接文档和项目看板。
- 状态：DONE。
- 依赖：无。
- 交付物：`AGENTS.md`、`relay-task.md`、`project-board.md`。
- 验收标准：新会话能按固定顺序理解项目状态；看板能看到下一任务。
- 备注：`relay-task.md` 是唯一项目交接文件；`handoff.md` 已废弃，只能作为旧入口跳转说明，不维护并行状态。

### T01 MVP PRD

- 目标：用 `skill_prd_sync` 锁定 MVP 需求、非目标、数据流、权限和验收。
- 状态：DONE。
- 依赖：T00。
- 交付物：`prd-mvp.md`。
- 验收标准：包含需求背景、数据流向图描述、容灾设计和明确验收标准。
- 备注：已采用默认决策：个人本地、助理式单窗口、剪贴板兜底、JSONL 历史。

### T02 SwiftUI App 骨架

- 目标：创建干净重写的 macOS SwiftUI App 工程。
- 状态：DONE。
- 依赖：T01。
- 交付物：可构建的 App 工程、基础目录和空白主界面。
- 验收标准：本机可 build；不包含 Easydict 源码复制内容。
- 备注：已创建 `PersonalAgent.xcodeproj`、`PersonalAgent/` 推荐目录、
  SwiftUI 入口、空白主窗口、本地化占位、资源占位和测试 target；
  `plutil -lint PersonalAgent.xcodeproj/project.pbxproj` 通过，
  `swiftc -parse` 通过，`xcodebuild build/test` 通过。为适配命令行沙盒
  验证，骨架阶段不保留非必要 `#Preview` 宏；验证使用仓库内
  `.DerivedData`，并已加入 `.gitignore`。

### T03 本地配置与密钥边界

- 目标：定义本地配置模型和敏感信息保存边界。
- 状态：READY。
- 依赖：T02。
- 交付物：配置模型、Keychain 或本地安全配置方案、示例占位说明。
- 验收标准：API key 不进入仓库；配置缺失时有明确错误。
- 备注：不要修改或覆盖 `.env`。

### T04 全局快捷键与输入入口

- 目标：建立全局快捷键和输入路由。
- 状态：TODO。
- 依赖：T02。
- 交付物：快捷键注册、输入入口和动作分发。
- 验收标准：能区分截图、取词、手动输入等入口。
- 备注：需要处理快捷键冲突和授权失败。

### T05 截屏区域选择

- 目标：实现区域截图和图片元信息输出。
- 状态：TODO。
- 依赖：T04。
- 交付物：截图 UI、区域选择、NSImage/Data 输出。
- 验收标准：支持取消、多屏基本场景和权限失败提示。
- 备注：截图模块不能直接调用 LLM。

### T06 Vision OCR

- 目标：用 Apple Vision 实现本地 OCR。
- 状态：TODO。
- 依赖：T05。
- 交付物：OCRResult、文本整理和失败状态。
- 验收标准：图片输入能返回结构化 OCR 结果；空结果有明确错误。
- 备注：OCR 层不做翻译。

### T07 LLM Provider

- 目标：实现一个 OpenAI-compatible LLM provider。
- 状态：TODO。
- 依赖：T03、T06。
- 交付物：provider adapter、validate、timeout、cancel、错误模型。
- 验收标准：能把 OCR 或文本输入转成结构化查询结果。
- 备注：API key 只走本地配置或 Keychain。

### T08 划线/剪贴板取词

- 目标：实现选中文本或剪贴板输入链路。
- 状态：TODO。
- 依赖：T04。
- 交付物：文本提取入口、剪贴板保护、失败状态。
- 验收标准：取词失败不触发空查询；不永久破坏用户剪贴板。
- 备注：PRD 已默认 MVP 使用剪贴板兜底；正式版再补 Accessibility、
  AppleScript 和模拟复制链路。

### T09 免费翻译 Provider

- 目标：接入一个免费翻译 provider。
- 状态：TODO。
- 依赖：T03、T07。
- 交付物：TranslationResult 和一个 provider adapter。
- 验收标准：可完成基本文本翻译；provider 失败不影响 LLM 查询。
- 备注：逆向 Web API 必须隔离，不能成为核心业务依赖。

### T10 指定 TTS Provider

- 目标：接入指定 TTS API 并完成播放链路。
- 状态：TODO。
- 依赖：T03。
- 交付物：TTSProvider、播放层和失败兜底。
- 验收标准：能按配置请求音频并播放；鉴权失败有明确错误。
- 备注：具体 TTS 供应商和音频格式待 James 确认。

### T11 结构化结果与本地历史

- 目标：保存查询、翻译、OCR 和 TTS 的结构化结果。
- 状态：TODO。
- 依赖：T07、T09、T10。
- 交付物：ResultModel、本地历史记录和基础读取接口。
- 验收标准：结果包含 id、source、content、provider、created_at、tags、
  error；未来知识库可订阅。
- 备注：存储方案待 PRD 阶段锁定。

## 看板维护规则

- 每次任务完成后更新状态、备注和下一推荐任务。
- 新任务必须有 ID、目标、状态、依赖、交付物和验收标准。
- 不在看板记录长过程日志；只记录能影响后续执行的事实。
- 遇到阻塞时标记 `BLOCKED`，并写清楚缺的决策或依赖。
