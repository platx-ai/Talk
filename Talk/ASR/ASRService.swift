//
//  ASRService.swift
//  Talk
//
//  ASR 服务 - 封装 GLMASR 模型
//

import Foundation
import MLX
import MLXAudioSTT
import MLXAudioCore
import HuggingFace

/// ASR 服务
@Observable
@MainActor
final class ASRService {
    // MARK: - 单例

    @MainActor static let shared = ASRService()

    // MARK: - 属性

    /// ASR 模型
    private var model: Qwen3ASRModel?

    /// 是否已加载模型
    private(set) var isModelLoaded = false

    /// 是否正在加载
    private(set) var isLoading = false

    /// 加载进度（0-1）
    private(set) var loadingProgress: Double = 0

    // MARK: - 初始化

    private init() {
        // 私有初始化
    }

    // MARK: - 模型管理

    /// 加载模型
    /// - Parameters:
    ///   - modelId: HuggingFace 仓库 ID（如 "mlx-community/Qwen3-ASR-0.6B-4bit"）
    ///   - bundleResourcesURL: 可选 — 将其作为 HubCache 根目录，用于从 app bundle 加载已打包的模型。
    ///     bundle 内模型须位于 `<resourcesURL>/mlx-audio/mlx-community_Qwen3-ASR-0.6B-4bit/`
    func loadModel(modelId: String, bundleResourcesURL: URL? = nil) async throws {
        guard !isModelLoaded else {
            AppLogger.info("ASR 模型已加载", category: .asr)
            return
        }

        if let reason = MLXRuntimeValidator.missingMetalLibraryReason() {
            AppLogger.error("ASR 运行时检查失败: \(reason)", category: .asr)
            throw ASRError.runtimeUnavailable(reason)
        }

        isLoading = true
        loadingProgress = 0

        AppLogger.info("开始加载 ASR 模型: \(modelId)", category: .asr)

        do {
            let cache: HubCache
            if let resourcesURL = bundleResourcesURL {
                cache = HubCache(cacheDirectory: resourcesURL)
                AppLogger.info("ASR 使用 bundle 内缓存: \(resourcesURL.path)", category: .asr)
            } else {
                cache = .default
            }
            model = try await Qwen3ASRModel.fromPretrained(modelId, cache: cache)
            isModelLoaded = true
            loadingProgress = 1.0
            isLoading = false
            AppLogger.info("ASR 模型加载成功", category: .asr)
        } catch {
            isLoading = false
            AppLogger.error("ASR 模型加载失败: \(error.localizedDescription)", category: .asr)
            throw ASRError.modelLoadFailed(error)
        }
    }

    /// 卸载模型
    func unloadModel() {
        model = nil
        isModelLoaded = false
        AppLogger.info("ASR 模型已卸载", category: .asr)
    }

    // MARK: - 语音识别

    /// 识别音频
    func transcribe(audio: [Float], sampleRate: Int) async throws -> String {
        guard isModelLoaded else {
            AppLogger.error("ASR 模型未加载", category: .asr)
            throw ASRError.modelNotLoaded
        }

        guard let model = model else {
            AppLogger.error("ASR 模型为空", category: .asr)
            throw ASRError.modelNotLoaded
        }

        if sampleRate != 16000 {
            AppLogger.warning("ASR 输入采样率不是 16kHz: \(sampleRate)Hz", category: .asr)
        }

        AppLogger.debug(
            "开始语音识别，音频长度: \(audio.count) 样点，采样率: \(sampleRate)Hz",
            category: .asr
        )

        do {
            let audioArray = MLXArray(audio)
            let output = model.generate(audio: audioArray)
            let text = output.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            AppLogger.debug("语音识别完成: \(text)", category: .asr)
            return text
        } catch {
            AppLogger.error("语音识别失败: \(error.localizedDescription)", category: .asr)
            throw ASRError.transcriptionFailed(error)
        }
    }

    /// 流式识别音频
    func transcribeStream(audio: [Float], sampleRate: Int) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isModelLoaded else {
                        throw ASRError.modelNotLoaded
                    }

                    guard let model = model else {
                        throw ASRError.modelNotLoaded
                    }

                    let audioArray = MLXArray(audio)
                    let output = model.generate(audio: audioArray)
                    let text = output.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                    for character in text {
                        continuation.yield(String(character))
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - ASR 错误

enum ASRError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(Error)
    case transcriptionFailed(Error)
    case invalidAudioFormat
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "ASR 模型未加载"
        case .modelLoadFailed(let error):
            return "模型加载失败: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "语音识别失败: \(error.localizedDescription)"
        case .invalidAudioFormat:
            return "音频格式无效"
        case .runtimeUnavailable(let reason):
            return "ASR 运行环境不可用: \(reason)"
        }
    }
}
