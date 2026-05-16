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
| P1 | 最薄垂直闭环 | 剪贴板→LLM→JSONL→展示 跑通 | DONE |
| P2 | 截屏/OCR 重路径 | 快捷键、截屏、OCR、取词入口 | READY |
| P3 | 次要 Provider | 免费翻译、指定 TTS | TODO |
| P4 | 收敛与硬化 | 容灾矩阵、本地化、历史读取 | TODO |

## 任务看板

| ID | 阶段 | 任务 | 状态 | 依赖 | 交付物 |
| --- | --- | --- | --- | --- | --- |
| T00 | P-1 | 项目文档骨架 | DONE | 无 | `AGENTS.md`、`relay-task.md`、`project-board.md` |
| T01 | P-1 | MVP PRD | DONE | T00 | `prd-mvp.md` |
| T02 | P-1 | SwiftUI App 骨架 | DONE | T01 | 可构建的 macOS App 工程 |
| TC  | P0 | 核心契约层 | DONE | T02 | 纯 Swift 模型 + ProviderAdapter 协议 + AgentError |
| T03 | P1 | 本地配置与密钥边界 | DONE | TC | 本地配置模型、Keychain/API key 边界 |
| T07a | P1 | 最小 LLM Provider | DONE | TC、T03 | OpenAI-compatible provider（validate/timeout/cancel）|
| T11a | P1 | 最小 JSONL 持久化 | DONE | TC | ResultModel 的 JSONL 写入与读取 |
| T-UI1 | P1 | 主窗口接入垂直闭环 | DONE | T07a、T11a | 粘贴文本→查询→展示→落盘 UI |
| T04 | P2 | 全局快捷键与输入入口 | DONE | TC | 快捷键注册、入口路由 |
| T05 | P2 | 截屏区域选择 | DONE | T04 | 截屏区域选择与图片输出 |
| T06 | P2 | Vision OCR | DONE | T05 | OCRResult 与 Vision OCR pipeline |
| T08 | P2 | 划线/剪贴板取词 | READY | T04 | 选中文本或剪贴板输入链路 |
| T-INT2 | P2 | P2 整合与可视化验收 | TODO | T04,T05,T06,T08 | overlay+热键+截屏→OCR→查询 App 接线 |
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

### T03 本地配置与密钥边界（P1，已完成）

- 目标：定义本地配置模型和敏感信息保存边界。
- 状态：DONE（2026-05-16，`xcodebuild build/test` 通过，T03 11 单测绿，
  回归 TC 10 + skeleton 1 全绿）。
- 依赖：TC。
- 交付物：
  - `ProviderConfig`（非敏感值类型：`baseUrl`/`model`/`timeoutSeconds`，
    snake_case Codable，**不含 API key**）。
  - `SecretStore` 协议 + `KeychainSecretStore`（生产）+
    `InMemorySecretStore`/`FailingSecretStore`（单测桩）。
  - `ConfigStore.resolve(_:apiKeyRef:)` → `ResolvedProviderConfig`
    （**故意不 Codable**，含 apiKey 防误序列化）。
- 验收结果：API key 仅经 Keychain，不进仓库/不落 JSON；缺失/非法配置
  统一抛 `AgentError(.invalidInput)`，Keychain 底层失败原样透传
  `.persistence`；单测覆盖有 key / 无 key / 非法配置 / 失败透传。
- 落点：`Core/Config/{ProviderConfig,SecretStore,ConfigStore}.swift`、
  `PersonalAgentTests/T03ConfigTests.swift`。
- 编码契约坑（后续沿用）：属性命名避开缩略词大写——`.convertFromSnakeCase`
  把 `base_url` 解回 `baseUrl`，用 `baseURL` 会解码失败，故用 `baseUrl`。
- 决策落地（James 确认）：ProviderConfig 最小三字段；Keychain 真实实现 +
  协议抽象桩测（单测不触碰真实 Keychain）。

### T07a 最小 LLM Provider（P1，已完成）

- 目标：实现一个 OpenAI-compatible LLM provider 的最小可用版本。
- 状态：DONE（2026-05-16，`** TEST SUCCEEDED **`，T07a 12 单测绿，
  回归全绿）。
- 依赖：TC、T03。
- 交付物：`LLMHTTPClient` 协议（生产 `URLSessionLLMHTTPClient`，单测桩）；
  `OpenAICompatibleLLMProvider: LLMProvider` 消费 `ResolvedProviderConfig`，
  `validate()` 仅形状零网络，`complete` 走 `/chat/completions`。
