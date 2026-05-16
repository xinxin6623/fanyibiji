# Relay Task

_updated: 2026-05-16 (T12 收敛硬化 A/B/C/D 全完成)_
_project: /Users/macmini/Documents/fanyibiji (PersonalAgent macOS App)_
_branch: main_

## 任务
参考 Easydict、干净重写个人用 macOS 助理 App MVP。2026-05-16 经 James
确认执行策略为 P0→P4（先定契约 → 最薄垂直闭环 → 再扩重路径 → 收敛
硬化）。**P0 + P1 + P2（含 T-INT2 整合代码层）+ P3 的 T09/T07b
已完成**（单测全绿）。剩 T-INT2 真机 GUI/授权验收（待 James 在场）、
T10 TTS（BLOCKED 待 James 决策）、T12 收敛硬化。

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
- [x] P3 T07b LLM Provider 硬化：DONE，5 单测绿。
  `RetryingLLMProvider` 装饰器只对可重试 `AgentError` 重试，取消不重试；
  多模型由 `ResolvedProviderConfig.model` 承载，流式推迟到确有需求。
- [x] P2 T-INT2 整合：**真机验收通过**（2026-05-16，James 在场）。
  代码层 8 单测绿、全量回归绿、无告警；真机逐条通过：截屏→框选→OCR
  →LLM 翻译→落盘（中英文均可），热键 ⌘⇧D 从任意 App 触发不抢窗口，
  ESC 取消不打扰，权限引导。提交 e9c8474/a923c4c/7ac00d8/de05763/
  f2df335。详见看板 T-INT2「真机验收结果」。
  关键修复：中文 OCR 默认语言、截屏坐标系 Y 翻转、辅助功能主动
  prompt+自愈、后台截屏不抢焦点、本地自签证书稳定签名。
- [x] T08/T09 取词 UI 动作分发：**真机验收通过**（2026-05-16，
  commit 305c188）。「取词问 AI」剪贴板→LLM；「取词翻译」剪贴板→
  T09（主翻译通道，免 key）。+7 单测，全量回归绿无告警。截屏
  `.translate` 走 LLM+prompt、取词 `.translate` 走 T09 provider——
  两条有意不同，各经 James 确认。详见看板 T09「UI 接入」。
- [x] **T12 收敛硬化 全完成**（2026-05-16，commit
  ba4c5fa/c4f23f8/4f7182c/98a951a）：A 截屏空图/坐标防御（纯函数
  +11 单测）、B 失败落盘+重试（§8-4，+8）、C 统一取消+超时恢复
  （§8-8，+4）、D 历史读取+本地化完整性（+4，25 键齐全）。逻辑层
  全单测覆盖，真机点验按 James"继续"跳过。TTS 失败路径随 T10。
  详见看板 T12 拆分。

## 下一步（具体到能直接动手）
1. 按序读 `AGENTS.md` → `relay-task.md` → `project-board.md` → `prd-mvp.md`。
2. **P0–P4 主体全部完成**（P2 整合 + T08/T09 UI + T12 收敛硬化
   A/B/C/D 均已落地，逻辑层单测全绿）。**唯一剩余：T10 TTS**。
   2026-05-16 James 表示去准备 TTS key（决策进行中）。
   接手 T10 时需先向 James 确认/收集：供应商、鉴权方式、音频格式、
   是否流式；key 走 Keychain（仿 LLM：account 自定，
   service=`com.james.personalagent`，写入用 `-A` 宽松 ACL 避免重签
   反复弹框）。实现沿 `TTSProvider` 协议（`Core/Services/ProviderAdapter
   .swift` 已定义 `synthesize(_:)->AudioResult`），仿 T07a/T09 结构：
   `TTSHTTPClient` 协议+URLSession 生产+桩、provider 错误统一
   `AgentError`、`validate()` 零网络、播放层（AVFoundation）。完成后
   把 §8-6 TTS 失败路径补进 T12 容灾矩阵（看板 T12 已注）。
   除 T10 外无 TODO；后续多为打磨/分发（非 MVP，PRD §9 Defer）。
3. 每个任务完成后验证（**本机用稳定签名构建参数**）：
   ```bash
   xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent \
     -destination 'platform=macOS' CODE_SIGN_STYLE=Manual \
     CODE_SIGN_IDENTITY="PersonalAgent Local Dev" DEVELOPMENT_TEAM=""
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
  `Features/Providers/OpenAICompatibleLLMProvider.swift`、
  `Features/Providers/RetryingLLMProvider.swift`
- 翻译 provider：`Core/Services/TranslateHTTPClient.swift`、
  `Features/Providers/FreeWebTranslateProvider.swift`
- 垂直闭环 UI：`UI/ContentQueryViewModel.swift`、`UI/MainWindowView.swift`、
  `App/AppComposition.swift`、`Resources/Localizable.xcstrings`
- P2 整合（T-INT2）：`Features/Integration/P2IntegrationCoordinator.swift`、
  `UI/RegionSelectionController.swift`、`App/AppController.swift`、
  `App/PersonalAgentApp.swift`、`PersonalAgentTests/TINT2IntegrationTests.swift`
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
  T08ClipboardGrabTests,T09TranslateProviderTests,T07bRetryTests}.swift`
- 本轮存档（详细背景）：`/Users/macmini/baidu/Archives/2026-05-16-personalagent-replan-tc-contracts.md`
- 相关 auto memory：`project_personalagent.md`、`user_james.md`

## 阻塞 / 风险 / 待用户决策
- **T-UI1 端到端手验待 key**：垂直闭环架构由 headless 单测证明；带真实
  API key 的剪贴板→LLM→JSONL 手动验收需 James 把 key 写入 Keychain
  （account=`llm.apiKey`, service=`com.james.personalagent`）。无 key 时
  UI 走降级失败态 `error.invalid_input`（已验证）。
- T10 TTS BLOCKED：供应商、鉴权、音频格式、是否流式待 James 决策；不阻塞 P1/P2。
- T09 免费翻译 provider 当前使用隔离的逆向公开端点；后续可整体替换 provider。
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
- **本机签名**：`pbxproj` 保持 ad-hoc/Automatic（不污染仓库），开发
  构建靠参数 `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="PersonalAgent
  Local Dev" DEVELOPMENT_TEAM=""` 用本地自签证书（TCC 授权按签名身份
  记，ad-hoc 每次重建变会失效）。证书已在 login keychain + 系统信任根。
- **TCC 重置铁律**：绝不用全局 `tccutil reset <svc>`（会连累 Easydict
  等），必须带 bundle id：`tccutil reset <svc> com.james.personalagent`。
- LLM key 在 Keychain（account=`llm.apiKey`,
  service=`com.james.personalagent`），用 `-A` 宽松 ACL 避免重签反复
  弹框（仅本机开发）。OpenRouter key 调试期多次泄露，**需作废重建**。
- 截屏坐标 AppKit↔CG 必须 Y 翻转（见 `SCScreenCapturer`）；防御机制
  待 T12。Vision OCR 默认语言须含中文（见 `VisionTextRecognizer`）。
