# Relay Task

_updated: 2026-05-17 (MVP 全闭环：开发完成 + 真机验收通过 + 已合并推送)_
_project: /Users/qoragufimo390gmail.com/Documents/New project 3 (PersonalAgent macOS App)_
_branch: main（t10-tts-impl 已 --no-ff 合入并删除，已 push origin）_
_HEAD: 153e47e（Merge t10-tts-impl）+ 后续 doc 同步 commit，origin 同步_

## 任务
参考 Easydict、干净重写个人用 macOS 助理 App MVP。执行策略 P0→P4
（先定契约 → 最薄垂直闭环 → 再扩重路径 → 收敛硬化）。
**P0–P4 + T10 TTS 全部完成，MVP 无剩余 TODO**（其余属 PRD §9 Defer）。
`relay-task.md` 是唯一交接文件；`handoff.md` 已废弃。
注：项目已迁到 `New project 3`，旧 relay 写的 `/Users/macmini/...` 作废。

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
- [x] **T10 讯飞 TTS 全完成并已合并推送**：**双引擎**（普通 v2/tts +
  超拟人 super-tts，UI 下拉切换，共用同一套三件套密钥，默认超拟人·
  聪小璇）；WebSocket 攒整段、HMAC-SHA256 鉴权、lame(MP3)、
  AVAudioPlayer 播放（进度条+播放/暂停）；引擎/发音人（随引擎联动
  两套）/口语化（仅超拟人）/三滑块均持久化。`T10TTSTests` 30 单测
  绿，§8-6 失败路径随此收口（看板 T12 已闭环）。
- 全量回归 159 测绿、无告警；commit 1349f2c→1e6ea06→b1f7356，
  `--no-ff` 合并为 153e47e，已 `git push origin main`（与 origin 同步）。
- [x] **真机验收通过（2026-05-17，James 在场）**：普通 v2/tts 与
  超拟人 super-tts **两个引擎都实测出声**，UI 切换/发音人/口语化
  正常，三件套 Keychain key 已由 James 写入（两引擎共用）。
- [x] **OpenRouter 泄露 key 已处理**：`sk-or-v1-35ff...` James 已去
  openrouter.ai/keys 作废并重建（长期风险项闭环）。

## 下一步（具体到能直接动手）
1. 按序读 `AGENTS.md` → `relay-task.md` → `project-board.md` → `prd-mvp.md`。
2. **MVP 全闭环：开发完成 + 真机验收通过 + 已合并推送，无剩余任务。**
   接手时无 TODO；如需继续，均属 PRD §9 Defer（分发/签名公证/插件
   等，非 MVP），动手前向 James 确认范围。
3. 其余均 PRD §9 Defer（分发/签名公证/插件等，非 MVP）。
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
- 配置/密钥：`Core/Config/{ProviderConfig,SecretStore,ConfigStore,
  TTSConfig}.swift`
- 持久化：`Core/Persistence/{JSONLResultStore,TTSSettingsStore}.swift`
- providers：`Features/Providers/{OpenAICompatibleLLMProvider,
  RetryingLLMProvider,FreeWebTranslateProvider}.swift`、
  `Features/Providers/XunfeiTTSProvider.swift`（含 `SuperTTSProvider`
  +`FailingTTSProvider`）、`Core/Services/{LLMHTTPClient,
  TranslateHTTPClient,TTSWebSocketClient,SuperTTSWebSocketClient}.swift`
- UI/编排：`UI/{ContentQueryViewModel,MainWindowView,
  RegionSelectionController,TTSPlaybackViewModel,TTSPanelView}.swift`、
  `App/{AppComposition,AppController,PersonalAgentApp}.swift`、
  `Resources/Localizable.xcstrings`（36 键，含 7 TTS + 4 设置）
- P2 整合：`Features/Integration/P2IntegrationCoordinator.swift`
- 截屏/OCR：`Features/Input/{ScreenCapture,ScreenCaptureAuthorizing,
  ScreenCaptureCoordinator,SCScreenCapturer,ScreenGeometry}.swift`、
  `Features/Recognition/{OCRRecognizing,OCRAssembler,OCRCoordinator,
  VisionTextRecognizer,BlankImageDetector}.swift`
- 输入路由：`Core/Input/{InputEntry,AccessibilityAuthorizing,
  InputRouter,HotkeyMonitoring,PasteboardReading,ClipboardTextGrabber}.swift`
- 单测：`PersonalAgentTests/*.swift`（19 文件，含 TINT2/TClipboard
  Dispatch/T12{ScreenDefense,FailurePersistRetry,CancelTimeout,History}/
  T10TTS 30 用例；全量 159 测绿）
- 本轮存档（详细背景去这里翻）：
  `/Users/qoragufimo390gmail.com/baidu/Archives/2026-05-16-personalagent-p2-t12-impl.md`
- 相关 auto memory：`project_2026-05-16_*.md`、`feedback_2026-05-16_*.md`

## 阻塞 / 风险 / 待用户决策
- **无未决阻塞**。MVP 全闭环（开发+真机验收+合并推送）。
- ~~T10 TTS~~：双引擎全完成，2026-05-17 真机验收两引擎均通过。
- ~~OpenRouter key 泄露~~：`sk-or-v1-35ff...` 2026-05-17 James 已
  openrouter.ai/keys 作废重建，风险闭环。
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
