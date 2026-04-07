//
//  ASREngineManager.swift
//  Talk
//
//  统一管理 ASR 引擎的选择和切换
//

import Foundation

/// ASR 引擎管理器 — TalkApp 通过此管理器与 ASR 引擎交互
@Observable
@MainActor
final class ASREngineManager {
    static let shared = ASREngineManager()

    /// 当前活跃的引擎
    private(set) var current: (any ASREngineProtocol)?

    /// 当前引擎类型
    private(set) var engineType: ASREngineType = .mlxLocal

    /// 引擎是否就绪
    var isReady: Bool { current?.isReady ?? false }

    /// 是否正在识别
    var isRecognizing: Bool { current?.isRecognizing ?? false }

    private init() {}

    // MARK: - 引擎切换

    /// 根据设置选择并准备引擎
    func prepare(settings: AppSettings) async throws {
        let type: ASREngineType = settings.asrEngine

        // 引擎类型没变且已就绪，跳过
        if type == engineType, current?.isReady == true {
            return
        }

        // 释放旧引擎
        current?.release()

        let engine = Self.createEngine(type)
        engineType = type
        current = engine

        try await engine.prepare()
        AppLogger.info("ASR 引擎已准备: \(type.rawValue)", category: .asr)
    }

    /// 释放当前引擎
    func release() {
        current?.release()
        current = nil
        AppLogger.info("ASR 引擎已释放", category: .asr)
    }

    // MARK: - 工厂

    private static func createEngine(_ type: ASREngineType) -> any ASREngineProtocol {
        switch type {
        case .mlxLocal:
            return ASRService.shared
        case .appleSpeech:
            return AppleSpeechService.shared
        case .gemma4:
            return Gemma4ASREngine.shared
        }
    }

    // MARK: - 便捷方法（代理到当前引擎）

    func startStreaming(config: ASREngineConfig) async throws {
        guard let engine = current else { throw ASREngineError.notReady }
        try await engine.startStreaming(config: config)
    }

    func feedAudio(samples: [Float], sampleRate: Int) {
        current?.feedAudio(samples: samples, sampleRate: sampleRate)
    }

    func stopStreaming() {
        current?.stopStreaming()
    }

    func cancelStreaming() {
        current?.cancelStreaming()
    }

    func transcribe(audio: [Float], sampleRate: Int) async throws -> String {
        guard let engine = current else { throw ASREngineError.notReady }
        return try await engine.transcribe(audio: audio, sampleRate: sampleRate)
    }

    /// 设置回调
    func setCallbacks(
        onUpdate: @escaping (_ confirmed: String, _ provisional: String) -> Void,
        onComplete: @escaping (_ fullText: String) -> Void
    ) {
        current?.onTranscriptionUpdate = onUpdate
        current?.onTranscriptionComplete = onComplete
    }

    /// 清除回调
    func clearCallbacks() {
        current?.onTranscriptionUpdate = nil
        current?.onTranscriptionComplete = nil
    }

    /// 是否支持批量识别
    var supportsBatchTranscription: Bool {
        switch engineType {
        case .mlxLocal, .gemma4: return true
        case .appleSpeech: return false
        }
    }
}
