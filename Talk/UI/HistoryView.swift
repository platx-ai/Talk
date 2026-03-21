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
            .navigationTitle("历史记录")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: exportHistory) {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {}) {
                        Text("关闭")
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                HistoryDetailView(item: item)
            }
        }
        .frame(width: 700, height: 500)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("暂无历史记录")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("开始录音后，识别结果会显示在这里")
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
                AppLogger.info("导出历史记录成功", category: .ui)
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
            TextField("搜索历史记录...", text: $text)
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

// MARK: - 历史记录行

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

            Button(action: {}) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func modelShortName(_ modelId: String) -> String {
        if modelId.contains("Qwen3-4B") { return "Qwen3-4B" }
        if modelId.contains("Qwen3-2B") { return "Qwen3-2B" }
        if modelId.contains("ASR-0.6B") { return "Qwen3-ASR" }
        return modelId
    }
}

// MARK: - 历史记录详情

private struct HistoryDetailView: View {
    let item: HistoryItem

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var editedPolishedText = ""
    @State private var showLearnConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("历史详情").font(.headline)
                Spacer()
                if showLearnConfirmation {
                    Text("已学习修正")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }

            infoSection("基本信息") {
                infoRow("录音时间", item.formattedTimestamp)
                infoRow("录音时长", item.formattedDuration)
                infoRow("ASR 模型", modelShortName(item.asrModel))
                infoRow("LLM 模型", modelShortName(item.llmModel))
            }

            textSection("原始识别文本", text: item.rawText, isEditable: false)
            polishedTextSection

            HStack(spacing: 12) {
                Button(action: copyText) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .controlSize(.large)

                if isEditing {
                    Button(action: saveEdit) {
                        Label("保存", systemImage: "checkmark")
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Button(action: cancelEdit) {
                        Label("取消", systemImage: "xmark")
                    }
                    .controlSize(.large)
                } else {
                    Button(action: startEditing) {
                        Label("编辑", systemImage: "pencil")
                    }
                    .controlSize(.large)
                }

                Spacer()

                Button(action: deleteItem) {
                    Label("删除", systemImage: "trash")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding(20)
        .frame(width: 600, height: 500)
        .onAppear {
            editedPolishedText = item.polishedText
        }
    }

    private var polishedTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("润色后文本").font(.caption).foregroundStyle(.secondary)
            if isEditing {
                TextEditor(text: $editedPolishedText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            } else {
                Text(item.polishedText)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }

    private func infoSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value).font(.body)
            Spacer()
        }
    }

    private func textSection(_ title: String, text: String, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
        }
    }

    private func startEditing() {
        editedPolishedText = item.polishedText
        isEditing = true
    }

    private func cancelEdit() {
        editedPolishedText = item.polishedText
        isEditing = false
    }

    private func saveEdit() {
        let originalText = item.polishedText
        let correctedText = editedPolishedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard correctedText != originalText, !correctedText.isEmpty else {
            isEditing = false
            return
        }

        // Update the history item
        var updatedItem = item
        updatedItem.polishedText = correctedText
        HistoryManager.shared.update(updatedItem)

        // Learn from correction
        VocabularyManager.shared.learnCorrection(original: originalText, corrected: correctedText)

        isEditing = false

        // Show confirmation
        withAnimation {
            showLearnConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showLearnConfirmation = false
            }
        }

        AppLogger.info("用户修正了润色文本并已学习", category: .ui)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.polishedText, forType: .string)
        AppLogger.info("复制历史记录到剪贴板", category: .ui)
    }

    private func deleteItem() {
        HistoryManager.shared.delete(item)
        dismiss()
        AppLogger.info("删除历史记录", category: .ui)
    }

    private func modelShortName(_ modelId: String) -> String {
        if modelId.contains("Qwen3-4B") { return "Qwen3-4B" }
        if modelId.contains("Qwen3-2B") { return "Qwen3-2B" }
        if modelId.contains("ASR-0.6B") { return "Qwen3-ASR" }
        return modelId
    }
}
