//
//  UsageStatistics.swift
//  Talk
//
//  使用统计管理
//

import Foundation
import OSLog

/// 单日使用统计
struct DailyStats: Codable, Identifiable {
    let id: UUID
    let date: Date  // 仅保留日期部分
    var sessionCount: Int = 0           // 使用次数
    var totalRecordingDuration: TimeInterval = 0  // 总录音时长（秒）
    var totalProcessingTime: TimeInterval = 0     // 总处理时长（秒）
    var asrInferenceTime: TimeInterval = 0        // ASR 推理总时长
    var llmInferenceTime: TimeInterval = 0        // LLM 推理总时长
    var editCount: Int = 0              // 用户编辑次数
    var errorCount: Int = 0             // 错误次数
    var totalCharacters: Int = 0              // 总输出字符数
    
    /// 平均每次使用时长
    var averageSessionDuration: TimeInterval {
        sessionCount > 0 ? totalRecordingDuration / Double(sessionCount) : 0
    }
    
    /// 编辑率（用户编辑次数 / 使用次数）
    var editRate: Double {
        sessionCount > 0 ? Double(editCount) / Double(sessionCount) : 0
    }
    
    init(id: UUID = UUID(), date: Date = Date()) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        sessionCount = try container.decode(Int.self, forKey: .sessionCount)
        totalRecordingDuration = try container.decode(TimeInterval.self, forKey: .totalRecordingDuration)
        totalProcessingTime = try container.decode(TimeInterval.self, forKey: .totalProcessingTime)
        asrInferenceTime = try container.decode(TimeInterval.self, forKey: .asrInferenceTime)
        llmInferenceTime = try container.decode(TimeInterval.self, forKey: .llmInferenceTime)
        editCount = try container.decode(Int.self, forKey: .editCount)
        errorCount = try container.decode(Int.self, forKey: .errorCount)
        totalCharacters = try container.decodeIfPresent(Int.self, forKey: .totalCharacters) ?? 0
    }
}

/// 聚合统计
struct AggregateStats {
    let totalSessions: Int
    let totalDuration: TimeInterval
    let totalCharacters: Int
    let totalEdits: Int
    let totalErrors: Int
    let averageEditRate: Double
    let averageErrorRate: Double

    /// 格式化时长为 "X 小时 Y 分钟" 或 "Y 分钟"
    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return String(localized: "\(hours) 小时\(minutes) 分钟")
        } else {
            return String(localized: "\(minutes) 分钟")
        }
    }

    /// 格式化总时长
    var totalDurationFormatted: String {
        Self.formatDuration(totalDuration)
    }

    /// 估算节省时间（打字 100 字/分钟 vs 实际录音时长）
    var estimatedTimeSaved: TimeInterval {
        let typingTime = Double(totalCharacters) / 100.0 * 60.0
        return max(0, typingTime - totalDuration)
    }

    /// 格式化节省时间
    var estimatedTimeSavedFormatted: String {
        Self.formatDuration(estimatedTimeSaved)
    }
}

/// 使用统计管理器
@Observable
@MainActor
final public class UsageStatisticsManager {
    static let shared = UsageStatisticsManager()
    
    private(set) var dailyStats: [DailyStats] = []
    private let statsFilePath: URL
    private let maxHistoryDays = 90  // 保留 90 天数据
    private let logger = Logger(subsystem: "com.talk.app", category: "Analytics")
    
    private init() {
        // 确定存储路径：~/Library/Application Support/Talk/usage_stats.json
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let talkURL = appSupportURL.appendingPathComponent("Talk", isDirectory: true)
        
        try? FileManager.default.createDirectory(
            at: talkURL,
            withIntermediateDirectories: true
        )
        
        statsFilePath = talkURL.appendingPathComponent("usage_stats.json")
        loadStats()
    }
    
    /// 加载统计数据
    private func loadStats() {
        guard FileManager.default.fileExists(atPath: statsFilePath.path) else {
            logger.info("统计数据文件不存在，使用空数据")
            return
        }
        
        do {
            let data = try Data(contentsOf: statsFilePath)
            dailyStats = try JSONDecoder().decode([DailyStats].self, from: data)
            logger.info("加载了 \(self.dailyStats.count) 天的统计数据")
            cleanupOldStats()
        } catch {
            logger.error("加载统计数据失败：\(error.localizedDescription)")
            dailyStats = []
        }
    }
    
