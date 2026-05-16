# Relay Task

_updated: 2026-05-16 (收尾：P0–P4 主体完成，仅余 T10 TTS)_
_project: /Users/macmini/Documents/fanyibiji (PersonalAgent macOS App)_
_branch: main_

## 任务
参考 Easydict、干净重写个人用 macOS 助理 App MVP。执行策略 P0→P4
（先定契约 → 最薄垂直闭环 → 再扩重路径 → 收敛硬化）。
**P0–P4 主体全部完成并真机验收，唯一剩余 T10 TTS（BLOCKED）。**
`relay-task.md` 是唯一交接文件；`handoff.md` 已废弃。

## 当前进度
- [x] P-1 骨架 / P0 契约层 / P1 垂直闭环（T03/T07a/T11a/T-UI1）。
- [x] P2 逻辑层（T04/T05/T06/T08）+ P3（T09/T07b）。
- [x] **T-INT2 P2 整合**：真机验收通过（James 在场）。截屏→框选→OCR
  →LLM 翻译→落盘（中英文），⌘⇧D 任意 App 触发不抢窗口，ESC 取消
  不打扰，权限引导。
- [x] **OCR→翻译改造**：截屏文本默认翻译（对齐 Easydict），默认 LLM
  = OpenRouter `baidu/qianfan-ocr-fast`。
- [x] **T08/T09 取词 UI 分发**：真机验收通过。「取词问 AI」→LLM；
  「取词翻译」→T09（主翻译通道，免 key）。截屏 .translate 走
  LLM+prompt、取词 .translate 走 T09——两条有意不同，各经 James 确认。
- [x] **T12 收敛硬化 A/B/C/D 全完成**（commit
  ba4c5fa/c4f23f8/4f7182c/98a951a）：A 截屏空图/坐标防御（纯函数
  +11 单测）、B 失败落盘+重试 §8-4（+8）、C 统一取消+超时恢复 §8-8
  （+4）、D 历史读取+本地化完整性（+4，25 键齐全）。逻辑层全单测
  覆盖，真机点验按 James"继续"跳过。
- 全量回归绿、无告警；仓库干净；本轮提交 e9c8474 → 4438a7c。

## 下一步（具体到能直接动手）
1. 按序读 `AGENTS.md` → `relay-task.md` → `project-board.md` → `prd-mvp.md`。
2. **唯一剩余 = T10 TTS**（BLOCKED）。2026-05-16 James 去准备 TTS key。
   接手时先向 James 确认/收集四个决策点：**供应商、鉴权方式、音频
   格式、是否流式**。然后：
   - key 写 Keychain（仿 LLM：account 自定，
     service=`com.james.personalagent`，用 `-A` 宽松 ACL 避免重签
     反复弹框）。
   - 沿 `TTSProvider` 协议（`Core/Services/ProviderAdapter.swift` 已定
     `synthesize(_:)->AudioResult`），仿 T07a/T09 结构：`TTSHTTPClient`
     协议 + URLSession 生产 + 桩；错误统一 `AgentError`；`validate()`
     零网络；播放层用 AVFoundation。
   - 完成后把 §8-6 TTS 失败路径补进 T12 容灾矩阵（看板 T12 已注）。
3. 除 T10 外无 TODO；后续多为打磨/分发（非 MVP，PRD §9 Defer）。
4. 验证（**本机必带稳定签名构建参数**）：
   ```bash
   xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent \
     -destination 'platform=macOS' CODE_SIGN_STYLE=Manual \
     CODE_SIGN_IDENTITY="PersonalAgent Local Dev" DEVELOPMENT_TEAM=""
   xcodebuild test  -project PersonalAgent.xcodeproj -scheme PersonalAgent \
     -destination 'platform=macOS' CODE_SIGN_STYLE=Manual \
     CODE_SIGN_IDENTITY="PersonalAgent Local Dev" DEVELOPMENT_TEAM=""
   ```

