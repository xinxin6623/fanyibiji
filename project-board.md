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
| P2 | 截屏/OCR 重路径 | 快捷键、截屏、OCR、取词入口 | DONE（真机验收通过）|
| P3 | 次要 Provider | 免费翻译、指定 TTS | 翻译 DONE；TTS(T10) DONE |
| P4 | 收敛与硬化 | 容灾矩阵、本地化、历史读取 | DONE（T12 A/B/C/D，TTS 路径已随 T10 收口）|

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
| T08 | P2 | 划线/剪贴板取词 | DONE（UI 已接，真机验收通过）| T04 | 选中文本或剪贴板输入链路 |
| T-INT2 | P2 | P2 整合与可视化验收 | DONE（真机验收通过）| T04,T05,T06,T08 | overlay+热键+截屏→OCR→翻译 App 接线 |
| T09 | P3 | 免费翻译 Provider | DONE（UI 已接为主翻译通道，真机验收通过）| T03、TC | 一个稳定翻译 provider |
| T10 | P3 | 指定 TTS Provider | DONE（讯飞双引擎，30 单测绿，已合并推送，2026-05-17 真机验收两引擎通过） | T03、TC | 普通+超拟人可切换 provider、播放链路、设置持久化 |
| T07b | P3 | LLM Provider 硬化 | DONE | T07a | 多模型配置已由 T03/T07a 承载；新增重试装饰器；流式推迟 |
| T12 | P4 | 收敛与硬化 | DONE（A/B/C/D 四项；TTS §8-6 已随 T10 收口）| P1–P3 | 容灾矩阵、本地化完整性、历史读取接口 |

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

### T08 划线/剪贴板取词（P2，已完成）

- 目标：实现选中文本或剪贴板输入链路。
- 状态：DONE（2026-05-16，`** TEST SUCCEEDED **`，T08 5 单测绿，
  回归全绿）。
- 依赖：T04。
- 交付物：`PasteboardReading` 协议 + `SystemPasteboard`（NSPasteboard
  只读）；`ClipboardTextGrabber`（空/纯空白→`.invalidInput`，纯可测）。
- 验收结果：取词失败返回 `.invalidInput` 不触发空查询；MVP 只读剪贴板
  兜底、不模拟 ⌘C、不写回 → 天然不破坏用户剪贴板。
- 落点：`Core/Input/{PasteboardReading,ClipboardTextGrabber}.swift`、
  `PersonalAgentTests/T08ClipboardGrabTests.swift`。
- 备注：Accessibility/AppleScript/模拟复制（含剪贴板快照恢复）属正式版，
  按 AGENTS「不提前造系统」推迟；接入 UI 在 T-INT2。

### T-INT2 P2 整合与可视化验收（P2，代码完成，待真机验收）

- 目标：把 T04/T05/T06/T08 的逻辑层接成可用功能，做一次真机可视化验收。
- 状态：DONE（代码层，2026-05-16，`** TEST SUCCEEDED **`，T-INT2 7 单测
  绿，全量回归全绿，无编译告警）。**真机 GUI/系统授权手动验收待 James**。
- 依赖：T04、T05、T06、T08。
- 交付物：
  - `P2IntegrationCoordinator`（headless 编排：路由授权门→区域选择→截屏
    →OCR→产出查询文本；复用 T04/T05/T06 协调器，错误分类原样透传，
    7 单测覆盖 happy/未授权短路/取消/空 OCR/采集失败透传/VM 注入）。
  - `RegionSelectionController` + 私有 `RegionSelectionView`（多屏全屏
    borderless overlay，拖拽框选，ESC/右键/空拖拽→`.cancelled`，复用
    `CaptureRegion.fromDrag` 不重写几何；局部→全局屏幕坐标换算）。
  - `AppController`（P2 组合根 + 生命周期：装配真实
    `SCScreenCapturer`/`VisionTextRecognizer`；`onAppear` 接
    `GlobalHotkeyMonitor`（⌘⇧A），未授权不崩溃记 `.permission`；
    串行触发，进行中忽略二次触发避免叠 overlay；`openPrivacySettings`
    落到隐私与安全性根面板——deep link 不稳定故用诚实可达兜底）。
  - `ContentQueryViewModel` 扩展：`runQuery(with:sourceKind:)` 接外部
    OCR 文本并保留真实 `sourceKind`；`reportCaptureFailure` 把采集链
    失败透传 UI（取消回 idle 不报错，其余显示分类文案）。
  - `MainWindowView` 重构：共享 VM + 截屏取词按钮（⌘⇧A）+ 权限引导
    横幅（`.permission` 时显示"打开系统设置"）；新增 `capture.run`/
    `capture.hint`/`permission.open_settings`/`permission.guide` 中英键。
  - `PersonalAgentApp` 持有 `AppController`、注入共享 VM、`start()`。
