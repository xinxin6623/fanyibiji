# Personal Agent MVP PRD

## 1. 需求背景

James 想基于 Easydict 的能力边界，重写一个个人使用的 macOS 助理型 App。
本项目不追求复刻 Easydict，而是抽取最有价值的本地工作流：截屏、OCR、
划线或剪贴板取词、LLM 查询、免费翻译、TTS 播放和结构化结果记录。

第一性原理判断：这个 MVP 的核心价值不是“翻译 App”，而是降低 James 在
阅读、截图、识别、查询和听读之间的上下文切换成本。所有设计都应服务于
快速捕获输入、可靠生成结果、本地保存上下文，以及未来能接知识库。

## 2. 用户目标与非目标

### 用户目标

- 在任意 App 中通过快捷键触发截图 OCR 或文本查询。
- 对截图和选中文本快速发起 LLM 查询。
- 保留一个稳定的免费翻译能力作为辅助结果。
- 将结果通过指定 TTS API 播放。
- 所有结果以结构化方式保存在本机，未来可接知识库和任务系统。

### 非目标

- 不全量 fork Easydict。
- 不复制 Easydict 源码、资源、提示词或逆向接口细节。
- 不在 MVP 阶段做完整插件系统。
- 不在 MVP 阶段做多设备同步、账号系统、云端知识库。
- 不把非官方 Web 翻译接口写成不可替换的核心依赖。

## 3. 默认决策

- 使用场景：个人本地使用，不以对外分发为第一目标。
- UI 形态：第一版采用助理式单窗口，先展示一次查询的主结果、翻译结果和
  TTS 操作入口；不做 Easydict 式复杂多服务同屏。
- 划线取词：MVP 先接受全局快捷键读取剪贴板兜底；正式版再补齐
  Accessibility、AppleScript 和模拟复制链路。
- TTS：先做可配置 provider 接口和占位配置，不在 PRD 中绑定具体供应商。
- 历史记录：第一版使用本地结构化文件，优先 JSONL；后续需要复杂查询时再
  迁移 SQLite 或 SwiftData。

## 4. 核心场景

### 场景 A：截图 OCR 查询

James 在任意界面按下截图快捷键，选择屏幕区域。App 获取截图后调用本地
Vision OCR，整理文本，展示可编辑文本预览，并将文本送入 LLM provider
生成回答。结果保存到本地历史。

### 场景 B：选中文本或剪贴板查询

James 在阅读网页、PDF、聊天或文档时选中文本，按下查询快捷键。MVP 读取
剪贴板文本作为输入，形成 QueryContext，调用 LLM provider，并保存结构化
结果。若剪贴板为空或内容不是文本，必须提示失败原因，不触发空查询。

### 场景 C：免费翻译辅助

同一段输入可调用一个免费翻译 provider，输出 TranslationResult。翻译失败
时不影响 LLM 主结果，只在 UI 中显示 provider 错误。

### 场景 D：TTS 播放

James 对 OCR、翻译或 LLM 输出点击播放。App 将文本发送到指定 TTS provider，
获得音频并播放。鉴权失败、网络失败或文本过长时显示明确错误。

## 5. 数据流向图描述

```text
InputSource
  ├─ screenshot region
  ├─ selected text / clipboard
  └─ manual input
       │
       ▼
Recognition / Normalization
  ├─ Vision OCR -> OCRResult
  └─ Text cleanup -> NormalizedText
       │
       ▼
QueryContext
  ├─ id
  ├─ source
  ├─ inputText
  ├─ createdAt
  ├─ languageHints
  └─ userAction
       │
       ▼
ProviderAdapter
  ├─ LLMProvider -> AssistantResult
  ├─ TranslateProvider -> TranslationResult
  └─ TTSProvider -> AudioResult
       │
       ▼
ResultModel
  ├─ id
  ├─ contextId
  ├─ provider
  ├─ content
  ├─ tags
  ├─ error
  └─ createdAt
       │
       ▼
Local Persistence
  └─ JSONL history first, future database or knowledge base subscriber
```

核心约束：

