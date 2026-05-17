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

    /// 左栏宽度（可拖动分隔条调整）。范围夹在 [minPane, total-minPane]。
    @State private var leftPaneWidth: CGFloat = 360
    private let minPaneWidth: CGFloat = 280
    private let dividerWidth: CGFloat = 8

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
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingHotkeySettings) {
            HotkeySettingsView(config: controller.hotkeyConfig,
                               promptConfig: controller.promptConfig)
                .environmentObject(controller)
        }
    }

    // MARK: - 左栏（原查询/结果/历史）

    private var leftPane: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    if let category = controller.captureFailure {
                        permissionBanner(category)
                    }
                    queryCard
                    languageBar
                    Group {
                        if showingHistory { historyCard } else { resultCard }
                    }
                    // 空闲不渲染;合成中/可播放/失败时自带卡片显示。
                    TTSPanelView(viewModel: controller.ttsViewModel)
                }
                .padding(16)
            }
        }
    }

    // MARK: - 可拖动分隔条

    private func clampedLeftWidth(total: CGFloat) -> CGFloat {
        let maxLeft = max(minPaneWidth, total - minPaneWidth - dividerWidth)
        return min(max(leftPaneWidth, minPaneWidth), maxLeft)
    }

    private func splitDivider(total: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: dividerWidth)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
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

    private var toolbar: some View {
        HStack(spacing: 14) {
            Image(systemName: "character.bubble")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("app.title")
                .font(.headline)
            Spacer()
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

            Button {
                showingHotkeySettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("settings.hotkey.title")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 查询卡

    private var queryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)

            Divider()

            HStack(spacing: 16) {
                iconButton("paperplane.fill", "query.run") {
                    viewModel.dispatch { await viewModel.runQuery() }
                }
                .disabled(isLoading)

                iconButton("camera.viewfinder", "capture.run") {
                    controller.triggerCapture()
                }
                .disabled(isLoading)

                iconButton("doc.on.clipboard", "clipboard.translate") {
                    viewModel.dispatch {
                        await viewModel.translateFromClipboard()
                    }
                }
                .disabled(isLoading)

                iconButton("brain", "clipboard.query") {
                    viewModel.dispatch { await viewModel.queryFromClipboard() }
                }
                .disabled(isLoading)

                // 朗读输入框文本（TTS 文本框已移除，直接传文本）。
                iconButton("speaker.wave.2", "tts.speak_input") {
                    controller.ttsViewModel.synthesizeAndPlay(
                        text: viewModel.inputText)
                }
                .disabled(viewModel.inputText.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty)

                Spacer()

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
            }
            .font(.title3)
        }
        .card()
    }

    // MARK: - 语言方向条

    private var languageBar: some View {
        HStack {
            // 源语言固定自动检测（provider 已 sl=auto），只读展示。
            Label("lang.auto_detect", systemImage: "globe")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Spacer()

            // 目标语言可选 → 改 viewModel.targetLanguage（didSet 落盘）。
            Picker(selection: $viewModel.targetLanguage) {
                ForEach(TargetLanguage.allCases, id: \.self) { lang in
                    Text(verbatim: "\(lang.flag) ")
                        + Text(LocalizedStringKey(lang.displayNameKey))
                }
            } label: { EmptyView() }
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                resultHeader(text: resultText(model), resultID: model.id)
                Text(resultText(model))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case let .failure(category):
                Label {
                    Text(Self.messageKey(for: category))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if viewModel.canRetry {
                    Button("query.retry") {
                        viewModel.dispatch { await viewModel.retryLast() }
                    }
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
        .background(Color(nsColor: .controlBackgroundColor))
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

    private func resultHeader(text: String, resultID: UUID? = nil) -> some View {
        HStack {
            Image(systemName: "text.bubble.fill")
                .foregroundStyle(.tint)
            Text("result.title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            // 插入当前译文到右侧**选中 Tab** 的笔记草稿;同时登记来源
            // result id(原料包 A 源追)。无选中 Tab 时按钮禁用。
            iconButton("text.insert", "note.insert_result") {
                noteDocs.selected?.editor.insert(
                    text, sourceResultID: resultID)
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
        .card()
    }

    // MARK: - 复用零件

    private func iconButton(_ systemName: String,
                            _ helpKey: LocalizedStringKey,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
        .help(helpKey)
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

/// 统一卡片容器修饰：圆角 + 背景 + 内边距，对齐 Easydict 卡片观感。
private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func card() -> some View { modifier(CardModifier()) }
}
