# Relay Task

_updated: 2026-05-17 11:40_
_project: /Users/qoragufimo390gmail.com/Documents/New project 3 (PersonalAgent, repo=fanyibiji)_
_branch: main_

## 任务
PersonalAgent 加划词翻译（Easydict 式）+ 统一设置体系（快捷键/密钥/系统提示词均可配置持久化），
并修掉过程中暴露的 5 个 bug。功能与测试全部完成，处于「用户验收中、改动未提交」状态。

## 当前进度
- [x] 划词翻译（SelectionTextGrabber + 模拟⌘C，已真机验收通过）
- [x] 快捷键自定义（KeyRecorder 已验收通过）
- [x] 密钥进设置（已验收：能存、显示"已配置"，弹密码问题解决）
- [x] LLM provider 重建（已验收：查询通了）
- [x] 系统提示词功能（PromptConfig + 注入 + 设置 UI，测试全绿）
- [~] 用户正在验收「发起查询」的系统提示词实际效果（待用户反馈）
- [ ] 24 文件改动提交（等验收通过）

## 下一步
1. 等用户确认「发起查询」按系统提示词风格回答（简洁/中文/不闲聊）
2. 验收通过后整理 commit，建议按主题拆 5 个：
   划词翻译 / 快捷键设置 / 密钥设置UI / 系统提示词 / bug修复(codable+keychain+keyrecorder+provider重建+测试宿主)
3. commit 信息末尾加 `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`，按需 push

如验收发现问题，常见排查见「上下文要点」。

## 关键文件 / 路径
- 划词：`PersonalAgent/Core/Input/SelectionTextGrabber.swift`、`SystemCopyKeystrokeSender.swift`
- 快捷键：`PersonalAgent/Core/Config/HotkeyConfig.swift`、`Core/Persistence/HotkeySettingsStore.swift`
- 提示词：`PersonalAgent/Core/Config/PromptConfig.swift`、`Core/Persistence/PromptSettingsStore.swift`
- 设置 UI：`PersonalAgent/UI/HotkeySettingsView.swift`（含 KeyRecorder/secrets/prompt 三区）
- 接线：`PersonalAgent/App/AppController.swift`、`AppComposition.swift`
- LLM 注入：`PersonalAgent/Features/Providers/OpenAICompatibleLLMProvider.swift`
- 测试：`PersonalAgentTests/T13*.swift`、`T14*.swift`
- 详细背景：`/Users/qoragufimo390gmail.com/baidu/Archives/2026-05-17-划词翻译与设置体系.md`
- auto memory：`project_2026-05-17_selection-translate.md`

## 阻塞 / 风险 / 待用户决策
- 无阻塞。唯一待用户确认：系统提示词验收 + 是否现在提交
- 翻译通道维持免费（FreeWebTranslateProvider），系统提示词只影响 LLM 查询——这是已确认的设计，勿误改

## 上下文要点（接手前必读）
1. 签名用本地自签证书 `PersonalAgent Local Development`（已稳定，勿改回 ad-hoc）
2. 跑 `xcodebuild test` 前必先 `pkill -x PersonalAgent`，否则 runner 挂起
3. 新增 .swift 必须手动加 pbxproj 4 处（Python 脚本，本轮已建立样板做法）
4. Codable 模型一律用显式 snake_case CodingKeys，store 不设 key 转换策略
5. 配置变更后必须重建对应 provider（provider 持有快照），LLM 走 AppController.replaceProvider
