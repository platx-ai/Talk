//
//  HistoryManager.swift
//  Talk
//
//  历史记录管理器
//

import Foundation
import AVFoundation

@Observable
@MainActor
final class HistoryManager {
    @MainActor static let shared = HistoryManager()

    private(set) var items: [HistoryItem] = []
    private let historyFilePath: URL
    private let audioDirectoryURL: URL
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

        audioDirectoryURL = localTypeURL.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)

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

        let expired = items.filter { $0.timestamp <= cutoffDate }
        for item in expired { deleteAudioFile(for: item) }
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
        deleteAudioFile(for: item)
        items.removeAll { $0.id == item.id }
        saveHistory()
    }

    func clearAll() {
        for item in items { deleteAudioFile(for: item) }
        items = []
        saveHistory()
        AppLogger.info("已清空所有历史记录")
    }

    // MARK: - 音频存储

    /// 将 PCM Float32 音频编码为 AAC/M4A 并保存，返回相对文件名
    func saveAudio(_ samples: [Float], sampleRate: Int, itemId: UUID) -> String? {
        let filename = "\(itemId.uuidString).m4a"
        let outputURL = audioDirectoryURL.appendingPathComponent(filename)

        // 创建 AVAudioFile 用于输出 AAC
        guard let outputFormat = AVAudioFormat(
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ]
        ) else {
            AppLogger.error("无法创建 AAC 输出格式", category: .storage)
            return nil
        }

        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            AppLogger.error("无法创建 PCM buffer", category: .storage)
            return nil
        }

        pcmBuffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = pcmBuffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { src in
            channelData.update(from: src.baseAddress!, count: samples.count)
        }

        do {
            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: pcmBuffer)
            AppLogger.debug("音频已保存: \(filename) (\(samples.count) samples)", category: .storage)
            return filename
        } catch {
            AppLogger.error("保存音频失败: \(error.localizedDescription)", category: .storage)
            return nil
        }
    }

    /// 获取音频文件完整路径
    func audioURL(for item: HistoryItem) -> URL? {
        guard let path = item.audioFilePath else { return nil }
        let url = audioDirectoryURL.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func deleteAudioFile(for item: HistoryItem) {
        guard let path = item.audioFilePath else { return }
        let url = audioDirectoryURL.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: url)
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
