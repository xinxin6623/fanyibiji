# Relay Task

_updated: 2026-05-17 14:50_
_project: /Users/qoragufimo390gmail.com/Documents/New project 3 (PersonalAgent, repo=fanyibiji)_
_branch: main_

## 任务
Easydict UI 重构 + 语言可配置 + TTS 交互重构。**已全部完成、验收通过、
PR #2 Squash 合并入 main，分支清理完毕。当前无进行中任务。**

## 当前进度
- [x] PR #1 已合并：划词翻译 + 设置体系 + 5 bug 修复
- [x] PR #2 已合并(squash, commit 0e68150)：Easydict UI 重构 / 语言可配置(7 语言) / TTS 交互重构
- [x] 全部用户真机验收通过
- [x] main 已同步，feature 分支已删

## 下一步

当前没有必须接力的工程下一步——两轮迭代均闭环合并。

如需继续，可选动作：
1. 用户自行在设置「提示词」Tab 写专有名词翻译规则（仅 LLM 路径生效，见下方上下文要点）
2. 若有新 UI/功能需求，从 main 开新 feature 分支

## 关键文件 / 路径
- 主窗口：`PersonalAgent/UI/MainWindowView.swift`（卡片式 + 朗读输入/结果按钮）
- 设置：`PersonalAgent/UI/HotkeySettingsView.swift`（5 Tab：通用/快捷键/密钥/提示词/语音）
- 语言：`PersonalAgent/Core/Config/LanguageConfig.swift`
- 翻译通道：`PersonalAgent/Features/Providers/FreeWebTranslateProvider.swift`（免费 Google gtx，黑盒）
- LLM：`PersonalAgent/Features/Providers/OpenAICompatibleLLMProvider.swift`（system prompt 注入）
- 详细背景：`/Users/qoragufimo390gmail.com/baidu/Archives/2026-05-17-划词翻译与设置体系.md`
- auto memory：`project_2026-05-17_selection-translate.md`、`feedback_2026-05-17_macos-swift-pitfalls.md`、`project_2026-05-17_translate-channels.md`

## 阻塞 / 风险 / 待用户决策
- 无阻塞。两轮迭代已合并入 main。

## 上下文要点（接手前必读）
1. **两条翻译通道**：取词/划词/截屏 OCR → FreeWebTranslateProvider(免费 Google gtx 黑盒，**无任何风格/术语控制位**，加不了规则)；发起查询/取词问 AI → LLM(可被系统提示词约束)
2. 带规则翻译(如"专有名词保留原文+括号中文")只能走 LLM 路径，不能改免费通道
3. 跑 `xcodebuild test` 前必先 `pkill -9 -x PersonalAgent`，否则 runner 挂起
4. 新增 .swift 必须手动加 pbxproj 4 处；Codable 用显式 snake_case CodingKeys
5. 签名用本地自签证书 PersonalAgent Local Development（已稳定）
