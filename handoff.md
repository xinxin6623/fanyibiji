# Agent Handoff

## Current Snapshot

- 当前阶段：`T02 SwiftUI App 骨架` 已完成，准备进入 `T03 本地配置与密钥边界`。
- 下一步：进入 T03，落地本地配置模型、Keychain/API key 边界和配置缺失错误。
- 已锁默认：个人本地、干净重写、助理式单窗口、剪贴板兜底、JSONL 历史。
- 未决事项：TTS API、免费翻译 provider、未来分发策略。
- 禁止事项：不复制 Easydict 源码，不写入 API key，不提前做插件系统。

## 项目一句话定位

本项目是一个参考 Easydict 能力边界、但默认干净重写的个人 macOS 助理型
App MVP，核心闭环是截屏、OCR、划线或剪贴板取词、LLM 查询、免费翻译和
指定 TTS API。

## 当前阶段

- 阶段：SwiftUI App 骨架已完成。
- 当前状态：已有 `PersonalAgent.xcodeproj`、SwiftUI App 入口、主窗口、
  本地化占位、资源占位、测试 target 和推荐目录结构；构建和测试已通过。
- 下一任务：执行 `T03 本地配置与密钥边界`，但不要写入真实 API key 或覆盖
  `.env`。

## 新会话必读顺序

1. `AGENTS.md`：Codex 默认入口，项目级 Agent 行为规则、架构边界和禁止事项。
2. `handoff.md`：当前接续状态、关键决策、风险和下一步。
3. `project-board.md`：总体规划、任务拆分、任务状态和验收标准。
4. `prd-mvp.md`：MVP 需求、数据流、容灾设计和验收标准。
5. `T02-admin-plan.md`：只有在进入 SwiftUI App 骨架任务时再读取。
6. `gemini-code-1778814575509.json`：只有在需要追溯 Easydict 对齐细节、
   模块路径或开发规范时再读取。
7. `想法.md`：只有在需要回看原始需求语义时再读取。

## 已确认架构决策

- 默认不全量 fork Easydict；按干净重写推进个人 MVP。
- Easydict 只作为模块边界、工程经验和能力语义参考。
- GPL-3.0 是硬边界：复制或派生 Easydict 源码并对外分发时必须按 GPL
  处理。
- 新功能默认 Swift / SwiftUI first，macOS 13.0+，Swift 5.9，Xcode 15+。
- MVP 使用 modular monolith，不提前引入重型 Event Bus。
- 结果必须结构化，为未来知识库、历史记录和任务看板预留接口。
- 敏感信息本地优先，API key 不能写进仓库，优先走本地配置或 Keychain。
- 复杂任务遵循 Admin -> Worker -> Overseer；Admin 规划后等待 James 确认。

## 当前未解决决策

- 指定 TTS API 的具体供应商、鉴权方式、音频返回格式和流式要求。
- 未来如果对外分发，需要重新确认 GPL、签名、公证和发布策略。
- 免费翻译第一版具体 provider 还未锁定，但不阻塞 T02 App 骨架。

## 下一步建议

优先执行 `T03 本地配置与密钥边界`：

- 定义本地配置模型和配置缺失错误。
- 明确 API key 只能走 Keychain 或用户本地配置，不进入仓库、日志或示例。
- 不修改或覆盖 `.env`。
- 验证命令使用仓库内 DerivedData：
  `xcodebuild -project PersonalAgent.xcodeproj -scheme PersonalAgent -destination platform=macOS -derivedDataPath .DerivedData build`

## 风险与边界

- GPL 风险：不得为了提速复制 Easydict 源码、资源、提示词或逆向细节实现。
- macOS 权限风险：截屏、Accessibility、AppleScript、模拟复制都可能需要
  明确授权和失败兜底。
- 剪贴板风险：取词实现不能永久破坏用户剪贴板。
- API 风险：LLM 和 TTS 鉴权信息不能写入仓库；provider 必须有 timeout、
  cancel、validate 和错误模型。
- 架构风险：MVP 不上重型插件系统或 Event Bus，先把核心闭环做小做稳。
- ARM 风险：后续 Docker、本地模型或二进制依赖要确认 `linux/arm64`。

## 最近变更摘要

- 2026-05-15：创建 `AGENTS.md`，定义项目级 Agent 规则、架构边界和协作流。
- 2026-05-15：人工对齐 `gemini-code-1778814575509.json`，修正 Easydict
  模块路径、GPL 策略和 MVP 开发规范。
- 2026-05-15：创建 `handoff.md` 和 `project-board.md`，用于新会话接续和
  项目进度管理。
- 2026-05-15：创建 `prd-mvp.md`，完成 T01 MVP PRD，锁定默认 UI、取词、
  历史记录和 provider 边界。
- 2026-05-15：删除 `agent.md` / `S.MD`，改用 Codex 默认读取的 `AGENTS.md`
  作为唯一项目入口；新增
  `T02-admin-plan.md`。
- 2026-05-15：根据 `feasibility-review.md` 同步 T02 状态；补充
  `.gitignore`，移除骨架阶段不必要的 `#Preview` 宏；`xcodebuild build`
  与 `xcodebuild test` 通过。

## 交接维护规则

- 只记录当前事实、关键决策、阻塞项和下一步，不写长过程日志。
- 每次完成一个任务，只更新必要摘要和下一任务。
- 详细历史放到 Git 记录、任务备注或专门归档，不塞进本文件。
- 文件目标是让新会话 2 分钟内知道当前该做什么。
