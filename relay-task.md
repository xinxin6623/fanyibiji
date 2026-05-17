# Relay Task

_updated: 2026-05-17 14:20_
_project: /Users/qoragufimo390gmail.com/Documents/New project 3 (PersonalAgent, repo=fanyibiji)_
_branch: feat/ui-easydict-style_

## 任务
参考 Easydict 做 UI 重构 + 翻译目标语言可配置。**已全部完成、测试绿、
用户验收通过，2 commit 待推送 + 开 PR。**(上一轮的划词翻译/设置体系
已合并入 main as PR #1。)

## 当前进度
- [x] TargetLanguage/LanguageConfig/LanguageSettingsStore（7 语言，默认中文）
- [x] ViewModel 目标语言改可配置 + 变更落盘
- [x] 主窗口卡片式重构（工具栏+查询卡+语言方向条+结果/历史/TTS 卡）
- [x] 设置改 Tab 风格（通用/快捷键/密钥/提示词 + 分组列表）
- [x] T15 容错单测，全量测试绿
- [x] 用户验收通过
- [x] 2 commit（b04d39a 语言功能 / e6e9903 UI 重构）
- [ ] 推送 + 开 PR（进行中）

## 下一步

当前没有必须接力的工程下一步——功能闭环、测试绿、验收通过。

如需继续，可选动作：
1. push feat/ui-easydict-style → 开 PR → 合并 → 回 main 同步
2. 若有 UI 细节微调（间距/配色/图标），在本分支继续追加 commit

## 关键文件 / 路径
- 语言：`PersonalAgent/Core/Config/LanguageConfig.swift`、`Core/Persistence/LanguageSettingsStore.swift`
- 主窗口：`PersonalAgent/UI/MainWindowView.swift`（卡片式，CardModifier）
- 设置：`PersonalAgent/UI/HotkeySettingsView.swift`（Tab + settingsGroup）
- 接线：`PersonalAgent/App/AppController.swift`（languageConfig/updateLanguageConfig）
- 测试：`PersonalAgentTests/T15LanguageConfigTests.swift`
- 详细背景：`/Users/qoragufimo390gmail.com/baidu/Archives/2026-05-17-划词翻译与设置体系.md`（含前序）
- auto memory：`project_2026-05-17_selection-translate.md`、`feedback_2026-05-17_macos-swift-pitfalls.md`

## 阻塞 / 风险 / 待用户决策
- 无阻塞。待推送+PR+合并。

## 上下文要点（接手前必读）
1. 跑 `xcodebuild test` 前必先 `pkill -9 -x PersonalAgent`，否则 runner 挂起（本轮又踩一次）
2. 翻译目标语言可配置但源语言仍 auto；语言方向条与设置通用页双向同步
3. TargetLanguage.code 必须与原写死 "zh" 兼容，勿改坏翻译 tl 参数
4. UI 纯视觉重构，未动业务逻辑；CardModifier/settingsGroup 是复用容器
5. 签名用本地自签证书 PersonalAgent Local Development（已稳定）