- 验收结果：成功 → `AssistantResult`（含 model）；空输入 → `.invalidInput`；
  HTTP 401/4xx → `.providerRejected`，5xx 同类可重试；`URLError.timedOut`
  → `.timeout`，`.cancelled`/`CancellationError` → `.cancelled`，其它网络
  → `.network`；响应畸形/空 choices → `.providerRejected`。API key 仅进
  `Authorization` 头，不落日志、不入 `ResultModel`。
- 落点：`Core/Services/LLMHTTPClient.swift`、
  `Features/Providers/OpenAICompatibleLLMProvider.swift`、
  `PersonalAgentTests/T07aLLMProviderTests.swift`。
- 备注：多模型/重试/流式属 T07b；本任务只做最小闭环所需。

### T11a 最小 JSONL 持久化（P1，已完成）

- 目标：把 `ResultModel` 以 JSONL 追加写入本地并可读取。
- 状态：DONE（2026-05-16，`xcodebuild test` 通过，T11a 7 单测绿，
  回归全绿）。
- 依赖：TC。
- 交付物：`JSONLResultStore`（注入 `fileURL`）：`append`/`readAll`/
  `bufferedFailures`。一行一 JSON，snake_case+iso8601（时间精度到秒）。
- 验收结果：写入失败时记录留内存缓冲并抛 `AgentError(.persistence)`；
  缺失/空文件读取返回 `[]`；损坏行抛 `.persistence`（MVP 不静默跳过）；
  `ResultModel` 不含明文 key。单测覆盖写读 round-trip / 顺序 / 行分隔 /
  秒精度 / 缺失 / 空 / 损坏行 / 写失败兜底。
- 落点：`Core/Persistence/JSONLResultStore.swift`、
  `PersonalAgentTests/T11aJSONLStoreTests.swift`。
- 备注：失败重试与缓冲回刷、损坏行容错均推迟到 T12 硬化。

### T-UI1 主窗口接入垂直闭环（P1，已完成）

- 目标：用最薄 UI 跑通端到端，证明架构成立。
- 状态：DONE（2026-05-16，`** TEST SUCCEEDED **`，TUI1 5 单测绿，
  回归全绿）。
- 依赖：T07a、T11a。
- 交付物：`ContentQueryViewModel`（headless 编排：文本→QueryContext→
  LLMProvider→ResultModel→JSONL）+ 重写的 `MainWindowView` +
  `AppComposition` 组合根 + `FailingLLMProvider` 降级 + 中英本地化键。
- 验收结果：编排层 headless 单测覆盖 成功+落盘 / 空输入 / provider
  AgentError 分类 / 非 AgentError→unknown / 落盘失败不阻断结果；UI 只按
  `AgentError.Category` 显示本地化文案，不拼 provider 私有错误；缺 key
  经 `FailingLLMProvider` 降级为可见失败态而非崩溃。
- 待办（非代码问题）：带真实 API key 的端到端手动验收待 James 提供 key；
  当前无 key 实跑停在 `error.invalid_input`（降级路径，已验证失败态 UI）。
- 落点：`UI/ContentQueryViewModel.swift`、`UI/MainWindowView.swift`、
  `App/AppComposition.swift`、`Resources/Localizable.xcstrings`、
  `PersonalAgentTests/TUI1QueryFlowTests.swift`。

### T04 全局快捷键与输入入口（P2，已完成）

- 目标：建立全局快捷键和输入路由。
- 状态：DONE（2026-05-16，`** TEST SUCCEEDED **`，T04 6 单测绿，
  回归全绿）。James 决策热键用 NSEvent 全局监听。
- 依赖：TC。
- 交付物：`InputEntry`（screenshot/selection/manualInput→`InputSourceKind`）；
  `AccessibilityAuthorizing` 协议（`AXIsProcessTrusted` + 桩）；
  `InputRouter`（纯逻辑，未授权入口返回 `AgentError(.permission)`）；
  `HotkeyMonitoring` 协议（`GlobalHotkeyMonitor` 用 NSEvent global+local，
  未授权 `start()` 抛 `.permission`，默认 ⌘⇧A）。
- 验收结果：三入口可区分；manualInput 不需授权恒通过，screenshot/
  selection 未授权返回 `.permission`；热键触发回调与授权失败抛错单测覆盖。
- 范围决策（AGENTS「不提前造系统」）：本任务只交付路由/授权/监听契约层。
  全局热键接入 App 生命周期 + 权限引导 UI **随 T05/T08 一并落地**——
  现接热键只能指向尚不存在的截屏/取词采集（死路径）；manualInput 查询
  路径已由 T-UI1 UI 可用。
- 诚实约束：NSEvent 全局监听非独占，无法检测与其它 App 的热键冲突
  （需 Carbon `RegisterEventHotKey`）；本任务只做授权失败提示，冲突
  检测推迟。
