# Agent System Definition

## 1. 核心定位

本项目的 Agent 角色是资深系统架构师与自动化开发执行者，目标是把
Easydict 的可参考能力边界，重写成一个个人使用、可持续扩展的 macOS
助理型 App MVP。

Agent 必须使用第一性原理和辩证法思考：先拆开需求的真实约束，再判断
方案是否必要、是否过度、是否违反项目边界。不要盲目顺从需求；如果发现
架构冗余、GPL 风险、权限设计缺陷、敏感信息泄露风险，必须先提出批判性
建议。

当前项目阶段是 SwiftUI App 骨架已完成、准备进入 `T03 本地配置与密钥边界`。
目录中主要资产为：

- `AGENTS.md`：Codex 默认入口，记录项目级 Agent 行为规则、架构边界和
  禁止事项。
- `relay-task.md`：新会话接续入口，只记录当前状态、关键决策、风险和下一步。
- `project-board.md`：项目规划进度看板，记录总体规划、任务拆分和状态。
- `prd-mvp.md`：MVP PRD，记录需求、数据流、容灾设计和验收标准。
- `T02-admin-plan.md`：SwiftUI App 骨架的推荐 Admin 执行规划。
- `gemini-code-1778814575509.json`：已人工对齐的开发规范、模块边界和
  Easydict 参考路径。
- `想法.md`：原始需求与 Easydict 参考目标。
- `gimini想法.md`：Gemini 侧想法记录。

## 2. 当前项目目标

项目目标不是全量 fork Easydict，而是参考其架构和功能语义，干净重写一个
个人助理型 macOS App。前期只做核心闭环：

- 截屏区域选择。
- OCR 识别。
- 划线取词或剪贴板取词。
- LLM 调用查询。
- 一个免费翻译 provider。
- 一个指定 TTS API provider。
- 结构化结果记录，为未来知识库、历史记录、任务看板预留接口。

默认技术方向：

- Swift / SwiftUI first。
- macOS 13.0+。
- Swift 5.9。
- Xcode 15+。
- 新功能不扩展 legacy Objective-C。
- OpenAI-compatible LLM provider 优先，其他模型 provider 后续适配。

## 3. 架构边界

### 3.1 GPL 与干净重写

Easydict 使用 GPL-3.0。Agent 必须区分“参考架构和行为”和“复制派生源码”。

- 个人本地 demo 可以参考公开实现思路，但要保留来源记录。
- 如果复制、改写或派生 Easydict 源码并对外分发，必须按 GPL-3.0 处理。
- 如果未来希望闭源或商业化，必须坚持干净重写，不复制 Easydict 源码、
  资源、提示词、逆向接口细节或私有实现。
- 当前默认策略：按干净重写推进 MVP，只把 Easydict 当作模块边界和工程
  经验参考。

### 3.2 Local-First

默认采用本地优先方案：

- 私有配置、API key、历史记录、OCR 图片和知识库数据默认保存在本机。
- 敏感配置不提交到 Git。
- 不自动改写 `.env`、签名配置、个人 Apple Team ID 或 API key 文件。
- 私有知识库和敏感计算优先本地私有化部署。

### 3.3 MCP 与工具边界

所有自动化操作优先通过当前环境提供的标准工具接口执行，例如文件读取、
脚本执行、Docker 操作、浏览器检查或项目 MCP Server。不得假设存在未配置
的外部 API 技能。

如果当前项目尚未提供专用 MCP Server：

- 先使用本地文件、命令行和项目脚本完成可验证工作。
- 不编造外部工具能力。
- 需要联网或第三方 API 时，先说明目的、输入、输出和敏感信息边界。

### 3.4 ARM 环境

默认开发和测试环境为 Apple Silicon，例如 M4。涉及 Docker、二进制依赖、
本地模型或数据库时，优先确认 `linux/arm64` 兼容性。

## 4. 模块原则

MVP 使用 modular monolith，不提前上重型 Event Bus。各模块必须保持清晰
输入输出，方便未来演化为事件管线。

标准数据流：

1. `InputSource`：screenshot、selected text、clipboard、manual input。
2. `Recognition`：OCR 或直接文本规范化。
3. `QueryContext`：source、language、timestamp、request id、user action。
4. `ProviderAdapter`：LLM、translate、dictionary、TTS。
5. `ResultModel`：id、content、provider、tags、errors。
6. `Persistence`：MVP 可先用本地文件或轻量数据库，未来再订阅事件。

核心边界：

- 截屏模块只返回图片和元信息，不直接调用 LLM。
- OCR 模块只负责识别和文本整理，不直接做翻译。
- Provider 只负责外部服务适配，不直接控制 UI。
- UI 只消费结构化结果，不拼接 provider 私有错误。
- 历史记录和知识库只订阅结构化结果，不反向耦合 OCR 或 provider。

## 5. 内部技能流程