- 验收标准（代码层已满足）：编排链 headless 单测全绿；取消/权限/空
  OCR 分类可区分；文案本地化；逻辑层回归全绿；`xcodebuild build/test`
  通过无告警。
- **真机验收结果（2026-05-16，James 在场逐条通过）**：
  - 手动查询、截屏→框选→OCR→LLM 翻译→落盘端到端通（英文 conf 1.0）。
  - 中文 OCR：初验漏识，修 `VisionTextRecognizer` 默认
    `zh-Hans/zh-Hant/en-US`（Vision 默认仅英文）后通过。
  - 截屏坐标：初验截到空白图（OCR 报无文字）。根因
    `SCScreenCapturer` 把 AppKit overlay 坐标（原点左下、Y 上）直接
    喂 `SCStreamConfiguration.sourceRect`（CG 坐标、原点左上、Y 下），
    修 Y 翻转 `cgY=display.height-y-h` 后通过。**防御机制（空图检测+
    坐标纯函数单测）James 确认记 T12，见下方 T12 条目。**
  - 全局热键：⌘⇧A 与 James 常用 App 冲突 → 默认改 ⌘⇧D。
    `AXIsProcessTrusted()` 对自签开发构建持续 false → 加
    `promptIfNeeded()`（`AXIsProcessTrustedWithOptions` 主动弹窗登记
    二进制）+ `didBecomeActiveNotification` 自愈重试（授权后切回即生效，
    不重启）。
  - 后台截屏交互：原实现热键触发会把主窗口抢到前台；改为框选阶段不
    `NSApp.activate`（`OverlayPanel` `.nonactivatingPanel`+`canBecomeKey`
    收 ESC 不抢焦点），仅成功/非取消失败时才激活主窗口。
  - 环境踩坑（已记 feedback 记忆）：`tccutil reset ScreenCapture`
    无 bundle id 连累 Easydict；此后只用带 bundle id 的精准 reset。
    Keychain ACL 随重签反复弹框 → 用 `-A` 宽松 ACL（仅本机开发）。
    ad-hoc 签名每次变 TCC 认不出 → 本地自签证书
    `PersonalAgent Local Dev`（**不入仓库**，构建参数
    `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=... DEVELOPMENT_TEAM=""`）。
- 落点：`Features/Integration/P2IntegrationCoordinator.swift`、
  `UI/RegionSelectionController.swift`、`App/AppController.swift`、
  `App/PersonalAgentApp.swift`、`Core/Input/{AccessibilityAuthorizing,
  HotkeyMonitoring}.swift`、`Features/Input/SCScreenCapturer.swift`、
  `Features/Recognition/VisionTextRecognizer.swift`、
  `UI/{ContentQueryViewModel,MainWindowView}.swift`、
  `Resources/Localizable.xcstrings`、
  `PersonalAgentTests/TINT2IntegrationTests.swift`。
- 诚实约束：NSEvent 全局热键非独占，无冲突检测（沿用 T04 决策，
  ⌘⇧D 仍可能与其它 App 撞，彻底解决需 Carbon RegisterEventHotKey）；
  单帧截图依赖 macOS 14 `SCScreenshotManager`（沿用 T05 约束）；
  系统设置面板用根 deep link 而非脆弱子面板深链；本地自签证书
  非正式签名，分发需正式 Developer ID + 公证。

### T09 免费翻译 Provider（P3，已完成）

- 目标：接入一个免费翻译 provider。
- 状态：DONE（2026-05-16，`** TEST SUCCEEDED **`，T09 11 单测绿，
  回归全绿）。
- 依赖：T03、TC。
- 交付物：`TranslateHTTPClient` 协议（独立于 `LLMHTTPClient`，生产
  URLSession + 桩）；`FreeWebTranslateProvider: TranslateProvider`
  （逆向公开端点，非官方响应解析集中在 `parse` 一处便于整体替换）。
- 验收结果：基本翻译成功（解析嵌套数组、目标语言取 languageHints
  兜底 default）；空输入→`.invalidInput`，HTTP/网络/超时/取消/响应畸形
  分类映射；隔离性单测证明翻译失败不影响 LLM 主路径（无共享状态、
  各自 HTTPClient）。
- 落点：`Core/Services/TranslateHTTPClient.swift`、
  `Features/Providers/FreeWebTranslateProvider.swift`、
  `PersonalAgentTests/T09TranslateProviderTests.swift`。
