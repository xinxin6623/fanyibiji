# Relay Task

_updated: 2026-05-30 19:38_
_project: /Users/macmini/Documents/fanyibiji (PersonalAgent macOS App)_
_branch: main @ 3e70b15（远端最新）_
_工作树: 词卡只存链接（见 §0）+ 已合并入下一 commit（见下方 §B）_
_remote: github.com/xinxin6623/fanyibiji_

## §0. 本轮小改：词卡不再下载 MP3（2026-05-30 19:38）

用户决定：词典双击保存的词卡只在 md 里保留远程音频链接，不再把 mp3 落盘到 `~/knowledge/words/_audio/`。

改动文件：
- `PersonalAgent/Core/Persistence/WordCardStore.swift`
  - 删 `AudioDownloading` 协议、`URLSessionAudioDownloader` 实现、`downloadAudio()`、`Task.detached` 触发
  - `init` 去掉 `downloader:` 参数
  - 不再创建 `_audio/` 子目录
  - body 渲染：`[🔊](_audio/<slug>-us.mp3)` → `[🔊](<usAudioURL>)` 直指远端
  - frontmatter 里的 `us_audio` / `uk_audio` / `audio` 字段仍写远程链接（不变）
- `PersonalAgent/App/AppComposition.swift` — `makeWordCardStore` 文档注释更新（删"MP3 异步落盘"句）
- `PersonalAgentTests/T16WordCardStoreTests.swift` — 删 `StubAudioDownloader`、替换 `testAudioFilesScheduledNextToCard` → `testAudioURLsInlinedAsLinksNotDownloaded`
- `临时位置.md` — §2 词卡说明更新

验证：`xcodebuild build` 通过；`T16WordCardStoreTests` 5/5 pass。

盘上残留：旧 `~/knowledge/words/_audio/` 目录若还在，用户可手删，不影响新词卡。

## 本会话本轮做了什么

### A. 已合并入 main 并推送
**commit `d3bafd2`** — feat: 设置页四 tab 化 + LLM 参数化 + 豆包 TTS 引擎接入
- 设置页 5 tab → 4 tab：`通用 / 快捷键 / 模型 / 转语音`（模型 tab 合 LLM 三件套+提示词；转语音 tab 合 TTS 密钥+语音设置）
- LLM baseUrl/model 从硬编码提到 `LLMSettingsStore`（llm-config.json）
- 豆包 TTS 第三引擎：V1 HTTP 一句话，`POST /api/v1/tts`，`Bearer;<token>` 鉴权，cluster `volcano_tts`
- 10 款 moon_bigtts 预置音色（service 10007 字符版正式开通后授权的）
- 修 body 字段：`volume_ratio → loudness_ratio`，删 `pitch_ratio`（V1 不支持音高）

### B. 本轮第二个 commit（紧随 d3bafd2）

下面这堆是 inline editor 重构 + 文档梳理 + TTS 测试修复：

```
modified:   AGENTS.md                                         ← T10 BLOCKED 标记过期已删；移除 gemini-code 引用
modified:   PersonalAgent.xcodeproj/project.pbxproj           ← 新文件 + Resources/InlineEditor 文件夹引用
modified:   PersonalAgent/UI/NoteEditorView.swift             ← 删编辑/预览分栏，挂 inline editor
modified:   PersonalAgent/UI/NoteEditorViewModel.swift        ← 删 Mode 枚举；insert() 改走 editor 光标插入
modified:   PersonalAgentTests/T10TTSTests.swift              ← 给 ResolvedTTSConfig 补 doubaoAppId/doubaoToken
modified:   relay-task.md                                     ← 本文件

Untracked files:
  PersonalAgent/Resources/InlineEditor/                       ← 新目录（folder reference 已注册 pbxproj）
    inline-editor.html                                          ← TOAST UI WYSIWYG 模板
    toastui-editor.min.js                                       ← 534KB all-in-one bundle（含 ProseMirror）
    toastui-editor.min.css                                      ← 主样式
    toastui-editor-dark.min.css                                 ← 深色覆盖样式
  PersonalAgent/UI/MarkdownInlineEditorView.swift             ← WKWebView wrap + JS↔Swift bridge
```

