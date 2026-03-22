//
//  VocabularyView.swift
//  Talk
//
//  词库管理视图
//

import SwiftUI
import UniformTypeIdentifiers

struct VocabularyView: View {
    @State private var vocabularyManager = VocabularyManager.shared
    @State private var searchText = ""
    @State private var newWord = ""
    @State private var newCorrectedForm = ""
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    private var filteredItems: [VocabularyItem] {
        if searchText.isEmpty {
            return vocabularyManager.items
        }
        return vocabularyManager.search(query: searchText)
    }

    private var correctionItems: [VocabularyItem] {
        filteredItems.filter { $0.isCorrection }
    }

    private var regularItems: [VocabularyItem] {
        filteredItems.filter { !$0.isCorrection }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                addEntryForm
                searchBar

                if filteredItems.isEmpty {
                    emptyView
                } else {
                    vocabularyList
                }
            }
            .navigationTitle("词库管理")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button(action: importVocabulary) {
                            Label("导入", systemImage: "square.and.arrow.down")
                        }
                        Button(action: exportVocabulary) {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Add Entry Form

    private var addEntryForm: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("原词/错误写法", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                TextField("正确写法（选填）", text: $newCorrectedForm)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    addEntry()
                }
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索词库...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
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

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("词库为空")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("可以手动添加词汇，也会从编辑历史记录中自动学习")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Vocabulary List

    private var vocabularyList: some View {
        List {
            if !correctionItems.isEmpty {
                Section("纠正词库") {
                    ForEach(correctionItems) { item in
                        VocabularyRow(item: item, onDelete: { deleteItem(item) })
                    }
                }
            }
            if !regularItems.isEmpty {
                Section("常用词汇") {
                    ForEach(regularItems) { item in
                        VocabularyRow(item: item, onDelete: { deleteItem(item) })
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    private func addEntry() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        let corrected = newCorrectedForm.trimmingCharacters(in: .whitespaces)

        guard !word.isEmpty else { return }

        if corrected.isEmpty {
            // Regular vocabulary word
            if vocabularyManager.contains(word) {
                errorMessage = "词汇「\(word)」已存在"
                return
            }
            vocabularyManager.add(word: word)
        } else {
            if word == corrected {
                errorMessage = "原词和正确写法不能相同"
                return
            }
            vocabularyManager.addCorrection(original: word, corrected: corrected)
        }

        newWord = ""
        newCorrectedForm = ""
        errorMessage = nil
    }

    private func deleteItem(_ item: VocabularyItem) {
        vocabularyManager.delete(item)
    }

    private func exportVocabulary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vocabulary_\(Int(Date().timeIntervalSince1970)).json"
        panel.allowedContentTypes = [UTType(filenameExtension: "json")!]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try vocabularyManager.export(to: url)
            } catch {
                AppLogger.error("导出词库失败: \(error.localizedDescription)", category: .storage)
            }
        }
    }

    private func importVocabulary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "json")!]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try vocabularyManager.import(from: url)
            } catch {
                AppLogger.error("导入词库失败: \(error.localizedDescription)", category: .storage)
            }
        }
    }
}

// MARK: - Vocabulary Row

private struct VocabularyRow: View {
    let item: VocabularyItem
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if item.isCorrection, let corrected = item.correctedForm {
                    HStack(spacing: 4) {
                        Text(item.word)
                            .foregroundColor(.primary)
                        Text("\u{2192}")
                            .foregroundColor(.secondary)
                        Text(corrected)
                            .foregroundColor(.green)
                    }
                    .font(.body)
                } else {
                    Text(item.word)
                        .font(.body)
                }

                HStack(spacing: 12) {
                    Text("频率: \(item.frequency)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("最近使用: \(item.formattedLastUsed)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
