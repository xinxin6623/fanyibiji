import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 右侧笔记编辑区（Codex App 风格分栏右栏）。
///
///  - 顶栏：标题 + 编辑/预览分段切换 + 保存状态 + 手动保存按钮
///  - 编辑态：纯文本 `TextEditor` 改 Markdown 源码
///  - 预览态：SwiftUI 原生 Markdown 渲染（`AttributedString(markdown:)`）
///
/// 翻译结果只读、随采集更新；这里是独立草稿，「插入到编辑区」由左侧
/// 结果卡调 `viewModel.insert(_:)` 写入（追加到尾部并补空行）。
struct NoteEditorView: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeTheme.separator.frame(height: 1)
            Group {
                switch viewModel.mode {
                case .edit:
                    TextEditor(text: $viewModel.text)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .padding(8)
                case .preview:
                    // WKWebView + 离线 marked/highlight.js,全语法一致
                    // (代码块/表格/嵌套/ASCII 图保留对齐)。
                    MarkdownWebView(markdown: viewModel.text)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ClaudeTheme.background)
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(ClaudeTheme.accent)
            Text("note.title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ClaudeTheme.secondaryText)

            // 撤销 / 重做：按钮 + ⌘Z / ⌘⇧Z。程序化插入(插译文/划词进
            // 草稿)与手敲都走 ViewModel 自建快照栈,故这对按钮对两者
            // 都生效(系统 TextEditor 内建 undo 退不掉程序化写入)。
            // 紧挨标题靠左放(James 指定)。
            HStack(spacing: 2) {
                Button {
                    viewModel.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canUndo)
                .help("note.undo")
                .nativeTooltip(String(localized: "note.undo"))
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    viewModel.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canRedo)
                .help("note.redo")
                .nativeTooltip(String(localized: "note.redo"))
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .font(.subheadline)

            Spacer()

            // 轻量文字分段：选中项赤陶橙加粗、其余灰，无填充块，
            // 与整体扁平风一致（James 决策，替代橙色 segmented）。
            HStack(spacing: 14) {
                modeTextButton("note.mode.edit", .edit)
                modeTextButton("note.mode.preview", .preview)
            }
            .fixedSize()

            saveStatusLabel

            Button {
                exportNote()
            } label: {
                Label("note.export", systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(ClaudeTheme.accent)
            .help("note.export.help")
            .disabled(viewModel.text.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 编辑/预览文字分段项：选中赤陶橙加粗，未选灰常规。
    private func modeTextButton(_ key: LocalizedStringKey,
                                _ mode: NoteEditorViewModel.Mode) -> some View {
        let selected = viewModel.mode == mode
        return Button {
            viewModel.mode = mode
        } label: {
            Text(key)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? ClaudeTheme.accent
                                          : ClaudeTheme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        switch viewModel.saveStatus {
        // 自动保存相关态(clean/dirty/saving/saved)一律不显示——James
        // 指定去掉「已保存 HH:mm」这类自动保存图示,草稿本就防抖兜底。
        // 仅保留「另存导出」结果(用户主动操作,需可见反馈)。
        case .clean, .dirty, .saving, .saved:
            EmptyView()
        case let .exported(url):
            Label {
                Text("\(Text("note.status.exported")) \(url.lastPathComponent)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help(url.path)
        case .exportFailed:
            Label("note.status.export_failed",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .failed:
            Label("note.status.failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - 导出（另存为）

    /// 弹 macOS 系统另存对话框，让用户自选目录/文件名导出 .md。
    /// 内部草稿的防抖自动保存照旧（防丢），本操作只负责“导出到用户
    /// 选的位置”。NSSavePanel 属 AppKit，必须主线程；写文件失败回写
    /// `saveStatus = .failed` 让顶栏可见。
    private func exportNote() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let stamp = Self.fileStampFormatter.string(from: Date())
        panel.nameFieldStringValue = "note-\(stamp).md"
        panel.message = String(localized: "note.export.help")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.text.data(using: .utf8)?
                .write(to: url, options: .atomic)
            viewModel.markExported(to: url)
        } catch {
            viewModel.markExportFailed()
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

}
