//
//  HistoryItem.swift
//  Talk
//
//  历史记录项模型
//

import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    let rawText: String
    var polishedText: String
    let asrModel: String
    let llmModel: String
    var audioFilePath: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        duration: TimeInterval,
        rawText: String,
        polishedText: String,
        asrModel: String,
        llmModel: String,
        audioFilePath: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.rawText = rawText
        self.polishedText = polishedText
        self.asrModel = asrModel
        self.llmModel = llmModel
        self.audioFilePath = audioFilePath
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
