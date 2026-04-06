//
//  HistoryView.swift
//  Talk
//
//  历史记录视图 — inline 编辑 + 播放 + 词库学习
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct HistoryView: View {
    @State private var searchText = ""
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
        }
        .frame(width: 750, height: 550)
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
                        InlineHistoryRow(item: item)
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

// MARK: - Inline 编辑行

private struct InlineHistoryRow: View {
    let item: HistoryItem

    @State private var editedText: String = ""
    @State private var isEditing = false
    @State private var showLearnConfirmation = false
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?

    /// 文本是否被修改过（相对于原始 polishedText）
    private var hasChanges: Bool {
        isEditing && editedText.trimmingCharacters(in: .whitespacesAndNewlines) != item.polishedText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶部：时间 + 时长 + 模型
            HStack(spacing: 8) {
                Text(item.formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(.quaternary))

                if showLearnConfirmation {
                    Label(String(localized: "已学习"), systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                Spacer()

                // 右侧按钮组
                actionButtons
            }

            // 主体：inline 可编辑文本
            if isEditing {
                TextField("", text: $editedText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...10)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(.blue.opacity(0.5)))
                    .onSubmit { saveIfChanged() }
            } else {
                Text(item.polishedText)
                    .font(.body)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editedText = item.polishedText
                        isEditing = true
                    }
            }

            // 原始 ASR 文本（折叠显示，如果与润色不同）
            if item.rawText != item.polishedText && !item.rawText.isEmpty {
                Text("ASR: \(item.rawText)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 右侧按钮

    private var actionButtons: some View {
        HStack(spacing: 4) {
            // 播放音频
            if item.audioFilePath != nil, HistoryManager.shared.audioURL(for: item) != nil {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isPlaying ? .red : .blue)
                }
                .buttonStyle(.plain)
                .help(String(localized: "播放录音"))
            }

            // Reset（编辑中才显示）
            if isEditing {
                Button(action: resetEdit) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(String(localized: "还原"))
            }

            // 保存 + 加入词库（有修改才亮起）
            if hasChanges {
                Button(action: saveAndLearn) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help(String(localized: "保存并学习"))
            }

            // 删除
            Button(action: deleteItem) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "删除"))
        }
    }

    // MARK: - Actions

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
            return
        }

        guard let url = HistoryManager.shared.audioURL(for: item) else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true

            // 播放结束后重置状态
            let duration = audioPlayer?.duration ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                isPlaying = false
            }
        } catch {
            AppLogger.error("播放音频失败: \(error.localizedDescription)", category: .ui)
        }
    }

    private func resetEdit() {
        editedText = item.polishedText
        isEditing = false
    }

    private func saveIfChanged() {
        if hasChanges {
            saveAndLearn()
        } else {
            isEditing = false
        }
    }

    private func saveAndLearn() {
        let originalText = item.polishedText
        let correctedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard correctedText != originalText, !correctedText.isEmpty else {
            isEditing = false
            return
        }

        var updatedItem = item
        updatedItem.polishedText = correctedText
        HistoryManager.shared.update(updatedItem)
        VocabularyManager.shared.learnCorrection(original: originalText, corrected: correctedText)

        isEditing = false

        withAnimation { showLearnConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showLearnConfirmation = false }
        }
    }

    private func deleteItem() {
        HistoryManager.shared.delete(item)
    }
}