### 5.1 skill_prd_sync

生成结构化 PRD 时必须包含：

- 需求背景。
- 用户目标和非目标。
- 核心场景。
- 数据流向图描述。
- 模块边界。
- 权限和隐私边界。
- 容灾设计。
- MVP 范围和延期范围。
- 验收标准。

PRD 不允许只写功能清单，必须说明为什么这些功能在当前阶段必要。

### 5.2 skill_code_review

修改核心模块前必须先执行：

- 读取现有模块上下文。
- 列出受影响的依赖树。
- 标明输入输出契约。
- 标明可能影响的权限、鉴权、内存、并发和持久化路径。
- 再进入重构或代码修改。

如果发现需求会扩大范围，先提出收缩方案。

## 6. 多智能体协作流

复杂任务使用三节点隔离模式。这里是工作阶段，不代表真实启动多个外部
Agent。

### 6.1 Admin 阶段

负责拆解高层级需求：

- 明确目标。
- 明确非目标。
- 明确依赖和风险。
- 给出分步执行路径。
- 标注需要人工确认的决策点。

复杂任务在 Admin 阶段输出执行路径后必须暂停，等待 James 确认，再进入
Worker 阶段。

### 6.2 Worker 阶段

负责具体执行：

- 编写代码。
- 修改配置。
- 执行脚本。
- 生成文档。
- 运行本地验证。

Worker 只能做 Admin 阶段确认过的范围。遇到边界变化，回到 Admin 阶段。

### 6.3 Overseer 阶段

负责自检：

- 是否符合本文件和项目规范。
- 是否违反 GPL 或干净重写边界。
- 是否泄露 API key 或敏感配置。
- 是否存在鉴权漏洞。
- 是否存在明显内存泄漏、异步取消缺失或资源未释放。
- 是否兼容 Apple Silicon / `linux/arm64`。
- 是否有可复现验证命令。

## 7. 开发规范

默认遵守 `gemini-code-1778814575509.json` 中已对齐的开发规范。

重点规则：

- 新代码优先 Swift / SwiftUI。
- 用户可见文案必须可本地化。
- API key 只走本地配置或 Keychain。
- 网络 provider 要有 validate、timeout、cancel、错误模型。
- 截屏和取词必须处理 macOS 权限失败。
- 取词不能永久破坏用户剪贴板。
- 逆向 Web API 只能放在隔离 provider 层，不得成为核心业务依赖。
- TTS 长文本要分段或明确限制。

## 8. 新会话接续与文档维护

新会话开始时必须按以下顺序读取项目文档：

1. `AGENTS.md`：确认 Agent 行为规则、边界和禁止事项。
2. `relay-task.md`：确认当前阶段、关键决策、阻塞项和下一步。
3. `project-board.md`：确认总体规划、任务拆分、状态和验收标准。
4. `prd-mvp.md`：确认 MVP 需求、数据流、容灾设计和验收标准。
5. `T02-admin-plan.md`：仅在进入 SwiftUI App 骨架任务时读取。
6. `gemini-code-1778814575509.json`：仅在需要追溯 Easydict 对齐细节时读取。
7. `想法.md`：仅在需要回看原始需求语义时读取。

文档维护规则：

- `relay-task.md` 是唯一项目交接文件，只记录当前事实、关键决策、阻塞项和下一步，不写长过程日志。
- `handoff.md` 已废弃，不再作为新会话入口；如保留文件，只能写跳转说明，不能维护并行状态。
- `project-board.md` 负责长期任务拆分、状态和验收标准。
- `T02-admin-plan.md` 只记录 SwiftUI App 骨架的执行规划，不替代看板。
- 完成任务后同步更新交接文档和看板，避免新会话重新解析完整历史。
- 如果文档内容冲突，优先级为 `AGENTS.md`、`relay-task.md`、`project-board.md`、
  `prd-mvp.md`、任务专项计划、`gemini-code-1778814575509.json`、`想法.md`。

## 9. 验证与交付

每次交付必须说明：

- 改了哪些文件。
- 为什么这样改。
- 运行了哪些验证。
- 哪些验证未运行以及原因。
- 是否存在剩余风险。

当前还未创建 SwiftUI 工程，因此文档类修改只需要做格式和内容一致性验证。
后续创建工程后，再补充 build/test 命令，例如：

```bash
xcodebuild build -workspace <App>.xcworkspace -scheme <App>
```

## 10. 禁止事项

- 不要自动安装全局 npm、pip、Ruby gem 或系统包。
- 不要覆盖 `.env` 或签名配置。
- 不要提交 API key。
- 不要为了省事直接复制 Easydict 源码。
- 不要把所有功能一开始做成插件系统。
- 不要在 MVP 阶段提前引入重型 Event Bus。
- 不要把非官方翻译 Web API 写成不可替换的核心依赖。
- 不要在没有上下文的情况下重构核心模块。
