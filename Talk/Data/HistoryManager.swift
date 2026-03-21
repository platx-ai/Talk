//
//  HistoryManager.swift
//  Talk
//
//  历史记录管理器
//

import Foundation

@Observable
@MainActor
final class HistoryManager {
    @MainActor static let shared = HistoryManager()

    private(set) var items: [HistoryItem] = []
    private let historyFilePath: URL
    var retentionDays: Int = 0

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

        historyFilePath = localTypeURL.appendingPathComponent("history.json")
        loadHistory()
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFilePath.path) else { return }

        do {
            let data = try Data(contentsOf: historyFilePath)
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
            AppLogger.info("加载了 \(items.count) 条历史记录")
        } catch {
            AppLogger.error("加载历史记录失败: \(error.localizedDescription)")
            items = []
        }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: historyFilePath)
        } catch {
            AppLogger.error("保存历史记录失败: \(error.localizedDescription)")
        }
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        cleanOldHistory()
        saveHistory()
    }

    private func cleanOldHistory() {
        guard retentionDays > 0 else { return }

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date()
        )!

        items = items.filter { $0.timestamp > cutoffDate }
        AppLogger.info("清理后保留 \(items.count) 条历史记录")
    }

    func update(_ item: HistoryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            saveHistory()
            AppLogger.info("更新历史记录: \(item.id)")
        }
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        saveHistory()
    }

    func clearAll() {
        items = []
        saveHistory()
        AppLogger.info("已清空所有历史记录")
    }

    func export(to url: URL) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: url)
        AppLogger.info("已导出 \(items.count) 条历史记录到 \(url.path)")
    }

    func getTodayRecords() -> [HistoryItem] { items.filter { $0.isToday } }
    func getYesterdayRecords() -> [HistoryItem] { items.filter { $0.isYesterday } }

    func search(query: String) -> [HistoryItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.rawText.localizedCaseInsensitiveContains(query) ||
            $0.polishedText.localizedCaseInsensitiveContains(query)
        }
    }
}
