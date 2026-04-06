//
//  HistoryItem.swift
//  Talk
//
//  历史记录项模型
//

import Foundation

/// ASR 上下文快照，用于复盘和调试
struct ASRContext: Codable, Equatable {
    let language: String?
    let hotwordPrompt: String?
    let systemPrompt: String?
    let polishIntensity: String?
    let targetApp: String?

    init(
        language: String? = nil,
        hotwordPrompt: String? = nil,
        systemPrompt: String? = nil,
        polishIntensity: String? = nil,
        targetApp: String? = nil
    ) {
        self.language = language
        self.hotwordPrompt = hotwordPrompt
        self.systemPrompt = systemPrompt
        self.polishIntensity = polishIntensity
        self.targetApp = targetApp
    }
}

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    let rawText: String
    var polishedText: String
    let asrModel: String
    let llmModel: String
    var audioFilePath: String?
    var asrContext: ASRContext?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        duration: TimeInterval,
        rawText: String,
        polishedText: String,
        asrModel: String,
        llmModel: String,
        audioFilePath: String? = nil,
        asrContext: ASRContext? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.rawText = rawText
        self.polishedText = polishedText
        self.asrModel = asrModel
        self.llmModel = llmModel
        self.audioFilePath = audioFilePath
        self.asrContext = asrContext
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: timestamp)
    }

    var formattedDuration: String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m\(remainingSeconds)s"
        }
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(timestamp)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(timestamp)
    }
}
