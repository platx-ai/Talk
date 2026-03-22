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

    /// Learn from user correction: original (ASR/LLM output) -> corrected (user edit)
    func learnCorrection(original: String, corrected: String) {
        guard original != corrected else { return }

        let originalWords = tokenize(original)
        let correctedWords = tokenize(corrected)

        // Simple word-level diff: compare aligned words
        let maxLen = max(originalWords.count, correctedWords.count)
        guard maxLen > 0 else { return }

        // Use a simple LCS-based approach to find changed segments
        let pairs = diffWords(old: originalWords, new: correctedWords)

        for (oldWord, newWord) in pairs {
            guard oldWord != newWord else { continue }
            guard !oldWord.isEmpty, !newWord.isEmpty else { continue }

            if let index = items.firstIndex(where: { $0.word == oldWord && $0.correctedForm == newWord }) {
                // Already have this correction, boost frequency
                items[index].frequency += 3
                items[index].lastUsed = Date()
            } else if let index = items.firstIndex(where: { $0.word == oldWord && $0.correctedForm != nil }) {
                // Same original word but different correction — update
                items[index].correctedForm = newWord
                items[index].frequency += 3
                items[index].lastUsed = Date()
            } else {
                // New correction entry with high initial frequency
                let item = VocabularyItem(
                    word: oldWord,
                    frequency: minFrequencyThreshold + 1,
                    correctedForm: newWord
                )
                items.append(item)
            }
        }

        saveVocabulary()
        AppLogger.info("从修正中学习了 \(pairs.filter { $0.0 != $0.1 }.count) 个纠正", category: .storage)
    }

    /// Get high-frequency correction items for LLM context
    func getHighFrequencyItems(limit: Int = 20) -> [VocabularyItem] {
        items
            .filter { $0.isCorrection && $0.frequency >= minFrequencyThreshold }
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { $0 }
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: " \n\r\t.,;:!?，。；：！？、"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Simple word-level diff that pairs up changed words between old and new
    private func diffWords(old: [String], new: [String]) -> [(String, String)] {
        // Build LCS table
        let m = old.count, n = new.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find matched (same) and changed pairs
        var pairs: [(String, String)] = []
        var i = m, j = n
        // Collect deletions and insertions between LCS matches
        var deletions: [String] = []
        var insertions: [String] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && old[i - 1] == new[j - 1] {
                // Flush accumulated changes as paired corrections
                flushChanges(deletions: &deletions, insertions: &insertions, into: &pairs)
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                insertions.append(new[j - 1])
                j -= 1
            } else {
                deletions.append(old[i - 1])
                i -= 1
            }
        }
        flushChanges(deletions: &deletions, insertions: &insertions, into: &pairs)

        return pairs
    }

    private func flushChanges(deletions: inout [String], insertions: inout [String], into pairs: inout [(String, String)]) {
        // Reverse because we collected them backwards
        deletions.reverse()
        insertions.reverse()

        if !deletions.isEmpty && !insertions.isEmpty {
            // Pair them up: join as phrase if counts differ
            let oldPhrase = deletions.joined(separator: " ")
            let newPhrase = insertions.joined(separator: " ")
            pairs.append((oldPhrase, newPhrase))
        }
        // If only deletions or only insertions, skip (not a correction, just added/removed text)

        deletions.removeAll()
        insertions.removeAll()
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

    /// Manually add a correction entry (original -> corrected)
    func addCorrection(original: String, corrected: String) {
        guard !original.isEmpty, !corrected.isEmpty, original != corrected else { return }
        if let index = items.firstIndex(where: { $0.word == original && $0.correctedForm == corrected }) {
            items[index].frequency += 1
            items[index].lastUsed = Date()
        } else {
            let item = VocabularyItem(word: original, frequency: minFrequencyThreshold + 1, correctedForm: corrected)
            items.append(item)
        }
        saveVocabulary()
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