## 关键文件 / 路径
- 规则/看板/PRD：`AGENTS.md`、`project-board.md`、`prd-mvp.md`
- 契约层：`PersonalAgent/Core/Models/*.swift`、`Core/Services/ProviderAdapter.swift`
- 配置/密钥：`Core/Config/{ProviderConfig,SecretStore,ConfigStore}.swift`
- 持久化：`Core/Persistence/JSONLResultStore.swift`
- providers：`Features/Providers/{OpenAICompatibleLLMProvider,
  RetryingLLMProvider,FreeWebTranslateProvider}.swift`、
  `Core/Services/{LLMHTTPClient,TranslateHTTPClient}.swift`
- UI/编排：`UI/{ContentQueryViewModel,MainWindowView,
  RegionSelectionController}.swift`、`App/{AppComposition,AppController,
  PersonalAgentApp}.swift`、`Resources/Localizable.xcstrings`
- P2 整合：`Features/Integration/P2IntegrationCoordinator.swift`
- 截屏/OCR：`Features/Input/{ScreenCapture,ScreenCaptureAuthorizing,
  ScreenCaptureCoordinator,SCScreenCapturer,ScreenGeometry}.swift`、
  `Features/Recognition/{OCRRecognizing,OCRAssembler,OCRCoordinator,
  VisionTextRecognizer,BlankImageDetector}.swift`
- 输入路由：`Core/Input/{InputEntry,AccessibilityAuthorizing,
  InputRouter,HotkeyMonitoring,PasteboardReading,ClipboardTextGrabber}.swift`
- 单测：`PersonalAgentTests/*.swift`（18 文件，含 TINT2/TClipboard
  Dispatch/T12{ScreenDefense,FailurePersistRetry,CancelTimeout,History}）
- 本轮存档（详细背景去这里翻）：
  `/Users/qoragufimo390gmail.com/baidu/Archives/2026-05-16-personalagent-p2-t12-impl.md`
- 相关 auto memory：`project_2026-05-16_*.md`、`feedback_2026-05-16_*.md`

## 阻塞 / 风险 / 待用户决策
- **T10 TTS BLOCKED**：供应商/鉴权/音频格式/是否流式待 James 决策；
  James 已去准备 key。
- **OpenRouter key 泄露**：`sk-or-v1-35ff...` 调试期多次明文进对话
  历史，**James 需去 openrouter.ai/keys 作废重建**（多次提醒未确认）。
- T09 用隔离的逆向公开端点；后续可整体替换 provider。
- 本地自签证书非正式签名；对外分发需正式 Developer ID + 公证 + 重新
  确认 GPL 策略。

## 上下文要点（接手前必读）
- **本机签名**：pbxproj 保持 ad-hoc/Automatic（不污染仓库），构建靠
  参数 `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="PersonalAgent
  Local Dev" DEVELOPMENT_TEAM=""`（TCC 授权按签名身份记，ad-hoc 每次
  重建变会失效）。证书已在 login keychain + 系统信任根。
- **TCC 重置铁律**：绝不用全局 `tccutil reset <svc>`（连累 Easydict
  等 James 日常工具）；必须带 bundle id `... com.james.personalagent`。
- **Keychain key**：写 key 用 `-A` 宽松 ACL 避免重签反复弹框（仅本机
  开发）。LLM key account=`llm.apiKey`，service=`com.james.personalagent`。
- pbxproj 显式引用：新增 .swift 必补 BuildFile/FileReference/Group/
  Sources 四处，改后 `plutil -lint` 再 build。
- 编码契约（T11a）：snake_case + `.iso8601` 秒精度；Codable 属性名避
  缩略词大写（用 `baseUrl` 非 `baseURL`）。
- provider 一律消费 `ConfigStore.resolve` 的 `ResolvedProviderConfig`
  （故意不 Codable），不自读 Keychain。错误统一 `throws AgentError`，
  UI 只按 `.category` 分支不拼 provider 私有错误。
- 截屏坐标 AppKit↔CG 必 Y 翻转（已抽 `ScreenGeometry` 纯函数+空图
  检测 `BlankImageDetector`，T12-A 已闭环）。Vision OCR 默认语言须含
  中文（`VisionTextRecognizer` 已默认 zh-Hans/zh-Hant/en-US）。
- 复杂任务 Admin→Worker→Overseer；输出路径后等 James 确认。默认干净
  重写，不复制 Easydict 源码/资源/提示词/逆向实现。
