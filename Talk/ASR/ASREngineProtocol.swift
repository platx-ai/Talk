//
//  ASREngineProtocol.swift
//  Talk
//
//  统一 ASR 引擎接口 — 所有引擎（Qwen3, Apple Speech, Gemma4 等）实现此协议
//

import Foundation

/// ASR 引擎配置（每个引擎自行解读需要的字段）
struct ASREngineConfig {
    let language: String
    let enableStreaming: Bool
    let sampleRate: Int

    init(language: String = "Chinese", enableStreaming: Bool = true, sampleRate: Int = 16000) {
        self.language = language
        self.enableStreaming = enableStreaming
        self.sampleRate = sampleRate
    }
}

/// 统一 ASR 引擎协议
@MainActor
protocol ASREngineProtocol: AnyObject {

    // MARK: - 状态

    /// 引擎是否已就绪（模型已加载 / 服务可用）
    var isReady: Bool { get }

    /// 是否正在流式识别
    var isRecognizing: Bool { get }

    // MARK: - 回调

    /// 流式识别更新（confirmed: 已确认文本, provisional: 临时文本）
    var onTranscriptionUpdate: ((_ confirmed: String, _ provisional: String) -> Void)? { get set }

    /// 流式识别完成（fullText: 完整文本）
    var onTranscriptionComplete: ((_ fullText: String) -> Void)? { get set }

    // MARK: - 生命周期

    /// 准备引擎（加载模型、检查权限等）
    func prepare() async throws

    /// 释放资源（卸载模型等）
    func release()

    // MARK: - 流式识别

    /// 开始流式识别
    func startStreaming(config: ASREngineConfig) async throws

    /// 喂入音频数据
    func feedAudio(samples: [Float], sampleRate: Int)

    /// 停止流式识别（等待最终结果）
    func stopStreaming()

    /// 取消流式识别（不等结果）
    func cancelStreaming()

    // MARK: - 批量识别

    /// 批量识别整段音频（不支持的引擎抛错）
    func transcribe(audio: [Float], sampleRate: Int) async throws -> String
}

/// 默认实现：不支持批量识别的引擎
extension ASREngineProtocol {
    func transcribe(audio: [Float], sampleRate: Int) async throws -> String {
        throw ASREngineError.batchNotSupported
    }

    func cancelStreaming() {
        stopStreaming()
    }
}

/// 引擎类型（复用 AppSettings.ASREngine 枚举值）
typealias ASREngineType = AppSettings.ASREngine

/// 引擎通用错误
enum ASREngineError: LocalizedError {
    case notReady
    case batchNotSupported
    case engineUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "ASR engine not ready"
        case .batchNotSupported:
            return "Batch transcription not supported by this engine"
        case .engineUnavailable(let reason):
            return "ASR engine unavailable: \(reason)"
        }
    }
}