- 截屏模块只输出图片和元信息。
- OCR 模块只输出识别结果。
- Provider 只做服务适配，不控制 UI。
- UI 只消费结构化结果，不拼接 provider 私有错误。
- 历史和知识库只订阅 ResultModel。

## 6. 模块边界

### Input

- 管理截图、快捷键、剪贴板和手动输入入口。
- 失败时返回明确错误，不吞掉权限失败。
- 不直接调用 LLM、翻译或 TTS。

### Recognition

- 使用 Apple Vision 做本地 OCR。
- 输出 OCRResult，包括文本、置信度、行块、语言提示和原图引用。
- 空结果、低置信度、权限失败必须可区分。

### Query

- 生成 QueryContext。
- 管理一次请求的来源、时间、输入文本和用户动作。
- 不保存 API key。

### Provider

- LLMProvider 支持 OpenAI-compatible endpoint。
- TranslateProvider 第一版只接入一个稳定 provider。
- TTSProvider 支持指定 endpoint、鉴权、文本长度限制和播放结果。
- 所有 provider 必须支持 validate、timeout、cancel 和结构化错误。

### Persistence

- MVP 使用本地 JSONL 保存 ResultModel。
- 每条记录必须包含 id、source、content、provider、created_at、tags、error。
- 不保存明文 API key。

## 7. 权限与隐私边界

- 截屏需要处理屏幕录制权限失败。
- 取词需要处理剪贴板为空、无文本或权限失败。
- 后续 Accessibility/AppleScript 取词必须明确授权和失败提示。
- API key 只能存本地配置或 Keychain，不能写入代码、日志或仓库。
- OCR 图片默认只在本机处理；是否保存原图后续由设置控制。
- LLM、翻译和 TTS 会把文本发送给外部 provider，UI 必须能让用户理解该行为。

## 8. 容灾设计

- 截图失败：提示权限或取消状态，不进入 OCR。
- OCR 空结果：保留图片引用和失败记录，允许用户手动输入文本继续查询。
- 剪贴板取词失败：提示剪贴板为空或非文本，不触发空查询。
- LLM 失败：保存失败 ResultModel，允许重试，不影响翻译和历史。
- 翻译失败：只标记 TranslationResult 错误，不影响 LLM 主流程。
- TTS 失败：停止播放状态，显示鉴权、网络、格式或文本长度错误。
- 历史写入失败：内存中保留当前结果，并提示本地持久化失败。
- Provider 超时：统一 timeout 错误，可取消请求并恢复 UI。

## 9. MVP 范围

### Must Have

- 干净 SwiftUI macOS App 骨架。
- 全局快捷键触发截图 OCR。
- 剪贴板文本查询入口。
- Vision OCR 本地识别。
- OpenAI-compatible LLM provider。
- 一个免费翻译 provider。
- 可配置 TTS provider 接口。
- JSONL 本地历史记录。
- 基础错误提示和权限失败提示。

### Defer

- 完整 Accessibility/AppleScript 取词链路。
- 完整 Event Bus。
- 插件系统。
- 多服务并发聚合。
- 复杂设置页。
- 云同步和账号系统。
- 对外分发、签名公证和 GPL 分发策略。

## 10. 验收标准

- 用户能通过快捷键完成一次截图 OCR 查询。
- 用户能通过剪贴板完成一次文本 LLM 查询。
- OCR、LLM、翻译、TTS 的失败状态可区分且不会导致空查询。
- API key 不进入仓库、日志或文档示例。
- 每次查询至少写入一条本地结构化 ResultModel。
- App 可在 Apple Silicon Mac 上构建和运行。
- 代码中没有复制 Easydict 源码、资源、提示词或逆向实现。

## 11. 下一阶段拆分

- T02：创建 SwiftUI App 骨架。
- T03：实现本地配置与密钥边界。
- T04：实现全局快捷键与输入入口。
- T05：实现截图区域选择。
- T06：实现 Vision OCR。
- T07：实现 OpenAI-compatible LLM Provider。
- T08：实现剪贴板取词。
- T09：接入一个免费翻译 Provider。
- T10：接入指定 TTS Provider。
- T11：实现结构化结果与本地历史。
