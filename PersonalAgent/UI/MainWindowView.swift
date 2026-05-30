import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Easydict 风格主窗口：卡片式分区 + 顶部固定工具栏 + 语言方向条。
///
/// 视觉重构（不动业务逻辑）：
///  - 顶部工具栏：标题 + 设置齿轮（pin 等高级项暂不引入）
///  - 查询卡：圆角分区，输入框 + 底部操作图标行（查询/截屏/取词/清除）
///  - 语言方向条：源 `自动检测` ↔ 目标可选（驱动 viewModel.targetLanguage）
///  - 结果卡：圆角分区，loading/成功/失败/历史各自成卡
///  - TTS 卡：独立分区
struct MainWindowView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject private var viewModel: ContentQueryViewModel
    @ObservedObject private var noteDocs: NoteDocumentsViewModel
    /// 原料包导出读全量翻译历史(只读 results.jsonl)。
    private let exportResultStore: JSONLResultStore
    @State private var showingHistory = false
    @State private var showingHotkeySettings = false

    /// app 内划词朗读控制器（监听选区→鼠标上方弹朗读浮层）。
    @State private var selectionSpeak = SelectionSpeakController()

    /// 左栏宽度（可拖动分隔条调整）。范围夹在 [minPane, total-minPane]。
    @State private var leftPaneWidth: CGFloat = 360
    private let minPaneWidth: CGFloat = 280
    private let dividerWidth: CGFloat = 8

    /// 左栏内"输入区"占比（0–1，可拖动横向分隔条调整）。
    /// 输入/输出上下分栏，各自独立滚动；分隔条夹在 [0.2, 0.8]。
    @State private var inputFraction: CGFloat = 0.45
    private let minInputFraction: CGFloat = 0.2
    private let maxInputFraction: CGFloat = 0.8
    private let hDividerHeight: CGFloat = 8

    init(viewModel: ContentQueryViewModel,
         noteDocs: NoteDocumentsViewModel,
         exportResultStore: JSONLResultStore) {
        self.viewModel = viewModel
        self.noteDocs = noteDocs
        self.exportResultStore = exportResultStore
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                leftPane
                    .frame(width: clampedLeftWidth(total: geo.size.width))
                splitDivider(total: geo.size.width)
                notePane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 920, minHeight: 560)
        .background(ClaudeTheme.background)
        .tint(ClaudeTheme.accent)
        .sheet(isPresented: $showingHotkeySettings) {
            HotkeySettingsView(config: controller.hotkeyConfig,
                               promptConfig: controller.promptConfig,
                               llmConfig: controller.llmConfig)
                .environmentObject(controller)
        }
        .onAppear {
            selectionSpeak.onSpeak = { text in
                handleSelectionSpeak(text)
            }
            selectionSpeak.start()
        }
        .onDisappear { selectionSpeak.stop() }
    }

    /// 划词浮层「朗读」点击：合成落盘 → 播放 → 在选中笔记 Tab
    /// 头部插「🔊 [语音](file://路径)」+ 原文（James 决策：链接在
    /// 原文之前）。无选中 Tab 时只播放（无处可插，静默跳过插入）。
    private func handleSelectionSpeak(_ text: String) {
        Task { @MainActor in
            guard let url = await controller.ttsViewModel
                .synthesizeSaveAndPlay(text: text) else { return }
            let snippet = "🔊 [语音](\(url.absoluteString)) \(text)"
            noteDocs.selected?.editor.insert(snippet)
        }
    }

    // MARK: - 左栏（原查询/结果/历史）

    /// 固定头部（工具栏 / TTS 播放条 / 语言条）+ 下方输入·输出
    /// 上下可拖动分栏。TTS 按 James 要求常驻左栏顶部。
    private var leftPane: some View {
        VStack(spacing: 0) {
            toolbar
            hairline
            if let category = controller.captureFailure {
                permissionBanner(category)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            GeometryReader { geo in
                let inputH = clampedInputHeight(total: geo.size.height)
                VStack(spacing: 0) {
                    // 输入区：仅文字框独立滚动
                    ScrollView {
                        queryEditor
                            .frame(minHeight: inputH - 44)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    .frame(height: inputH)

                    // 工具行钉在分隔线正上方，不随输入滚动
                    queryToolbarRow

                    hSplitDivider(total: geo.size.height)

                    // 输出区（结果/历史）：独立滚动
                    ScrollView {
                        Group {
                            if showingHistory { historyCard } else { resultCard }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - 输入/输出上下可拖动分隔

    private func clampedInputHeight(total: CGFloat) -> CGFloat {
        let usable = max(total - hDividerHeight, 1)
        let f = min(max(inputFraction, minInputFraction), maxInputFraction)
        return usable * f
    }

    private func hSplitDivider(total: CGFloat) -> some View {
        Rectangle()
            .fill(ClaudeTheme.separator)
            .frame(height: hDividerHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(ClaudeTheme.secondaryText.opacity(0.4))
                    .frame(width: 36, height: 3))
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let usable = max(total - hDividerHeight, 1)
                        let cur = clampedInputHeight(total: total)
                        let proposed = (cur + value.translation.height) / usable
                        inputFraction = min(max(proposed, minInputFraction),
                                            maxInputFraction)
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
    }

    // MARK: - 可拖动分隔条

    private func clampedLeftWidth(total: CGFloat) -> CGFloat {
        let maxLeft = max(minPaneWidth, total - minPaneWidth - dividerWidth)
        return min(max(leftPaneWidth, minPaneWidth), maxLeft)
    }

    private func splitDivider(total: CGFloat) -> some View {
        Rectangle()
            .fill(ClaudeTheme.separator)
            .frame(width: dividerWidth)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(ClaudeTheme.secondaryText.opacity(0.4))
                    .frame(width: 3, height: 36)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let proposed = clampedLeftWidth(total: total)
                            + value.translation.width
                        let maxLeft = max(minPaneWidth,
                                          total - minPaneWidth - dividerWidth)
                        leftPaneWidth = min(max(proposed, minPaneWidth), maxLeft)
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }

    // MARK: - 顶部工具栏

    /// 顶栏：左侧 TTS 播放条（播放/进度/速度，占主空间），右侧
    /// 历史/设置图标。原 `字` 图标与 "Personal Agent" 标题按 James
    /// 要求去掉（无信息量、占地方）。
    private var toolbar: some View {
        HStack(spacing: 14) {
            TTSPanelView(viewModel: controller.ttsViewModel)

            Button {
                showingHistory.toggle()
                if showingHistory { viewModel.loadHistory() }
            } label: {
                Image(systemName: showingHistory
                      ? "clock.fill" : "clock")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(showingHistory ? "history.hide" : "history.show")
            .nativeTooltip(String(localized: showingHistory
                                   ? "history.hide" : "history.show"))

            Button {
                showingHotkeySettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("settings.hotkey.title")
            .nativeTooltip(String(localized: "settings.hotkey.title"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// 极细分隔线（1px 暖灰，参考 James 给的设计图）。Divider 默认
    /// 偏粗且系统色，统一换成这个。
    private var hairline: some View {
        ClaudeTheme.separator
            .frame(height: 1)
    }

    // MARK: - 查询卡

    /// 输入文字框（无边框、落窗口底色，James 决策）。放进可滚动区，
    /// 长文本在此滚动；工具行已抽出钉在分隔线上方不随其滚。
    private var queryEditor: some View {
        TextEditor(text: $viewModel.inputText)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 工具行（图标 + 中英切换 + 朗读图标）。从输入框内抽出，钉在
    /// 可拖动分隔线**正上方**，不随输入文字滚动（James 决策）。
    /// 上方那条 hairline 已按 James 要求去掉。
    private var queryToolbarRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // 词典查询（最左第一个，James 决策）。独立通道：与翻译/LLM
                // 完全分流，失败仅影响本通道，UI 可一键改用翻译。
                iconButton("character.book.closed", "manualInput.dictionary") {
                    viewModel.dispatch {
                        await viewModel.runDictionaryLookup(
                            viewModel.inputText,
                            sourceKind: .manualInput)
                    }
                }
                .disabled(isLoading || viewModel.inputText.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty)

                // 直接翻译输入框文本（走免 key 翻译通道）。
                // 与取词翻译同管线，sourceKind 记 .manualInput 供溯源。
                iconButton("character.bubble", "manualInput.translate") {
                    viewModel.dispatch {
                        await viewModel.runTranslate(
                            viewModel.inputText,
                            sourceKind: .manualInput)
                    }
                }
                .disabled(isLoading || viewModel.inputText.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty)

                // 问 AI（原 paperplane 发送查询，图标换 brain，
                // 提示改「问AI」，James 决策）。
                iconButton("brain", "query.run") {
                    viewModel.dispatch { await viewModel.runQuery() }
                }
                .disabled(isLoading)

                iconButton("camera.viewfinder", "capture.run") {
                    controller.triggerCapture()
                }
                .disabled(isLoading)

                // 直接把输入框内容原样插入选中 Tab 笔记（无原文/译文
                // 标签，不登记 sourceResultID——这只是手敲原料不是翻译
                // 结果，James 决策）。空输入或无选中 Tab 时禁用。
                iconButton("text.append", "note.insert_input") {
                    noteDocs.selected?.editor.insert(viewModel.inputText)
                }
                .disabled(noteDocs.selected == nil
                          || viewModel.inputText.trimmingCharacters(
                            in: .whitespacesAndNewlines).isEmpty)

                if isLoading {
                    ProgressView().controlSize(.small)
                    if viewModel.canCancel {
                        iconButton("xmark.circle.fill", "query.cancel") {
                            viewModel.cancelCurrent()
                        }
                    }
                } else if !viewModel.inputText.isEmpty {
                    iconButton("xmark.circle", "query.clear") {
                        viewModel.inputText = ""
                    }
                }

                Spacer()

                // 中英切换按钮（James 决策：只留中英两种，点击在
                // 中文 ⇄ English 间 toggle，去掉多语言下拉）。
                Button {
                    viewModel.targetLanguage =
                        viewModel.targetLanguage == .chinese ? .english
                                                             : .chinese
                } label: {
                    Text(viewModel.targetLanguage == .chinese
                         ? "中 / EN" : "EN / 中")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ClaudeTheme.primaryText)
                }
                .buttonStyle(.plain)
                .help("lang.toggle")
                .nativeTooltip(String(localized: "lang.toggle"))

                // 朗读输入框文本：只留图标（与左侧工具图标统一细线性，
                // James 决策：去文字去描边）。
                iconButton("speaker.wave.2", "tts.speak_input") {
                    controller.ttsViewModel.synthesizeAndPlay(
                        text: viewModel.inputText)
                }
                .disabled(viewModel.inputText.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 结果卡

    @ViewBuilder
    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.state {
            case .idle:
                cardHint("query.idle")
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("query.loading").foregroundStyle(.secondary)
                }
            case let .success(model):
                if case let .dictionary(entry) = model.content {
                    // 词典专用卡片(完整渲染),不走通用 header+Text 路径。
                    // 词头双击保存到 ~/knowledge/words/<word>.md。
                    DictionaryCardView(entry: entry,
                                       wordStore: controller.wordCardStore)
                } else {
                    resultHeader(text: resultText(model),
                                 sourceText: model.sourceText,
                                 resultID: model.id)
                    Text(resultText(model))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case let .failure(category):
                Label {
                    Text(Self.messageKey(for: category))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    if viewModel.canRetry {
                        Button("query.retry") {
                            viewModel.dispatch { await viewModel.retryLast() }
                        }
                        .controlSize(.small)
                    }
                    // 词典失败专用：一键改用翻译通道(中文/句子/未收录词)。
                    if viewModel.canFallbackToTranslate {
                        Button("dictionary.fallback_to_translate") {
                            viewModel.dispatch { await viewModel.fallbackToTranslate() }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - 笔记区(多草稿 Tab + 历史 + 原料包导出)

    private var notePane: some View {
        VStack(spacing: 0) {
            noteTabBar
            Divider()
            if let sel = noteDocs.selected {
                // 用 id 强制 Tab 切换时重建 NoteEditorView,各自绑定
                // 自己的 NoteEditorViewModel(隔离 text/saveStatus)。
                NoteEditorView(viewModel: sel.editor)
                    .id(sel.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .background(ClaudeTheme.background)
    }

    private var noteTabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(noteDocs.tabs) { tab in
                        noteTabChip(tab)
                    }
                }
                .padding(.horizontal, 4)
            }
            Divider().frame(height: 18)
            Button {
                noteDocs.newDocument()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("note.tab.new")
            .nativeTooltip(String(localized: "note.tab.new"))

            historyMenu

            notePackExportButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func noteTabChip(_ tab: NoteDocumentsViewModel.Tab) -> some View {
        let isSel = tab.id == noteDocs.selectedID
        return HStack(spacing: 4) {
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 140)
            Button {
                noteDocs.closeDocument(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("note.tab.close")
            .nativeTooltip(String(localized: "note.tab.close"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSel ? Color.accentColor.opacity(0.18)
                          : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { noteDocs.select(tab.id) }
    }

    private var historyMenu: some View {
        Menu {
            let items = noteDocs.history()
            if items.isEmpty {
                Text("note.history.empty")
            } else {
                ForEach(items) { it in
                    Button(it.title) { noteDocs.openFromHistory(it.id) }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("note.history")
        .nativeTooltip(String(localized: "note.history"))
    }

    /// 导出原料包:当前 Tab 的草稿全文 + **它自己的** referencedResultIDs
    /// → NotePackComposer(A 源追∪B 文本兜底)→ NSSavePanel 另存。
    /// 绝不跨 Tab 取 result id(否则混入别草稿翻译历史)。
    private var notePackExportButton: some View {
        Button {
            exportNotePack()
        } label: {
            Label("note.pack.export", systemImage: "shippingbox")
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .help("note.pack.export.help")
        .disabled(noteDocs.selected == nil)
    }

    private func exportNotePack() {
        guard let sel = noteDocs.selected else { return }
        let draft = sel.editor.text
        let refIDs = sel.editor.referencedResultIDs
        let allResults = (try? exportResultStore.readAll()) ?? []
        let md = NotePackComposer.compose(
            draft: draft,
            referencedResultIDs: refIDs,
            allResults: allResults)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let stamp = Self.packStampFormatter.string(from: Date())
        panel.nameFieldStringValue = "note-pack-\(stamp).md"
        panel.message = String(localized: "note.pack.export.help")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try md.data(using: .utf8)?.write(to: url, options: .atomic)
            sel.editor.markExported(to: url)
        } catch {
            sel.editor.markExportFailed()
        }
    }

    private static let packStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private func resultHeader(text: String,
                              sourceText: String? = nil,
                              resultID: UUID? = nil) -> some View {
        HStack {
            // 「翻译结果」标题+图标已按 James 要求删掉，只留右侧
            // 两个操作按钮（插入笔记 / 朗读结果），靠右浮在结果上方。
            Spacer()
            // 插入到右侧**选中 Tab** 的笔记草稿;同时登记来源
            // result id(原料包 A 源追)。无选中 Tab 时按钮禁用。
            // 有原文则按「**原文:** … / **译文:** …」带标签排版一起带过去
            // (James 决策);无原文(如纯问答)退化为只插结果文本。
            iconButton("text.append", "note.insert_result") {
                noteDocs.selected?.editor.insert(
                    Self.noteSnippet(source: sourceText, result: text),
                    sourceResultID: resultID)
            }
            .font(.subheadline)
            .disabled(text.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty)
            // 朗读结果文本（TTS 文本框已移除，直接传结果）。
            iconButton("speaker.wave.2", "tts.speak_result") {
                controller.ttsViewModel.synthesizeAndPlay(text: text)
            }
            .font(.subheadline)
            .disabled(text.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// 组装插入草稿的片段：有原文则「**原文:** … / 空行 / **译文:** …」
    /// 带标签排版（James 决策），原文为空/纯空白（如纯问答无 sourceText）
    /// 退化为只给结果文本。纯函数便于单测断言形状。
    nonisolated static func noteSnippet(source: String?,
                                        result: String) -> String {
        let src = source?.trimmingCharacters(
            in: .whitespacesAndNewlines) ?? ""
        guard !src.isEmpty else { return result }
        return "**原文:** \(src)\n\n**译文:** \(result)"
    }

    // MARK: - 历史卡

    @ViewBuilder
    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.fill").foregroundStyle(.tint)
                Text("history.show").font(.subheadline.weight(.semibold))
                Spacer()
            }
            if let cat = viewModel.historyError {
                Label {
                    Text(Self.messageKey(for: cat))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else if viewModel.history.isEmpty {
                cardHint("history.empty")
            } else {
                ForEach(viewModel.history, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.provider)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if item.error != nil {
                                Text("history.failed_tag")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text(item.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(resultText(item).isEmpty
                             ? "—" : resultText(item))
                            .font(.body)
                            .textSelection(.enabled)
                            .lineLimit(4)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - 复用零件

    /// 统一工具图标：细线性（调用处传无 .fill 名）、同字号同字重、
    /// 同暖灰调（James 决策：一排图标视觉一致，不混填充/描边）。
    private func iconButton(_ systemName: String,
                            _ helpKey: LocalizedStringKey,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(ClaudeTheme.primaryText)
        }
        .buttonStyle(.plain)
        // .help 在 .plain 按钮上不稳，叠一层原生 tooltip 兜底
        // （两者并存无害，谁先触发都给提示）。
        .help(helpKey)
        .nativeTooltip(Self.localized(helpKey))
    }

    /// LocalizedStringKey → 已本地化字符串（喂给 AppKit toolTip）。
    /// 这些键都是无参短语，直接按当前语言查表。
    private static func localized(_ key: LocalizedStringKey) -> String {
        // LocalizedStringKey 无公开取 key 的 API，但工程里这些键与
        // 其字符串值一一对应，String(localized:) 用 key 文本即可命中。
        let mirror = Mirror(reflecting: key)
        if let k = mirror.children.first(where: { $0.label == "key" })?
            .value as? String {
            return String(localized: String.LocalizationValue(k))
        }
        return ""
    }

    private func cardHint(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func permissionBanner(_ category: AgentError.Category) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(category == .permission
                     ? "permission.guide"
                     : Self.messageKey(for: category))
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
            }
            if category == .permission {
                Button("permission.open_settings") {
                    controller.openPrivacySettings()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func resultText(_ model: ResultModel) -> String {
        if case let .text(value) = model.content { return value }
        if case let .translation(t, _, _) = model.content { return t }
        if case let .dictionary(entry) = model.content {
            // 历史/笔记预览用：词头 — 中译聚合(无释义则只词头)。
            if let s = entry.summary, !s.isEmpty {
                return "\(entry.headword) — \(s)"
            }
            return entry.headword
        }
        return ""
    }

    /// category → 本地化键。UI 不拼接 provider 私有错误。
    private static func messageKey(for category: AgentError.Category) -> LocalizedStringKey {
        switch category {
        case .invalidInput:     return "error.invalid_input"
        case .network:          return "error.network"
        case .timeout:          return "error.timeout"
        case .cancelled:        return "error.cancelled"
        case .permission:       return "error.permission"
        case .persistence:      return "error.persistence"
        case .providerRejected: return "error.provider_rejected"
        case .unknown:          return "error.unknown"
        }
    }
}