- 备注（AGENTS 边界）：逆向 Web API 隔离在可替换 provider 层，未成为
  核心依赖。
- **UI 接入（2026-05-16，commit 305c188，真机验收通过）**：经 James
  确认 T09 作**主翻译通道**。`ContentQueryViewModel` 新增
  `TranslateProvider`+`ClipboardTextGrabber` 依赖与
  `queryFromClipboard`/`translateFromClipboard`/`runTranslate`；
  `MainWindowView` 加「取词问 AI」（剪贴板→LLM `.query`）「取词翻译」
  （剪贴板→T09，免 key）两按钮 + `clipboard.query`/`clipboard.translate`
  中英键；`AppComposition` 装配 `FreeWebTranslateProvider`+
  `SystemPasteboard`。取词翻译经 `languageHints=["zh"]` 传目标语言给
  T09 的 `tl` 参数。落盘 `ResultModel.provider` 区分 LLM/翻译通道可
  溯源。**与截屏路径区分**：截屏 `.translate` 仍走 LLM+翻译 prompt
  （OpenRouter），取词 `.translate` 走 T09 provider——两条有意不同，
  按 James 各自确认。新增 7 单测（`TClipboardDispatchTests`），既有
  VM 构造点迁移到共享 `makeTestViewModel`。空/纯空白剪贴板→
  `.invalidInput` 不触发空 provider 调用。

### T10 指定 TTS Provider（P3，DONE）

- 目标：接入指定 TTS API 并完成播放链路。
- 状态：**DONE + 真机验收通过**（2026-05-16 开发，`T10TTSTests` 30
  单测绿、全量回归绿、无告警；已合并推送 origin/main；2026-05-17
  James 真机实测**普通与超拟人两引擎均出声通过**，三件套 key 已
  写入）。**双引擎**：普通 v2/tts + 超拟人 super-tts，UI 下拉切换，
  共用同一套三件套密钥（鉴权完全相同），默认超拟人·聪小璇。
- 依赖：T03、TC。
- James 决策（解阻塞）：供应商=科大讯飞（两套接口：普通在线
  `wss://tts-api.xfyun.cn/v2/tts`；超拟人
  `wss://cbm01.cn-huabei-1.xf-yun.com/v1/private/mcd9m97e6`）；鉴权=
  HMAC-SHA256（host+date+request-line → base64 authorization，两接口
  相同）；音频格式=lame(MP3)，AVAudioPlayer 直接解码；非流式「攒整
  段」；超拟人额外支持口语化程度（高/中/低，UI 下拉）。引擎/发音人
  /口语化均持久化随设置。
- 交付物：
  - `Core/Config/TTSConfig.swift`：`TTSConfig`(Codable) /
    `ResolvedTTSConfig`(不 Codable) / `TTSConfigStore.resolve`。
  - `Core/Services/TTSWebSocketClient.swift`：协议 + URLSession
    WebSocket 生产实现 + `TTSFrameCollector`(纯) + `XunfeiTTSAuth`
    (纯，注入 date 可复现签名)。
  - `Features/Providers/XunfeiTTSProvider.swift` + `FailingTTSProvider`
    降级（缺 key/非法配置 UI 可见不崩）。
  - `UI/TTSPlaybackViewModel.swift`（AVAudioPlayer，progress/seek，
    注入 provider 工厂）+ `UI/TTSPanelView.swift`（发音人下拉 +
    语速/音量/音调三滑块），挂 MainWindowView 底部。
  - `Core/Persistence/TTSSettingsStore.swift`：发音人/语速/音量/音调
    改动 debounce 落盘 `tts-config.json`，下次开 App 恢复；损坏/缺失
    /越界回默认（不阻断功能）。
- 密钥位：三个独立 Keychain 项，service=`com.james.personalagent`，
  account=`tts.appId`/`tts.apiKey`/`tts.apiSecret`，`-A` 宽松 ACL；
  James 自行写入（敏感信息不由 AI 代填）。
- 验收标准达成：按配置请求音频并播放；鉴权/网络/超时/服务方拒绝/
  文本过长/取消错误经 `AgentError` 统一可区分（讯飞码进
  `providerErrorCode` 仅诊断）；签名/帧拼接/错误码/配置/失败映射/
  设置持久化/ViewModel 重建均零网络单测覆盖。

### T07b LLM Provider 硬化（P3）

