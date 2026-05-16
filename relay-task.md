# Relay Task

_updated: 2026-05-16 15:25_
_project: /Users/macmini/Documents/fanyibiji (PersonalAgent macOS App)_
_branch: main_

## 任务
参考 Easydict、干净重写个人用 macOS 助理 App MVP。2026-05-16 经 James
确认执行策略为 P0→P4（先定契约 → 最薄垂直闭环 → 再扩重路径 → 收敛
硬化）。**P0 + P1 + P2 全部逻辑层 + P3 的 T09 翻译 provider 已完成**
（单测全绿）。剩 T-INT2 P2 整合（GUI/授权，需真机验收）、T10 TTS
（BLOCKED 待 James 决策）、T07b/T12 硬化。

`relay-task.md` 是唯一交接文件；`handoff.md` 已废弃。

## 当前进度
- [x] P-1 文档与工程骨架（T00/T01/T02）。
- [x] 2026-05-16 总体规划重排为 P0–P4，写入 `project-board.md`。
- [x] P0 TC 核心契约层：6 契约源文件 + 10 单测，
  `xcodebuild build/test` 通过。测试 target 已配 TEST_HOST/BUNDLE_LOADER
  + 对 App target 的依赖。
- [x] P1 T03 本地配置与密钥边界：DONE。`ProviderConfig` +
  `SecretStore`(Keychain/内存桩) + `ConfigStore.resolve`，11 单测绿。
- [x] P1 T11a 最小 JSONL 持久化：DONE。`JSONLResultStore`，7 单测绿。
- [x] P1 T07a 最小 LLM Provider：DONE。`LLMHTTPClient` 协议 +
  `OpenAICompatibleLLMProvider`，12 单测绿。
- [x] P1 T-UI1 主窗口接入垂直闭环：DONE，5 单测绿。**P1 全部完成。**
- [x] P2 T04 全局快捷键与输入入口：DONE，6 单测绿。仅契约/逻辑层。
- [x] P2 T05 截屏区域选择：DONE（逻辑/适配层），9 单测绿。
- [x] P2 T06 Vision OCR：DONE，8 单测绿。
- [x] P2 T08 划线/剪贴板取词：DONE，5 单测绿。**P2 逻辑层全部完成。**
- [x] P3 T09 免费翻译 provider：DONE，11 单测绿（含隔离性）。
  `TranslateHTTPClient`/`FreeWebTranslateProvider`（逆向端点隔离）。

## 下一步（具体到能直接动手）
1. 按序读 `AGENTS.md` → `relay-task.md` → `project-board.md` → `prd-mvp.md`。
2. **T-INT2 P2 整合**（看板已登记，需真机可视化验收，建议 James 在场/
   给反馈）：区域选择 overlay 全屏框选（复用 `CaptureRegion`）+
   `HotkeyMonitoring`/`InputRouter` 接 App 生命周期 + 权限引导 UI +
   截屏→`SCScreenCapturer`→`OCRCoordinator`→`ContentQueryViewModel`
   端到端 + T08 取词入口 + T09 翻译动作。逻辑层已全就绪，本任务主要
   是接线与可视化/授权验收——刻意推迟的"无法 headless 测 GUI"兑现点。
3. 可 headless 的备选：T07b LLM 硬化（多模型/重试），T12 收敛硬化的
   纯逻辑部分。T10 TTS 仍 BLOCKED 待 James 决策（供应商/鉴权/格式/流式）。
4. 每个任务完成后验证：
   ```bash
   xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent
   xcodebuild test  -project PersonalAgent.xcodeproj -scheme PersonalAgent
   ```

## 关键文件 / 路径
- Agent 规则：`AGENTS.md`
- 项目看板（P0–P4 拆分/验收）：`project-board.md`
- MVP PRD：`prd-mvp.md`
- 契约层：`PersonalAgent/Core/Models/*.swift`、`Core/Services/ProviderAdapter.swift`
- 配置/密钥边界：`PersonalAgent/Core/Config/{ProviderConfig,SecretStore,ConfigStore}.swift`
- 持久化：`PersonalAgent/Core/Persistence/JSONLResultStore.swift`
- LLM provider：`Core/Services/LLMHTTPClient.swift`、
  `Features/Providers/OpenAICompatibleLLMProvider.swift`
- 翻译 provider：`Core/Services/TranslateHTTPClient.swift`、
  `Features/Providers/FreeWebTranslateProvider.swift`
- 垂直闭环 UI：`UI/ContentQueryViewModel.swift`、`UI/MainWindowView.swift`、
  `App/AppComposition.swift`、`Resources/Localizable.xcstrings`
- 输入路由层：`PersonalAgent/Core/Input/{InputEntry,
  AccessibilityAuthorizing,InputRouter,HotkeyMonitoring,
  PasteboardReading,ClipboardTextGrabber}.swift`
- 截屏层：`PersonalAgent/Features/Input/{ScreenCapture,
  ScreenCaptureAuthorizing,ScreenCaptureCoordinator,SCScreenCapturer}.swift`
- OCR 层：`PersonalAgent/Features/Recognition/{OCRRecognizing,
  OCRAssembler,OCRCoordinator,VisionTextRecognizer}.swift`
- 单测：`PersonalAgentTests/{TCContractsTests,T03ConfigTests,
  T11aJSONLStoreTests,T07aLLMProviderTests,TUI1QueryFlowTests,
  T04InputRoutingTests,T05ScreenCaptureTests,T06OCRTests,
  T08ClipboardGrabTests,T09TranslateProviderTests}.swift`
- 本轮存档（详细背景）：`/Users/macmini/baidu/Archives/2026-05-16-personalagent-replan-tc-contracts.md`
- 相关 auto memory：`project_personalagent.md`、`user_james.md`

## 阻塞 / 风险 / 待用户决策
- **T-UI1 端到端手验待 key**：垂直闭环架构由 headless 单测证明；带真实
  API key 的剪贴板→LLM→JSONL 手动验收需 James 把 key 写入 Keychain
  （account=`llm.apiKey`, service=`com.james.personalagent`）。无 key 时
  UI 走降级失败态 `error.invalid_input`（已验证）。
- T10 TTS BLOCKED：供应商、鉴权、音频格式、是否流式待 James 决策；不阻塞 P1/P2。
- 免费翻译 provider 未锁定；逆向 Web API 须隔离在可替换层。
- 未来如对外分发，需重新确认 GPL/签名/公证策略。

## 上下文要点（接手前必读）
- pbxproj 是显式引用工程：新增 .swift 必须手动补
  PBXBuildFile/FileReference/Group/Sources 四处，改后 `plutil -lint` 再 build。
- 持久化编码契约（T11a 沿用）：snake_case + `.iso8601`，时间精度到秒
  （不含亚秒），历史去重/比对按秒。Codable 属性名避开缩略词大写：
  `.convertFromSnakeCase` 把 `base_url` 解回 `baseUrl`，用 `baseURL` 会
  解码失败——统一用 `baseUrl` 式命名。
- API key 边界：provider 一律消费 `ConfigStore.resolve` 产出的
  `ResolvedProviderConfig`，不自己读 Keychain；该类型故意不 Codable。
- 错误统一 `throws AgentError`；UI 只按 `AgentError.category` 分支，
  不拼接 provider 私有错误。
- 复杂任务 Admin → Worker → Overseer；Admin 输出路径后必须等 James 确认。
- 默认干净重写，不复制 Easydict 源码/资源/提示词/逆向实现。