- 落点：`Core/Input/{InputEntry,AccessibilityAuthorizing,InputRouter,
  HotkeyMonitoring}.swift`、`PersonalAgentTests/T04InputRoutingTests.swift`。

### T05 截屏区域选择（P2，逻辑层完成）

- 目标：实现区域截图和图片元信息输出。
- 状态：DONE（逻辑/适配层，2026-05-16，`** TEST SUCCEEDED **`，
  T05 9 单测绿，回归全绿）。James 决策采集用 ScreenCaptureKit。
- 依赖：T04。
- 交付物：`CaptureRegion`（拖拽两点归一化 + 多屏裁剪 + 退化判空，纯
  几何）；`ScreenCaptureAuthorizing`（`CGPreflight/RequestScreenCaptureAccess`
  + 桩）；`ScreenCaptureCoordinator`（授权门/取消/失败编排，纯可测）；
  `SCScreenCapturer`（ScreenCaptureKit 薄适配，`SCScreenshotManager`
  macOS 14+，13.x 明确报"需 macOS 14"）；`ScreenshotResult`（PNG +
  TC `DisplayInfo`）。
- 验收结果：取消→`.cancelled`，未授权→`.permission`，采集失败分类；
  截图模块只产图不调 LLM/OCR；几何/编排单测覆盖。
- 范围决策（AGENTS「不提前造系统」+ 不零散造无法测 UI）：区域选择
  overlay 窗口（全屏拖拽框选）+ 热键→截屏→OCR 的 App 接线，与 T06
  一并作一次 **P2 整合**落地（届时截图有 OCR 消费者，可端到端可视化
  验收，同时接入 T04 `HotkeyMonitoring`/`InputRouter`）。
- 诚实约束：单帧截图依赖 macOS 14 `SCScreenshotManager`；13.x 单次
  截图需 `SCStream` 取帧，属后续硬化，当前明确报错不静默。
- 落点：`Features/Input/{ScreenCapture,ScreenCaptureAuthorizing,
  ScreenCaptureCoordinator,SCScreenCapturer}.swift`、
  `PersonalAgentTests/T05ScreenCaptureTests.swift`。

### T06 Vision OCR（P2，已完成）

- 目标：用 Apple Vision 实现本地 OCR。
- 状态：DONE（2026-05-16，`** TEST SUCCEEDED **`，T06 8 单测绿，
  回归全绿）。
- 依赖：T05。
- 交付物：`OCRRecognizing` 协议 + `OCRLine`；`OCRAssembler`（行→
  `OCRResult`，fullText 拼接 + 置信度均值，纯可测）；`OCRCoordinator`
  （取消/空结果/未知分类编排）；`VisionTextRecognizer`（VNRecognizeText
  薄适配，本地无网络无权限）。
- 验收结果：图片→结构化 `OCRResult`；空/纯空白→`.invalidInput`，
  低置信度仍成功（保留 `overallConfidence` 供调用方判断），取消→
  `.cancelled`，其它→`.unknown`；OCR 层不做翻译。
- 落点：`Features/Recognition/{OCRRecognizing,OCRAssembler,
  OCRCoordinator,VisionTextRecognizer}.swift`、
  `PersonalAgentTests/T06OCRTests.swift`。

### T08 划线/剪贴板取词（P2）

- 目标：实现选中文本或剪贴板输入链路。
- 状态：TODO。
- 依赖：T04。
- 交付物：文本提取入口、剪贴板保护、失败状态。
- 验收标准：取词失败不触发空查询；不永久破坏用户剪贴板。
- 备注：MVP 用剪贴板兜底；正式版再补 Accessibility/AppleScript/模拟复制。

### T-INT2 P2 整合与可视化验收（P2）

- 目标：把 T04/T05/T06/T08 的逻辑层接成可用功能，做一次真机可视化验收。
- 状态：TODO。
- 依赖：T04、T05、T06、T08。
- 交付物：区域选择 overlay 窗口（全屏拖拽框选，复用 `CaptureRegion`）；
  `HotkeyMonitoring`/`InputRouter` 接 App 生命周期；权限引导 UI（辅助
  功能/录屏未授权→引导系统设置，复用 `.permission` 文案）；
  截屏→`OCRCoordinator`→`ContentQueryViewModel` 端到端串联。
- 验收标准：真机走通 热键→框选→截屏→OCR→查询→落盘；取消/权限失败
  在 UI 可区分；文案本地化；逻辑层回归单测全绿。
- 备注：本任务是前述被刻意推迟的"零散造无法测 UI"的集中兑现点；
  GUI/系统授权需手动验收，James 在场或提供验收反馈。

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
