//
//  HistoryView.swift
//  Talk
//
//  历史记录视图
//

import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @State private var searchText = ""
    @State private var selectedItem: HistoryItem?
    @State private var historyManager = HistoryManager.shared

    private var filteredItems: [HistoryItem] {
        let items = searchText.isEmpty ? historyManager.items : historyManager.search(query: searchText)
        let today = items.filter { $0.isToday }
        let yesterday = items.filter { $0.isYesterday }
        let older = items.filter { !$0.isToday && !$0.isYesterday }
        return today + yesterday + older
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)

                if filteredItems.isEmpty {
                    emptyView
                } else {
                    historyList
                }
            }
            .navigationTitle(String(localized: "历史记录"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: exportHistory) {
                        Label(String(localized: "导出"), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                HistoryEditSheet(item: item)
            }
        }
        .frame(width: 700, height: 500)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(String(localized: "暂无历史记录"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "开始录音后，识别结果会显示在这里"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var historyList: some View {
        List {
            ForEach(groupedItems.keys.sorted(by: >), id: \.self) { date in
                Section(header: Text(dateFormatter.string(from: date))) {
                    ForEach(groupedItems[date] ?? []) { item in
                        HistoryRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var groupedItems: [Date: [HistoryItem]] {
        Dictionary(grouping: filteredItems) { item in
            Calendar.current.startOfDay(for: item.timestamp)
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "talk_history_\(Date().timeIntervalSince1970).json"
        panel.allowedContentTypes = [UTType(filenameExtension: "json")!]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try historyManager.export(to: url)
            } catch {
                AppLogger.error("导出历史记录失败: \(error.localizedDescription)", category: .ui)
            }
        }
    }
}

// MARK: - 搜索栏

private struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "搜索历史记录..."), text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - 历史记录行（和之前一样的列表样式）

private struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.polishedText)
                    .font(.body)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    Text("ASR: \(modelShortName(item.asrModel))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("LLM: \(modelShortName(item.llmModel))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func modelShortName(_ modelId: String) -> String {
        if modelId.contains("Qwen3-4B") { return "Qwen3-4B" }
        if modelId.contains("Qwen3.5-2B") {return "Qwen3.5-2B"}
        if modelId.contains("Qwen3-2B") { return "Qwen3-2B" }
        if modelId.contains("ASR-0.6B") { return "Qwen3-ASR" }
        return modelId
    }
}

// MARK: - 编辑 Sheet（用 NSTextView 包装解决 sheet 内 TextEditor 不可编辑的问题）

struct HistoryEditSheet: View {
    let item: HistoryItem

    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String = ""
    @State private var displayText: String = ""  // 当前显示的文本（保存后立即更新）
    @State private var isEditing = false
    @State private var showLearnConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text(String(localized: "历史详情")).font(.headline)
                Spacer()
                if showLearnConfirmation {
                    Label(String(localized: "已学习修正"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Button(String(localized: "关闭")) { dismiss() }
            }

            // 基本信息
            GroupBox(String(localized: "基本信息")) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text(String(localized: "录音时间")).foregroundStyle(.secondary)
                        Text(item.formattedTimestamp)
                    }
                    GridRow {
                        Text(String(localized: "录音时长")).foregroundStyle(.secondary)
                        Text(item.formattedDuration)
                    }
                }
                .font(.body)
                .padding(.vertical, 4)
            }

            // 原始识别
            GroupBox(String(localized: "原始识别文本")) {
                Text(item.rawText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }

            // 润色后文本（可编辑）
            GroupBox(isEditing ? String(localized: "编辑润色文本") : String(localized: "润色后文本")) {
                if isEditing {
                    EditableTextView(text: $editedText)
                        .frame(minHeight: 80)
                } else {
                    Text(displayText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
            }

            // 操作按钮
            HStack(spacing: 12) {
                Button(action: copyText) {
                    Label(String(localized: "复制"), systemImage: "doc.on.doc")
                }

                if isEditing {
                    Button(action: saveEdit) {
                        Label(String(localized: "保存修正"), systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(String(localized: "取消")) {
                        isEditing = false
                        editedText = displayText
                    }
                } else {
                    Button(action: {
                        editedText = displayText
                        isEditing = true
                    }) {
                        Label(String(localized: "编辑"), systemImage: "pencil")
                    }
                }

                Spacer()

                Button(role: .destructive, action: deleteItem) {
                    Label(String(localized: "删除"), systemImage: "trash")
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 480)
        .onAppear {
            displayText = item.polishedText
            editedText = item.polishedText
        }
    }

    private func saveEdit() {
        let originalText = displayText
        let correctedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard correctedText != originalText, !correctedText.isEmpty else {
            isEditing = false
            return
        }

        var updatedItem = item
        updatedItem.polishedText = correctedText
        HistoryManager.shared.update(updatedItem)
        VocabularyManager.shared.learnCorrection(original: originalText, corrected: correctedText)

        // 立即更新显示
        displayText = correctedText
        isEditing = false

        withAnimation { showLearnConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showLearnConfirmation = false }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayText, forType: .string)
    }

    private func deleteItem() {
        HistoryManager.shared.delete(item)
        dismiss()
    }
}

// MARK: - NSTextView 包装（解决 SwiftUI TextEditor 在 sheet 中不可编辑的问题）

struct EditableTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableTextView
        init(_ parent: EditableTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
