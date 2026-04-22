//
//  Logger.swift
//  Talk
//
//  日志工具
//

import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = "com.kongjiaming.talk"
    private static let fileWriteQueue = DispatchQueue(label: "com.kongjiaming.talk.logger")

    private static let general = Logger(subsystem: subsystem, category: "General")
    private static let audio = Logger(subsystem: subsystem, category: "Audio")
    private static let asr = Logger(subsystem: subsystem, category: "ASR")
    private static let llm = Logger(subsystem: subsystem, category: "LLM")
    private static let ui = Logger(subsystem: subsystem, category: "UI")
    private static let hotkey = Logger(subsystem: subsystem, category: "Hotkey")
    private static let model = Logger(subsystem: subsystem, category: "Model")
    private static let storage = Logger(subsystem: subsystem, category: "Storage")

    enum Level {
        case debug, info, warning, error

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
    }

    static func debug(_ message: String, category: Category = .general) {
        log(message, level: .debug, category: category)
    }

    static func info(_ message: String, category: Category = .general) {
        log(message, level: .info, category: category)
    }

    static func warning(_ message: String, category: Category = .general) {
        log(message, level: .warning, category: category)
    }

    static func error(_ message: String, category: Category = .general) {
        log(message, level: .error, category: category)
    }

    static func logFilePath() -> String { logFileURL.path }

    private static func log(_ message: String, level: Level, category: Category) {
        let logger: Logger
        switch category {
        case .general: logger = general
        case .audio: logger = audio
        case .asr: logger = asr
        case .llm: logger = llm
        case .ui: logger = ui
        case .hotkey: logger = hotkey
        case .model: logger = model
        case .storage: logger = storage
        }

//        logger.log(level: level.osLogType, "\(message)")

        let levelLabel: String
        switch level {
        case .debug: levelLabel = "DEBUG"
        case .info: levelLabel = "INFO"
        case .warning: levelLabel = "WARN"
        case .error: levelLabel = "ERROR"
        }

        print("[\(levelLabel)] [\(category.rawValue)] \(message)")

        // Capture timestamp at log-call time, not at file-write time. Otherwise
        // a backlogged fileWriteQueue would make every entry look late and
        // mask the real event timing.
        let eventDate = Date()
        if level != .debug || AppSettings.load().enableDetailedLogging {
            fileWriteQueue.async {
                writeToFile(message, level: level, category: category, date: eventDate)
            }
        }
    }

    private static let logFileURL: URL = {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupportURL.appendingPathComponent("Talk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("talk.log")
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func writeToFile(_ message: String, level: Level, category: Category, date: Date) {
        let timestamp = dateFormatter.string(from: date)
        let levelString: String
        switch level {
        case .debug: levelString = "DEBUG"
        case .info: levelString = "INFO"
        case .warning: levelString = "WARN"
        case .error: levelString = "ERROR"
        }

        let logLine = "[\(timestamp)] [\(levelString)] [\(category.rawValue)] \(message)\n"

        if let handle = FileHandle(forWritingAtPath: logFileURL.path) ?? createLogFile() {
            handle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        }
    }

    private static func createLogFile() -> FileHandle? {
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        return FileHandle(forWritingAtPath: logFileURL.path)
    }

    static func cleanOldLogs() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let modificationDate = attributes[.modificationDate] as? Date,
           modificationDate < cutoffDate {
            try? FileManager.default.removeItem(at: logFileURL)
            debug("已清理旧日志文件")
        }
    }

    static func getLogFileContent() -> String? {
        try? String(contentsOf: logFileURL, encoding: .utf8)
    }

    static func clearLogFile() {
        try? FileManager.default.removeItem(at: logFileURL)
        debug("已清空日志文件")
    }
}

// MARK: - 日志类别

extension AppLogger {
    enum Category: String {
        case general, audio, asr, llm, ui, hotkey, model, storage
    }
}
