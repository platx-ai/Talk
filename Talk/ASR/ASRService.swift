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
    ///
    /// 关键点：调 `session.cancel()` 真正打断上游 `decodeTask.Task.detached`，
    /// 否则它会继续跑完当前 window 的完整 decode（3-6 秒），期间 MLX 模型被锁住，
    /// 后续的 batch `model.generate(...)` 要排队等它释放。这是 issue #13 6.5s gap
    /// 的真正根因。
    func stopStreaming() {
        guard let session = streamingSession else {
            return
        }

        AppLogger.info("停止流式识别", category: .asr)
        session.cancel()
        streamingSession = nil
        isRecognizing = false
        onTranscriptionUpdate = nil
        onTranscriptionComplete = nil
    }

    // MARK: - 语言参数解析

    /// 将 AppSettings.ASRLanguage 转换为 Qwen3 ASR 模型所需的语言字符串
    /// Qwen3 模型的 buildPrompt 接受 "Chinese", "English" 等语言名，大小写不敏感
    private func resolveLanguageForModel(_ asrLanguage: AppSettings.ASRLanguage) -> String {
        switch asrLanguage {
        case .chinese, .mixed:
            return "Chinese"
        case .english:
            return "English"
        case .auto:
            // auto 模式默认用 Chinese（用户主要中文场景），
            // 后续由 transcribeWithLanguageRetry 检测并纠正
            return "Chinese"
        }
    }

    // MARK: - 语言检测启发式

    /// 检测文本是否主要为英文输出（用于 auto 模式下语言误判检测）
    /// 返回 true 表示文本主要是英文（ASCII 字母比例 > 80%）
    private func looksLikeEnglishOutput(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let asciiLetterCount = trimmed.unicodeScalars.filter {
            ($0.value >= 0x41 && $0.value <= 0x5A) ||  // A-Z
            ($0.value >= 0x61 && $0.value <= 0x7A)      // a-z
        }.count

        let totalNonSpace = trimmed.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) &&
            !CharacterSet.punctuationCharacters.contains($0)
        }.count

        guard totalNonSpace > 0 else { return false }

        let asciiRatio = Double(asciiLetterCount) / Double(totalNonSpace)
        return asciiRatio > 0.80
    }

    /// 检测文本是否包含 CJK 字符（中日韩统一表意文字）
    private func containsCJK(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) ||   // CJK Unified
            (scalar.value >= 0x3400 && scalar.value <= 0x4DBF) ||   // CJK Extension A
            (scalar.value >= 0x20000 && scalar.value <= 0x2A6DF)    // CJK Extension B
        }
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

        let language = resolveLanguageForModel(AppSettings.shared.asrLanguage)
        let audioArray = MLXArray(audio)
        // initialPrompt 参数不再传递给模型（已禁用）
        let output = model.generate(audio: audioArray, language: language)
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

        let settings = AppSettings.shared
        let language = resolveLanguageForModel(settings.asrLanguage)

        AppLogger.debug(
            "开始语音识别，音频长度: \(audio.count) 样点，采样率: \(sampleRate)Hz，语言: \(language)",
            category: .asr
        )

        do {
            let audioArray = MLXArray(audio)
            let text: String

            // auto 模式下使用语言验证重试
            if settings.asrLanguage == .auto {
                text = try await transcribeWithLanguageRetry(
                    model: model, audioArray: audioArray, primaryLanguage: language)
            } else {
                let output = model.generate(audio: audioArray, language: language)
                text = output.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }

            AppLogger.debug("语音识别完成: \(text)", category: .asr)
            return text
        } catch {
            AppLogger.error("语音识别失败: \(error.localizedDescription)", category: .asr)
            throw ASRError.transcriptionFailed(error)
        }
    }

    /// Post-ASR 语言验证 + 重跑
    ///
    /// auto 模式下，先用主语言（Chinese）识别。如果输出全是英文（无 CJK 字符，且 ASCII 比例 > 80%），
    /// 说明可能误判语言，用 English 重跑一次，取两次结果中更合理的那个。
    ///
    /// 判断逻辑：
    /// - 第一次用 Chinese，如果输出包含 CJK → 直接用（大概率正确）
    /// - 第一次用 Chinese，输出全英文 → 用 English 重跑
    ///   - 如果 English 结果也全英文 → 用户确实说的英文，返回 English 结果
    ///   - 如果 English 结果包含 CJK → 不太可能，返回 Chinese 结果
    private func transcribeWithLanguageRetry(
        model: Qwen3ASRModel, audioArray: MLXArray, primaryLanguage: String
    ) async throws -> String {
        // 第一次：用主语言（Chinese）
        let primaryOutput = model.generate(audio: audioArray, language: primaryLanguage)
        let primaryText = primaryOutput.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // 如果输出包含 CJK 字符，大概率是中文，直接返回
        if containsCJK(primaryText) {
            AppLogger.debug("语言验证: 输出包含 CJK，无需重试", category: .asr)
            return primaryText
        }

        // 输出全英文 → Qwen3 语言误判
        if looksLikeEnglishOutput(primaryText) {
            // 如果用户已选 Gemma4 作为 LLM 引擎（模型已在内存中），
            // 利用它的多模态能力做 fallback（不额外加载模型）
            if AppSettings.shared.llmEngine == .gemma4 && Gemma4ASREngine.shared.isModelLoaded {
                AppLogger.info("语言验证: 输出全英文，用已加载的 Gemma4 做 fallback", category: .asr)
                do {
                    let audioFloats = audioArray.asArray(Float.self)
                    let gemmaText = try await Gemma4ASREngine.shared.transcribe(
                        audio: audioFloats, sampleRate: 16000)
                    if !gemmaText.isEmpty && containsCJK(gemmaText) {
                        AppLogger.info("语言验证: Gemma4 fallback 成功", category: .asr)
                        return gemmaText
                    }
                } catch {
                    AppLogger.warning("语言验证: Gemma4 fallback 失败", category: .asr)
                }
            }

            // Qwen3 English 重跑确认
            AppLogger.info("语言验证: 用 Qwen3 English 模式重跑", category: .asr)
            let retryOutput = model.generate(audio: audioArray, language: "English")
            let retryText = retryOutput.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if looksLikeEnglishOutput(retryText) && !containsCJK(retryText) {
                return retryText
            }
            return primaryText
        }

        // 既不是 CJK 也不像英文（数字、标点等），直接返回
        return primaryText
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

                    let language = resolveLanguageForModel(AppSettings.shared.asrLanguage)
                    let audioArray = MLXArray(audio)
                    let output = model.generate(audio: audioArray, language: language)
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
