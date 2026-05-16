# Relay Task

_updated: 2026-05-16 11:30_
_project: /Users/macmini/Documents/fanyibiji (PersonalAgent macOS App)_
_branch: main_

## 任务
参考 Easydict、干净重写个人用 macOS 助理 App MVP。2026-05-16 经 James
确认执行策略为 P0→P4（先定契约 → 最薄垂直闭环 → 再扩重路径 → 收敛
硬化）。P0 TC 核心契约层已完成，下一步进入 P1 起点 T03。

`relay-task.md` 是唯一交接文件；`handoff.md` 已废弃。

## 当前进度
- [x] P-1 文档与工程骨架（T00/T01/T02）。
- [x] 2026-05-16 总体规划重排为 P0–P4，写入 `project-board.md`。
- [x] P0 TC 核心契约层：6 契约源文件 + 10 单测，
  `xcodebuild build/test` 通过。测试 target 已配 TEST_HOST/BUNDLE_LOADER
  + 对 App target 的依赖。
- [~] P1 起点 T03 本地配置与密钥边界：未开始（待 Admin 设计）。

## 下一步（具体到能直接动手）
1. 按序读 `AGENTS.md` → `relay-task.md` → `project-board.md` → `prd-mvp.md`。
2. 进入 `T03` 的 Admin 阶段：列出本地配置模型、Keychain/API key 边界、
   配置缺失的 `AgentError` 分支、单测点；输出执行路径后**暂停等 James 确认**。
3. James 确认后进 Worker 写代码，验证：
   ```bash
   xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent
   xcodebuild test  -project PersonalAgent.xcodeproj -scheme PersonalAgent
   ```

## 关键文件 / 路径
- Agent 规则：`AGENTS.md`
- 项目看板（P0–P4 拆分/验收）：`project-board.md`
- MVP PRD：`prd-mvp.md`
- 契约层：`PersonalAgent/Core/Models/*.swift`、`Core/Services/ProviderAdapter.swift`
- 契约单测：`PersonalAgentTests/TCContractsTests.swift`
- 本轮存档（详细背景）：`/Users/macmini/baidu/Archives/2026-05-16-personalagent-replan-tc-contracts.md`
- 相关 auto memory：`project_personalagent.md`、`user_james.md`

## 阻塞 / 风险 / 待用户决策
- T10 TTS BLOCKED：供应商、鉴权、音频格式、是否流式待 James 决策；不阻塞 P1/P2。
- 免费翻译 provider 未锁定；逆向 Web API 须隔离在可替换层。
- 未来如对外分发，需重新确认 GPL/签名/公证策略。

## 上下文要点（接手前必读）
- pbxproj 是显式引用工程：新增 .swift 必须手动补
  PBXBuildFile/FileReference/Group/Sources 四处，改后 `plutil -lint` 再 build。
- 持久化编码契约（T11a 沿用）：snake_case + `.iso8601`，时间精度到秒
  （不含亚秒），历史去重/比对按秒。
- 错误统一 `throws AgentError`；UI 只按 `AgentError.category` 分支，
  不拼接 provider 私有错误。
- 复杂任务 Admin → Worker → Overseer；Admin 输出路径后必须等 James 确认。
- 默认干净重写，不复制 Easydict 源码/资源/提示词/逆向实现。