**全部 build 通过（CODE_SIGN_IDENTITY="-"），项目级测试套 14 pass / 1 unrelated fail**（`T14DictionaryProviderTests.testParsesGoodFixtureECBranch` 是 33a7ff8 词典提交里的预存 fixture 问题，与本轮无关）。

### C. 笔记编辑器（inline 实时渲染）—— 已验证可用，等用户验收
- 路线：WKWebView + **TOAST UI Editor v3.2.2 WYSIWYG**（学习了 Milkdown/TipTap/CodeMirror 等方案后选的，零 build 步骤、标准 UMD）
- 替换原「编辑 / 预览」分栏，单一 WYSIWYG 视图
- 工具栏内置：标题/B/I/S/分隔线/引用/无序/有序/任务清单/缩进/表格/图片/链接/code/codeblock
- 暗色模式：加载 `toastui-editor-dark.min.css` + JS 监听 `prefers-color-scheme` 实时跟系统切换
- 工具栏紧凑化：按钮 26×26、扁平、hover 才显淡灰底（默认 36×36 太大已 CSS 压掉）
- `viewModel.text` 仍是真理源，JS↔Swift 双向桥按 `jsContent` 去重避免回环
- 程序化 `insert(_:)` 走 `editor.insertText()` 在光标处插入（不再覆盖整段文本）
- 诊断管道：JS 任何异常 / init 失败 / 资源 404 都 `postMessage({type:'error'})` → Swift `os.Logger` 旁路到 Console.app

诊断命令（断电需要重排查时用）：
```
/usr/bin/log show --predicate 'subsystem == "com.james.personalagent" AND category == "InlineEditor"' --info --last 1m
```

### D. 踩坑提醒（下一会话/未来人接手前必看）

**坑 1：TOAST UI Editor 的 UMD 文件名有大坑**
- jsdelivr / cdnjs 上的 `@toast-ui/editor@x/dist/toastui-editor.min.js` 是「**外置 ProseMirror 依赖**版」——需要先单独加载 8 个 prosemirror UMD 才能用
- 浏览器 standalone 必须用 NHN 自家 CDN 的 `toastui-editor-all.min.js`（含 prosemirror+DOMPurify 全打进，534KB）
- 本仓沿用名 `toastui-editor.min.js` 但**内容是 all 版**（从 `https://uicdn.toast.com/editor/3.2.2/toastui-editor-all.min.js` 下的）
- 别下错路径 → 永远 `undefined is not a constructor`

**坑 2：暗色 CSS 是单独文件**
- 只设 `theme: 'dark'` 选项不够，必须同时挂 `toastui-editor-dark.min.css`
- jsdelivr 该文件路径是 `/dist/theme/toastui-editor-dark.css`（不在 dist 根目录）

**坑 3：LaunchServices 双 app 注册**
- 本会话清理过一次，注销了 DerivedData 旧 hash 的注册 + Trash 注册
- 现在只剩 `./build/Build/Products/Debug/PersonalAgent.app` 一份
- Trash 里物理文件 macOS 沙箱挡了 shell 直接删——**用户需在 Finder 里手动「清倒废纸篓」彻底干净**

**坑 4：pbxproj 新文件 4 处**
- 本轮新增 `MarkdownInlineEditorView.swift`（用 C1A0...056 / C1F0...056 两组 ID）
- 新增 `Resources/InlineEditor/` 文件夹引用（用 C1A0...055 / C1F0...055，`lastKnownFileType = folder` 自动包含所有子文件）
- 已 `plutil -lint` 通过

## 下一会话开局建议

按这个顺序：

1. **决定本轮怎么提交**——一个 commit 包大笔记编辑器重写 + 文档同步 + TTS 测试修，或拆两个：
   - 拆 a：`feat: 笔记编辑器换成 inline 实时渲染（TOAST UI WYSIWYG）`
     包含：`MarkdownInlineEditorView.swift` + `Resources/InlineEditor/` + `NoteEditorView.swift` + `NoteEditorViewModel.swift` + `project.pbxproj` + `T10TTSTests.swift`（小修）
   - 拆 b：`docs: 同步文档到 d3bafd2 状态 + 修过期标记`
     包含：`AGENTS.md` + `relay-task.md` + 还可补 `project-board.md` 加 T18-T21（**本轮被切换打断没做完，是文档梳理的剩余尾巴**）
   - 推荐：**先拆 b 文档单独提交**（review 成本低），再拆 a 大块提交
