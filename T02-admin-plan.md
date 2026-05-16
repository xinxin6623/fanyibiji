# T02 Admin Plan - SwiftUI App 骨架

## 1. 目标

创建一个干净重写的 macOS SwiftUI App 工程，为后续 T03-T11 功能提供稳定
骨架。T02 只建立工程、目录、基础窗口和构建验证，不实现截图、OCR、LLM、
翻译或 TTS 业务逻辑。

## 2. 推荐默认决策

- 工程名：`PersonalAgent`。
- App 显示名：`Personal Agent`。
- Bundle ID：`com.james.personalagent`。
- 最低系统版本：macOS 13.0。
- 语言：Swift。
- UI：SwiftUI first，必要时再引入 AppKit。
- 工程方式：优先使用原生 Xcode 工程，不引入 XcodeGen。
- 依赖策略：T02 不新增第三方依赖。
- 目录策略：先保持小而清晰，不提前做插件系统。

选择理由：

- 原生 Xcode 工程对当前阶段最直接，不增加额外生成工具。
- `PersonalAgent` 作为工程名适合 Swift module 和目录命名。
- `com.james.personalagent` 是个人本地 MVP 可用的 bundle id；未来分发前再
  调整签名和 Team 配置。

## 3. 推荐目录结构

```text
PersonalAgent/
  App/
    PersonalAgentApp.swift
  UI/
    MainWindowView.swift
  Core/
    Models/
    Services/
    Persistence/
  Features/
    Input/
    Recognition/
    Providers/
  Resources/
    Assets.xcassets
    Localizable.xcstrings
PersonalAgentTests/
```

目录含义：

- `App`：App 入口、生命周期和窗口组织。
- `UI`：第一版助理式单窗口界面。
- `Core/Models`：QueryContext、ResultModel 等共享模型的未来落点。
- `Core/Services`：通用服务抽象和错误模型的未来落点。
- `Core/Persistence`：JSONL 历史记录的未来落点。
- `Features/Input`：快捷键、剪贴板、截图入口的未来落点。
- `Features/Recognition`：Vision OCR 的未来落点。
- `Features/Providers`：LLM、翻译、TTS provider 的未来落点。
- `Resources`：资源和本地化文件。

## 4. T02 执行范围

### 必须做

- 创建 macOS SwiftUI App 工程。
- 设置 macOS 13.0+。
- 创建基础目录结构。
- 创建空白主窗口，显示项目名、当前阶段和下一步提示。
- 创建 `Localizable.xcstrings` 占位，避免后续硬编码用户可见文案。
- 创建测试 target 占位。
- 确认不复制 Easydict 源码、资源或逆向实现。
- 运行一次构建验证。
- 更新 `relay-task.md` 和 `project-board.md`。

### 不做

- 不实现真实截图。
- 不实现 OCR。
- 不接 LLM、翻译或 TTS API。
- 不写 API key 或 `.env`。
- 不创建插件系统。
- 不引入第三方依赖。
- 不处理签名公证和对外分发。

## 5. Admin 阶段需要 James 确认的点

如果没有额外要求，按推荐默认决策执行：

- App 显示名是否使用 `Personal Agent`。
- Bundle ID 是否使用 `com.james.personalagent`。
- 是否接受原生 Xcode 工程，而不是 XcodeGen。

## 6. 验收标准

- 根目录出现可打开的 Xcode 工程或 workspace。
- App target 可构建。
- 主窗口能启动并显示基础页面。
- 工程最低系统版本为 macOS 13.0+。
- 工程内 `SWIFT_VERSION = 5.0` 表示 Swift 5 语言兼容模式；工具链版本以
  当前 Xcode 为准，项目规范中的 Swift 5.9+ 作为最低开发工具链要求。
- 目录结构与本计划一致或有清楚说明。
- 没有复制 Easydict 源码、资源、提示词或逆向实现。
- 没有 API key、`.env` 或个人签名配置进入仓库。

## 7. 验证命令

推荐验证：

```bash
xcodebuild -project PersonalAgent.xcodeproj -scheme PersonalAgent -destination platform=macOS -derivedDataPath .DerivedData build
```

如果后续采用 workspace，则改为：

```bash
xcodebuild build -workspace PersonalAgent.xcworkspace -scheme PersonalAgent
```

构建失败时先检查 Xcode 工程设置、最低系统版本、target membership 和资源
引用，不要通过引入额外依赖绕过骨架问题。
