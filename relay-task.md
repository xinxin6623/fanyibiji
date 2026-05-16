# Relay Task

_updated: 2026-05-15 13:35_
_project: /Users/qoragufimo390gmail.com/Documents/New project 3_
_branch: main_

## 任务
本项目正在把 Easydict 的可参考能力边界，干净重写为个人使用的 macOS 助理型 App MVP。当前应从已完成的 SwiftUI App 骨架继续，进入 `T03 本地配置与密钥边界`。

`relay-task.md` 是本项目唯一交接文件；`handoff.md` 已废弃，只保留跳转说明，避免与 `/wrap-up` 技能生成的接力单重复维护。

## 当前进度
- [x] T00 项目文档骨架：`AGENTS.md`、`relay-task.md`、`project-board.md` 已建立。
- [x] T01 MVP PRD：`prd-mvp.md` 已完成，锁定个人本地、干净重写、助理式单窗口、剪贴板兜底、JSONL 历史。
- [x] T02 SwiftUI App 骨架：`PersonalAgent.xcodeproj`、SwiftUI 入口、主窗口、本地化占位、资源占位、测试 target 和推荐目录结构已建立。
- [x] 本机完整 Xcode 已安装并选中：`/Applications/Xcode.app/Contents/Developer`，版本 `Xcode 26.5 (17F42)`。
- [x] 当前项目已通过构建验证：`xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent` 结果 `BUILD SUCCEEDED`。
- [~] 下一阶段是 `T03 本地配置与密钥边界`，尚未开始实现。

## 下一步（具体到能直接动手）
1. 按顺序读取 `AGENTS.md`、`relay-task.md`、`project-board.md`、`prd-mvp.md`，确认边界。
2. 进入 `T03 本地配置与密钥边界` 的 Admin 阶段，先列出配置模型、Keychain/API key 边界、错误模型和验证方式。
3. 等 James 确认 T03 执行范围后，再进入 Worker 阶段写代码。
4. 验证时运行：

```bash
xcodebuild build -project PersonalAgent.xcodeproj -scheme PersonalAgent
```

## 关键文件 / 路径
- Agent 规则：`AGENTS.md`
- 当前交接：`relay-task.md`
- 旧交接入口：`handoff.md`（已废弃，只作跳转）
- 项目看板：`project-board.md`
- MVP PRD：`prd-mvp.md`
- T02 规划：`T02-admin-plan.md`
- SwiftUI 工程：`PersonalAgent.xcodeproj`
- App 入口：`PersonalAgent/App/PersonalAgentApp.swift`
- 主窗口：`PersonalAgent/UI/MainWindowView.swift`
- 本地化：`PersonalAgent/Resources/Localizable.xcstrings`

## 阻塞 / 风险 / 待用户决策
- T03 可以先做配置边界，不需要真实 API key；不要修改或覆盖 `.env`。
- TTS API 供应商、鉴权方式、音频格式和是否流式仍待 James 决策。
- 免费翻译 provider 未锁定；如使用逆向 Web API，必须隔离在可替换 provider 层。
- 未来如果对外分发，需要重新确认 GPL、签名、公证和发布策略。
- 当前未安装 Simulator runtime；不影响 macOS App 构建，如后续跑 iOS 模拟器再单独安装。

## 上下文要点（接手前必读）
- 默认策略是干净重写，不复制 Easydict 源码、资源、提示词、逆向接口细节或私有实现。
- MVP 使用 modular monolith，不提前引入重型 Event Bus 或完整插件系统。
- 标准数据流：`InputSource -> Recognition -> QueryContext -> ProviderAdapter -> ResultModel -> Persistence`。
- UI 只消费结构化结果，不拼接 provider 私有错误；Provider 不直接控制 UI。
- API key 只走本地配置或 Keychain，不进入仓库、日志或示例文件。
- 复杂任务遵循 Admin -> Worker -> Overseer；复杂任务在 Admin 阶段输出执行路径后必须等待 James 确认。
