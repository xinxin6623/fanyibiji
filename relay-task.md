# Relay Task

_updated: 2026-05-16 13:05_
_project: /Users/macmini/Documents/fanyibiji (PersonalAgent macOS App)_
_branch: main_

## 任务
参考 Easydict、干净重写个人用 macOS 助理 App MVP。2026-05-16 经 James
确认执行策略为 P0→P4（先定契约 → 最薄垂直闭环 → 再扩重路径 → 收敛
硬化）。**P0 + 整个 P1 垂直闭环已完成**（剪贴板→LLM→JSONL→展示，
headless 单测全绿），下一步进入 P2 起点 T04 全局快捷键与输入入口。

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
- [x] P1 T-UI1 主窗口接入垂直闭环：DONE。`ContentQueryViewModel` +
  `MainWindowView` + `AppComposition` + 中英本地化，5 单测绿。
  **P1 全部完成，`** TEST SUCCEEDED **`。**

## 下一步（具体到能直接动手）
1. 按序读 `AGENTS.md` → `relay-task.md` → `project-board.md` → `prd-mvp.md`。
2. 进入 **P2 起点 T04 全局快捷键与输入入口**（依赖 TC，已就绪）：
   快捷键注册、输入入口路由（截图/取词/手动输入分流），复用 P1 已验证
   的 `ContentQueryViewModel` 查询管线；快捷键冲突与授权失败要有提示。
   涉及全局快捷键/权限属系统级，按 AGENTS 复杂任务流先 Admin 输出路径；
   James 已授权无系统级/业务问题即连续推进，Admin 写在回复中即可。
3. 后续 P2：T05 截屏区域选择 → T06 Vision OCR → T08 取词。
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
- 垂直闭环 UI：`UI/ContentQueryViewModel.swift`、`UI/MainWindowView.swift`、
  `App/AppComposition.swift`、`Resources/Localizable.xcstrings`
- 单测：`PersonalAgentTests/{TCContractsTests,T03ConfigTests,
  T11aJSONLStoreTests,T07aLLMProviderTests,TUI1QueryFlowTests}.swift`
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
