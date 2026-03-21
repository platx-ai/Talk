//
//  VocabularyManager.swift
//  Talk
//
//  个人词库管理器
//

import Foundation

@Observable
@MainActor
final class VocabularyManager {
    @MainActor static let shared = VocabularyManager()

    private(set) var items: [VocabularyItem] = []
    private let vocabularyFilePath: URL
    private let minFrequencyThreshold = 3

    private init() {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let localTypeURL = appSupportURL.appendingPathComponent("Talk", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: localTypeURL,
            withIntermediateDirectories: true
        )

        vocabularyFilePath = localTypeURL.appendingPathComponent("vocabulary.json")
        loadVocabulary()
    }

    private func loadVocabulary() {
        guard FileManager.default.fileExists(atPath: vocabularyFilePath.path) else { return }

        do {
            let data = try Data(contentsOf: vocabularyFilePath)
            items = try JSONDecoder().decode([VocabularyItem].self, from: data)
            AppLogger.info("加载了 \(items.count) 个词汇", category: .storage)
        } catch {
            AppLogger.error("加载词库失败: \(error.localizedDescription)", category: .storage)
            items = []
        }
    }

    private func saveVocabulary() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: vocabularyFilePath)
        } catch {
            AppLogger.error("保存词库失败: \(error.localizedDescription)", category: .storage)
        }
    }

    func learn(from text: String) {
        let words = text.components(separatedBy: CharacterSet(charactersIn: " \n\r\t.,;:!?，。；：！？、"))
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }

        for word in words {
            if let index = items.firstIndex(where: { $0.word == word }) {
                items[index].frequency += 1
                items[index].lastUsed = Date()
            } else {
                let newItem = VocabularyItem(
                    word: word,
                    frequency: 1,
                    context: extractContext(from: text, for: word)
                )
                items.append(newItem)
            }
        }

        saveVocabulary()
    }

    private func extractContext(from text: String, for word: String) -> String? {
        guard let range = text.range(of: word) else { return nil }

        let maxLength = 20
        let startIndex = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - maxLength)
        let endIndex = min(text.count, text.distance(from: text.startIndex, to: range.upperBound) + maxLength)

        let contextIndex = text.index(text.startIndex, offsetBy: startIndex)
        let contextEndIndex = text.index(contextIndex, offsetBy: endIndex - startIndex)
        let safeEndIndex = min(contextEndIndex, text.endIndex)

        return String(text[contextIndex..<safeEndIndex])
    }

    func getHighFrequencyWords(limit: Int = 100) -> [VocabularyItem] {
        items
            .filter { $0.frequency >= minFrequencyThreshold }
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { $0 }
    }

    func search(query: String) -> [VocabularyItem] {
        guard !query.isEmpty else { return getHighFrequencyWords() }
        return items.filter { item in
            item.word.localizedCaseInsensitiveContains(query) ||
            (item.context?.localizedCaseInsensitiveContains(query) ?? false)
        }
        .sorted { $0.frequency > $1.frequency }
    }

    func contains(_ word: String) -> Bool {
        items.contains { $0.word == word }
    }

    func add(word: String, context: String? = nil) {
        if !contains(word) {
            let item = VocabularyItem(word: word, frequency: 1, context: context)
            items.append(item)
            saveVocabulary()
            AppLogger.info("添加词汇: \(word)", category: .storage)
        }
    }

    func delete(_ item: VocabularyItem) {
        items.removeAll { $0.id == item.id }
        saveVocabulary()
        AppLogger.info("删除词汇: \(item.word)", category: .storage)
    }

    func clearAll() {
        items = []
        saveVocabulary()
        AppLogger.info("已清空词库", category: .storage)
    }

    func export(to url: URL) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: url)
        AppLogger.info("已导出 \(items.count) 个词汇到 \(url.path)", category: .storage)
    }

    func `import`(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let importedItems = try JSONDecoder().decode([VocabularyItem].self, from: data)

        for item in importedItems {
            if let index = items.firstIndex(where: { $0.word == item.word }) {
                items[index].frequency += item.frequency
                items[index].lastUsed = max(items[index].lastUsed, item.lastUsed)
            } else {
                items.append(item)
            }
        }

        saveVocabulary()
        AppLogger.info("已导入 \(importedItems.count) 个词汇", category: .storage)
    }
}
