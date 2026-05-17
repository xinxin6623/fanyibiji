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
            Divider()
            Group {
                switch viewModel.mode {
                case .edit:
                    TextEditor(text: $viewModel.text)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .padding(8)
                case .preview:
                    ScrollView {
                        markdownPreview
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.tint)
            Text("note.title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $viewModel.mode) {
                Text("note.mode.edit").tag(NoteEditorViewModel.Mode.edit)
                Text("note.mode.preview").tag(NoteEditorViewModel.Mode.preview)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
            .tint(.accentColor)
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
        case .clean:
            EmptyView()
        case .dirty:
            Text("note.status.unsaved")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .saving:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("note.status.saving")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        case let .saved(date):
            Text("\(Text("note.status.saved")) \(date, style: .time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    // MARK: - Markdown 预览

    /// SwiftUI 原生 Markdown：按行解析，空行成段。`AttributedString` 的
    /// 单串 `.full` 解析会吃掉换行，逐行渲染才能保留 Markdown 块结构。
    private var markdownPreview: some View {
        let lines = viewModel.text.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 6) {
            if viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("note.preview.empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        Spacer().frame(height: 6)
                    } else {
                        Text(Self.attributed(from: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// 单行 → Markdown 行内 `AttributedString`，解析失败退化为纯文本
    /// （绝不因渲染异常丢内容）。
    private static func attributed(from line: String) -> AttributedString {
        (try? AttributedString(
            markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(line)
    }
}
