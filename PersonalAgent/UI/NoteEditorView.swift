import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 右侧笔记编辑区（行内实时渲染版）。
///
///  - 顶栏：标题图标 + 撤销/重做 + 导出按钮（不再有「编辑/预览」分段）
///  - 主体：`MarkdownInlineEditorView`（WKWebView 内 TOAST UI Editor，
///    WYSIWYG 模式，所见即所得；ViewModel.text 仍是真理源）
///  - 翻译结果只读、随采集更新；这里是独立草稿，「插入到编辑区」由左侧
///    结果卡调 `viewModel.insert(_:)`，ViewModel 走 inline editor 的
///    insertAtCursor API 在光标处插入（不再追加到尾部）。
struct NoteEditorView: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeTheme.separator.frame(height: 1)
            MarkdownInlineEditorView(
                text: $viewModel.text,
                onReady: {},
                onCoordinatorReady: { coord in
                    viewModel.attachEditorCoordinator(coord)
                })
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

            // 撤销/重做：UI 按钮明确走 ViewModel 的整段快照栈（覆盖程序化
            // insert 与手敲两类），inline editor 内 TOAST 自带 undo 仍响应
            // ⌘Z 处理 WYSIWYG 内编辑动作。两套并存：⌘Z 默认走系统编辑器，
            // 按钮明确走 ViewModel。
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

                Button {
                    viewModel.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canRedo)
                .help("note.redo")
                .nativeTooltip(String(localized: "note.redo"))
            }
            .font(.subheadline)

            Spacer()

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

    @ViewBuilder
    private var saveStatusLabel: some View {
        switch viewModel.saveStatus {
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