2. **真机验收笔记编辑器**——按下面 8 条跑一遍，如有问题再修：
   1. 工具栏图标紧凑无方框；右键能 Inspect Element（开发期 `isInspectable=true`）
   2. 系统切深↔浅，编辑器即时跟着切
   3. 中文 IME 输入流畅
   4. 左侧点「插入到编辑区」→ 译文进光标处不是末尾
   5. 顶栏 ← / → 撤销/重做生效
   6. 关闭再开 app，草稿持久化
   7. 多 tab 草稿切换不串内容
   8. 工具栏点表格/任务列表/代码块都能用；导出 .md 内容正确
3. **如笔记验收没问题**——可考虑 push 后续小补丁：拖拽图片 hook、代码块 syntax highlight 插件、TOAST UI 自定义 toolbar 图标换 SF Symbol 风格

## 关键文件 / 路径速查

- 主真实 App：`./build/Build/Products/Debug/PersonalAgent.app`（用 `xcodebuild -derivedDataPath build CODE_SIGN_IDENTITY="-"` 产）
- 密钥：`~/Library/Application Support/com.james.personalagent/secrets.enc`（含 llm.apiKey / tts 讯飞三件套 / tts.doubao.{appId,token}）
- LLM 配置：`~/Library/Application Support/com.james.personalagent/llm-config.json`
- TTS 配置：`~/Library/Application Support/com.james.personalagent/tts-config.json`
- 提示词：`~/Library/Application Support/com.james.personalagent/prompt-config.json`
- 历史：`~/Library/Application Support/com.james.personalagent/results.jsonl`
- 笔记草稿：`~/Library/Application Support/com.james.personalagent/notes/`
- 词卡：`~/knowledge/words/`
- 编辑器资源（新）：`PersonalAgent/Resources/InlineEditor/{inline-editor.html, toastui-editor*.{js,css}}`

## auto memory 已落地（下一会话自动可读）

- `project_doubao_tts.md`（豆包 V1 接入约束 + 服务开通陷阱 + cluster `volcano_tts` + `loudness_ratio` + Logger 诊断）
- `MEMORY.md` 索引已包含

## Archives 已落地

- `~/baidu/Archives/2026-05-30-personalagent-llm-doubao-tts.md`（豆包 TTS 接入全程：踩坑/cluster/voice 演化/控制台「开通」陷阱）
- 本轮 inline editor 重构尚**未**写 Archives——下一会话提交后再补即可

## 阻塞 / 风险 / 待用户决策

- 无阻塞。所有改动 build 通过 + 测试套通过（除 T14 词典 fixture 失败，与本轮无关）
- 用户已视觉确认笔记编辑器可用且 dark 模式生效；最后一次截图前的 UI 问题（图标过大、暗色没适配）已修，待用户最终验收

## 上下文要点（接手前必读）

1. 反复弹钥匙串密码的真根因是开发期签名指纹漂移（非代码 bug），已绕过（改 FileSecretStore），别再回头查 Keychain 读写代码
2. 本项目 pbxproj 是显式引用式，新增 .swift 要手动补 4 处（PBXBuildFile/PBXFileReference/PBXGroup children/PBXSourcesBuildPhase）
3. 跑 `xcodebuild test` 前先 `pkill -x PersonalAgent`，否则 runner 挂起
4. 仓库 github.com/xinxin6623/fanyibiji，main HEAD=d3bafd2（远端已对齐；本地工作树有 ↑↑ 的未提交改动）
5. 火山引擎控制台「**服务开通**」按钮必须点过 + 「正式版」状态，才会授权 moon_bigtts 系音色；未点会 3001 grant not found
6. 豆包 TTS 诊断日志命令见 §C
7. 设置页结构：4 tab（通用/快捷键/模型/转语音），不要回到 5 tab 老结构
8. TOAST UI Editor 用 `-all` 全打包 UMD 文件，不要换回 jsdelivr 的「外置依赖」版