- 目标：在最小 LLM provider 基础上补多模型适配、重试与流式（如需）。
- 状态：DONE（2026-05-16，`T07bRetryTests` 5 单测绿）。
- 依赖：T07a。
- 交付物：`RetryingLLMProvider` 装饰器，可包裹任意 `LLMProvider`，
  只对 `AgentError.isRetriable` 重试，`.cancelled` 立即停止，耗尽次数
  抛最后一次错误。多模型能力继续由 `ResolvedProviderConfig.model`
  承载；流式按"确有需求再做"推迟。
- 验收标准：新增能力不破坏 P1 已验证的最小闭环回归；新增重试成功、
  耗尽、不可重试、取消不重试、id/validate 透传测试。

### T12 收敛与硬化（P4）

- 目标：补齐容灾矩阵与交付质量。
- 状态：**DONE**（2026-05-16，A/B/C/D 四项，James 确认范围，逐项
  单测全绿、全量回归绿、无告警）。**§8-6 TTS 失败路径已随 T10
  收口**：讯飞错误经 `XunfeiTTSProvider`/`TTSFrameCollector` 统一映射
  `AgentError`（流控 11201/11202/10200 标 `isRetriable`，鉴权/授权类
  不可重试），缺 key/非法配置 `FailingTTSProvider` 降级，UI 只按
  category 显本地化文案。
- 依赖：P1–P3。
- 拆分与落地：
  - **T12-A 截屏空图/坐标防御**（commit ba4c5fa）：`ScreenGeometry`
    （AppKit↔CG 坐标翻转 + 像素尺寸，纯函数）+ `BlankImageDetector`
    （近纯色采样，纯函数）；`SCScreenCapturer` 截到近纯色即抛
    `.invalidInput`「likely coord/capture error」，根因不再被 OCR
    "无文字"掩盖。11 单测（多屏/高分/边界/对比/短缓冲）。
  - **T12-B 失败落盘+重试**（§8-4，commit c4f23f8）：LLM/翻译失败
    也写带 `error` 的 `ResultModel`（tags=["failed"]），满足 §10
    "每次查询≥1 记录"；取消非失败不落盘。`lastAttempt`+`retryLast()`
    复用同输入同通道，`canRetry` 控 UI 重试按钮。8 单测。
  - **T12-C 统一取消+超时恢复**（§8-8，commit 4f7182c）：ViewModel
    经 `dispatch` 持有 `runningTask`，`cancelCurrent()` 取消并归位
    idle（传导到 provider）；run 方法对 `.cancelled`/`Task.isCancelled`
    早退不回写状态、不与取消打架；超时统一 `.timeout` 透传并落失败。
    UI loading 态显「取消」按钮。4 新单测 + 修正 T12-B 取消语义测试。
  - **T12-D 历史读取+本地化完整性**（commit 98a951a）：
    `loadHistory(limit:)` 读 JSONL（最近在前、缺失→空无错、损坏行
    →`.persistence` 不崩）；MainWindowView「历史」面板（provider/
    时间/内容/失败标记）。全 25 本地化键 en+zh-Hans 齐全、无硬编码
    UI 字面量。4 单测。
- 验收标准达成：§8 失败路径（含 §8-6 TTS，已随 T10 收口）全覆盖且有失败注入
  单测；§10 逐条满足（取消/超时可恢复、失败可区分不空查询、key 不
  入仓库/日志、每次查询≥1 记录、Apple Silicon 可构建运行、无 Easydict
  源码复制）。
- 落点：`Features/Input/ScreenGeometry.swift`、
  `Features/Recognition/BlankImageDetector.swift`、
  `Features/Input/SCScreenCapturer.swift`、
  `UI/{ContentQueryViewModel,MainWindowView}.swift`、
  `Resources/Localizable.xcstrings`、
  `PersonalAgentTests/{T12ScreenDefenseTests,T12FailurePersistRetryTests,
  T12CancelTimeoutTests,T12HistoryTests}.swift`。
- 诚实约束：取消依赖 provider 内 `Task.checkCancellation()`/
  `URLError.cancelled`（已具备）；空图检测是采样近纯色启发式，极端
  纯色正常截图理论上可能误报（阈值 tolerance=8 已留余量，可调）；
  TTS（§8-6）已随 T10（双引擎）收口，错误经 `AgentError` 统一映射。

## 看板维护规则

- 每次任务完成后更新状态、备注和下一推荐任务。
- 新任务必须有 ID、阶段、目标、状态、依赖、交付物和验收标准。
- 不在看板记录长过程日志；只记录能影响后续执行的事实。
- 遇到阻塞标记 `BLOCKED`，并写清缺的决策或依赖。
- 阶段内任务必须对 TC 契约层编程，禁止跨层私有耦合。
