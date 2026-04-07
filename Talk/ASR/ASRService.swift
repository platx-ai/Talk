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

    /// 是否正在流式识别
    private(set) var isRecognizing = false

    /// 流式推理会话
    private var streamingSession: StreamingInferenceSession?

    /// 实时转录回调（confirmed: 已确认文本, provisional: 临时文本）
    var onTranscriptionUpdate: ((String, String) -> Void)?

    /// 流式识别结束回调（fullText: 完整文本）
    var onTranscriptionComplete: ((String) -> Void)?

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
    ///
    /// TODO: ModelScope 下载源支持
    /// 当前 `Qwen3ASRModel.fromPretrained` 使用 HuggingFace Hub 下载。MLXAudioSTT 框架暂不支持自定义 endpoint。
    /// ModelScope 上的模型文件格式与 HuggingFace 完全相同（ID 也相同），用户可：
    /// 1. 从 ModelScope 手动下载模型文件到 `~/.cache/huggingface/` 缓存目录
    /// 2. 使用 `make download-models` 脚本并配置 ModelScope 源
    /// 待 swift-huggingface 库支持自定义 endpoint 后，可通过 `AppSettings.shared.modelSource` 切换下载源。
    func loadModel(modelId: String, bundleResourcesURL: URL? = nil) async throws {
        guard !isModelLoaded else {
            AppLogger.info("ASR 模型已加载", category: .asr)
            return
        }
        // isLoading 检查：@MainActor 保证串行，但 Task.detached 的 await 挂起点
        // 可能让第二个 loadModel 进入。用 isLoading 防止重复下载。
        // processAudio 会在 loadModel return 后再次检查 isModelLoaded。
        guard !isLoading else {
            AppLogger.info("ASR 模型正在加载中，等待完成", category: .asr)
            // 等待加载完成（轮询，因为没有 continuation 机制）
            while isLoading { try await Task.sleep(for: .milliseconds(200)) }
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
            // 在后台线程加载模型，避免阻塞主线程/UI
            let loadedModel: Qwen3ASRModel = try await Task.detached(priority: .userInitiated) {
                let cache: HubCache
                if let resourcesURL = bundleResourcesURL {
                    cache = HubCache(cacheDirectory: resourcesURL)
                    AppLogger.info("ASR 使用 bundle 内缓存: \(resourcesURL.path)", category: .asr)
                } else {
                    cache = .default
                }
                return try await Qwen3ASRModel.fromPretrained(modelId, cache: cache)
            }.value

            model = loadedModel
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
        stopStreaming()
        model = nil
        isModelLoaded = false
        AppLogger.info("ASR 模型已卸载", category: .asr)
    }

    // MARK: - 流式语音识别

    /// 开始流式识别
    /// - Parameters:
    ///   - delayPreset: 延迟预设（Realtime ~200ms, Agent ~480ms, Subtitle ~2400ms）
    ///   - language: 语言代码（如 "Chinese", "English"）
    ///   - temperature: 温度参数（0.0-1.0），越高越随机
    func startStreaming(
        delayPreset: DelayPreset = .agent,
        language: String = "Chinese",
        temperature: Float = 0.0
    ) async throws {
        guard isModelLoaded else {
            AppLogger.error("ASR 模型未加载", category: .asr)
            throw ASRError.modelNotLoaded
        }

        guard let model = model else {
            AppLogger.error("ASR 模型为空", category: .asr)
            throw ASRError.modelNotLoaded
        }

        // 停止之前的会话
        stopStreaming()

        let config = StreamingConfig(
            decodeIntervalSeconds: 1.00,
            delayPreset: delayPreset,
            language: language,
            temperature: temperature,
            maxTokensPerPass: 20,
            minAgreementPasses: 2,
            finalizeCompletedWindows: true
        )

        streamingSession = StreamingInferenceSession(model: model, config: config)
        isRecognizing = true

        AppLogger.info("开始流式识别，延迟预设: \(delayPreset)", category: .asr)

        // 监听事件流
        Task {
            guard let session = streamingSession else { return }

            for await event in session.events {
                switch event {
                case .provisional(let text):
                    // 临时文本，可能还会变化
                    AppLogger.debug("临时识别: \(text)", category: .asr)
                    await MainActor.run {
                        onTranscriptionUpdate?("", text)
                    }
                case .confirmed(let text):
                    // 已确认文本
                    AppLogger.debug("确认识别: \(text)", category: .asr)
                    await MainActor.run {
                        onTranscriptionUpdate?(text, "")
                    }
                case .displayUpdate(let confirmed, let provisional):
                    // 显示更新：确认文本 + 临时文本
                    AppLogger.debug("显示更新: 确认=\(confirmed), 临时=\(provisional)", category: .asr)
                    await MainActor.run {
                        onTranscriptionUpdate?(confirmed, provisional)
                    }
                case .stats(let stats):
                    // 性能统计
                    AppLogger.debug("流式统计: \(stats)", category: .asr)
                case .ended(let fullText):
                    // 识别结束
                    AppLogger.info("流式识别结束: \(fullText)", category: .asr)
                    await MainActor.run {
                        onTranscriptionComplete?(fullText)
                        onTranscriptionUpdate?(fullText, "")
                    }
                }
            }
        }
    }

    /// 喂入音频数据
    /// - Parameters:
    ///   - samples: 音频样点数组
    ///   - sampleRate: 采样率（应为 16000）
    func feedAudio(samples: [Float], sampleRate: Int) {
        guard let session = streamingSession else {
            AppLogger.warning("流式会话未启动", category: .asr)
            return
        }

        if sampleRate != 16000 {
            AppLogger.warning("流式识别输入采样率不是 16kHz: \(sampleRate)Hz, samples=\(samples.count)", category: .asr)
        }

        session.feedAudio(samples: samples)
    }

    /// 停止流式识别
    func stopStreaming() {
        guard streamingSession != nil else {
            return
        }

        AppLogger.info("停止流式识别", category: .asr)
        streamingSession = nil
        isRecognizing = false
        onTranscriptionUpdate = nil
        onTranscriptionComplete = nil
    }

    // MARK: - 语音识别

    /// 构建热词 initialPrompt（从词库中提取高频正确形式）
    ///
    /// 实验验证：batch-only 场景下所有 prompt 格式均安全有效。
    /// 生产环境幻觉原因：VAD 裁剪后的短音频 + hotword 导致模型退化。
    /// 安全措施：音频 < 3s 不注入、去重、限制数量。
    /// 构建热词 initialPrompt
    ///
    /// 已禁用 — 生产环境确认：有 hotword 必出问题，无 hotword 完全正常。
    /// 流式 decode 后模型状态变化，使得 batch generate 中的 system prompt
    /// 注入不可控（输出 "."、"语言 Chinese"、"Chinese" 循环、数字递增等）。
    /// 纯 batch 测试无法复现，因为测试中模型没经过流式 decode。
    /// 热词修正完全依赖 LLM 润色阶段。
    private func buildHotwordPrompt(audioSampleCount: Int = 0, sampleRate: Int = 16000) -> String? {
        return nil
    }

    /// 识别音频（指定 initialPrompt，用于测试和外部调用）
    /// 注意：initialPrompt 已禁用（流式后 batch 不稳定），此方法保留供测试使用
    func transcribe(audio: [Float], sampleRate: Int, initialPrompt: String?) async throws -> String {
        guard isModelLoaded else { throw ASRError.modelNotLoaded }
        guard let model = model else { throw ASRError.modelNotLoaded }

        let audioArray = MLXArray(audio)
        // initialPrompt 参数不再传递给模型（已禁用）
        let output = model.generate(audio: audioArray)
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

// MARK: - ASREngineProtocol 适配

extension ASRService: ASREngineProtocol {
    var isReady: Bool { isModelLoaded }

    func prepare() async throws {
        let settings = AppSettings.shared
        try await loadModel(modelId: settings.asrModelId)
    }

    func release() {
        unloadModel()
    }

    func startStreaming(config: ASREngineConfig) async throws {
        try await startStreaming(
            delayPreset: .realtime,
            language: config.language,
            temperature: 0.0
        )
    }

    func cancelStreaming() {
        stopStreaming()
    }
}

// MARK: - ASR 错误

public enum ASRError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(Error)
    case transcriptionFailed(Error)
    case invalidAudioFormat
    case runtimeUnavailable(String)

    public var errorDescription: String? {
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