    /// 保存统计数据
    private func saveStats() {
        do {
            let data = try JSONEncoder().encode(dailyStats)
            try data.write(to: statsFilePath)
            logger.debug("统计数据已保存")
        } catch {
            logger.error("保存统计数据失败：\(error.localizedDescription)")
        }
    }
    
    /// 清理 90 天前的旧数据
    private func cleanupOldStats() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxHistoryDays, to: Date())!
        let oldCount = self.dailyStats.count
        dailyStats.removeAll { $0.date < cutoffDate }
        
        if self.dailyStats.count != oldCount {
            logger.info("清理了 \(oldCount - self.dailyStats.count) 条旧统计数据")
            saveStats()
        }
    }
    
    // MARK: - 记录方法
    
    /// 记录单次使用
    func recordSession(
        recordingDuration: TimeInterval,
        processingTime: TimeInterval,
        asrTime: TimeInterval,
        llmTime: TimeInterval,
        characterCount: Int = 0,
        hadError: Bool = false
    ) {
        let today = Calendar.current.startOfDay(for: Date())
        
        // 查找今天的记录
        if let index = dailyStats.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            // 更新现有记录
            dailyStats[index].sessionCount += 1
            dailyStats[index].totalRecordingDuration += recordingDuration
            dailyStats[index].totalProcessingTime += processingTime
            dailyStats[index].asrInferenceTime += asrTime
            dailyStats[index].llmInferenceTime += llmTime
            if hadError {
                dailyStats[index].errorCount += 1
            }
            dailyStats[index].totalCharacters += characterCount
            logger.debug("更新了今天的统计记录")
        } else {
            // 创建新记录
            var newDay = DailyStats(date: today)
            newDay.sessionCount = 1
            newDay.totalRecordingDuration = recordingDuration
            newDay.totalProcessingTime = processingTime
            newDay.asrInferenceTime = asrTime
            newDay.llmInferenceTime = llmTime
            newDay.errorCount = hadError ? 1 : 0
            newDay.totalCharacters = characterCount
            dailyStats.append(newDay)
            logger.info("创建了新的统计记录")
        }
        
        saveStats()
    }
    
    /// 记录用户编辑
    func recordEdit() {
        let today = Calendar.current.startOfDay(for: Date())
        
        if let index = dailyStats.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            dailyStats[index].editCount += 1
            logger.debug("记录了编辑操作")
            saveStats()
        } else {
            // 如果今天还没有使用记录，创建一个
            var newDay = DailyStats(date: today)
            newDay.editCount = 1
            dailyStats.append(newDay)
            logger.info("创建了包含编辑记录的新统计")
            saveStats()
        }
    }
    
    // MARK: - 查询方法
    
    /// 获取最近 7 天的统计数据
    func getStatsForLast7Days() -> [DailyStats] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        return dailyStats
            .filter { $0.date >= sevenDaysAgo }
            .sorted { $0.date < $1.date }
    }
    
    /// 获取最近 30 天的统计数据
    func getStatsForLast30Days() -> [DailyStats] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
        return dailyStats
            .filter { $0.date >= thirtyDaysAgo }
            .sorted { $0.date < $1.date }
    }
    
    /// 获取聚合统计
    func getAggregateStats() -> AggregateStats {
        let totalSessions = dailyStats.reduce(0) { $0 + $1.sessionCount }
        let totalDuration = dailyStats.reduce(0) { $0 + $1.totalRecordingDuration }
        let totalCharacters = dailyStats.reduce(0) { $0 + $1.totalCharacters }
        let totalEdits = dailyStats.reduce(0) { $0 + $1.editCount }
        let totalErrors = dailyStats.reduce(0) { $0 + $1.errorCount }

        return AggregateStats(
            totalSessions: totalSessions,
            totalDuration: totalDuration,
            totalCharacters: totalCharacters,
            totalEdits: totalEdits,
            totalErrors: totalErrors,
            averageEditRate: totalSessions > 0 ? Double(totalEdits) / Double(totalSessions) : 0,
            averageErrorRate: totalSessions > 0 ? Double(totalErrors) / Double(totalSessions) : 0
        )
    }
    
    /// 清空所有统计数据
    func clearAllStats() {
        dailyStats = []
        saveStats()
        logger.info("已清空所有统计数据")
    }
}
