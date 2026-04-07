//
//  Gemma4ASREngine.swift
//  Talk
//
//  Gemma4 ASR 引擎 — 端到端音频直接输出润色文本
//  实现 ASREngineProtocol，通过 ASREngineManager 接入
//

import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import Tokenizers

/// Gemma4 ASR 引擎
@Observable
@MainActor
final class Gemma4ASREngine {
    static let shared = Gemma4ASREngine()

    // MARK: - 状态

    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var isRecognizing = false

    var onTranscriptionUpdate: ((_ confirmed: String, _ provisional: String) -> Void)?
    var onTranscriptionComplete: ((_ fullText: String) -> Void)?

    // MARK: - 模型

    private var modelContext: ModelContext?

    private init() {}

    // MARK: - 结构化 prompt（实验验证的最优 prompt）

    static let defaultPrompt = "Transcribe this audio verbatim."

    // MARK: - 模型管理

    func loadModel(modelId: String) async throws {
        guard !isModelLoaded else { return }
        guard !isLoading else {
            while isLoading { try await Task.sleep(for: .milliseconds(200)) }
            return
        }

        isLoading = true
        AppLogger.info("开始加载 Gemma4 模型: \(modelId)", category: .asr)

        do {
            let configuration = ModelConfiguration(id: modelId)
            let context = try await VLMModelFactory.shared.load(configuration: configuration)

            modelContext = context
            isModelLoaded = true
            isLoading = false
            AppLogger.info("Gemma4 模型加载成功", category: .asr)
        } catch {
            isLoading = false
            AppLogger.error("Gemma4 模型加载失败: \(error.localizedDescription)", category: .asr)
            throw error
        }
    }

    func unloadModel() {
        modelContext = nil
        isModelLoaded = false
        AppLogger.info("Gemma4 模型已卸载", category: .asr)
    }

    // MARK: - 转录

    /// 端到端转录：音频 → Gemma4 → 润色文本
    func transcribe(audio: [Float], sampleRate: Int, prompt: String? = nil) async throws -> String {
        guard isModelLoaded, let context = modelContext else {
            throw ASRError.modelNotLoaded
        }

        let effectivePrompt = prompt ?? Self.defaultPrompt

        AppLogger.debug(
            "Gemma4 开始转录，音频长度: \(audio.count) 样点",
            category: .asr
        )

        // 构建 UserInput，包含音频
        var input = UserInput(prompt: effectivePrompt)
        input.audios = [audio]

        do {
            let startTime = CFAbsoluteTimeGetCurrent()

            // prepare: 提取 mel → 构建 LMInput
            let lmInput = try await context.processor.prepare(input: input)

            AppLogger.debug(
                "Gemma4 LMInput: tokens=\(lmInput.text.tokens.shape), hasAudio=\(lmInput.audio != nil), audioShape=\(lmInput.audio?.features.shape.description ?? "nil")",
                category: .asr
            )

            // Generate: use model.prepare for first step (handles audio embedding),
            // then callAsFunction for subsequent tokens
            let model = context.model
            let cache = model.newCache(parameters: nil)
            let prepareResult = try model.prepare(lmInput, cache: cache, windowSize: nil)

            var outputTokens = [Int]()
            var logits: MLXArray
            switch prepareResult {
            case .logits(let result):
                logits = result.logits
            case .tokens(let tokens):
                logits = model.callAsFunction(tokens.tokens, cache: cache)
            }

            for _ in 0..<500 {
                let lastLogits = logits[0..., -1, 0...]
                let nextToken = lastLogits.argMax(axis: -1).item(Int.self)

                // Stop on EOS/special tokens
                // <eos>=1, <turn|>=106, <|turn>=105, <channel|>=101, <|channel>=100
                if [1, 106, 105, 101, 100].contains(nextToken) { break }

                outputTokens.append(nextToken)

                let nextTokenArray = MLXArray([Int32(nextToken)]).expandedDimensions(axis: 0)
                logits = model.callAsFunction(nextTokenArray, cache: cache)
                eval(logits)
            }

            let text = context.tokenizer.decode(tokens: outputTokens)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // t2s 后处理
            if AppSettings.shared.gemma4EnableT2S {
                result = traditionalToSimplified(result)
            }

            AppLogger.info(
                "Gemma4 转录完成: \(String(format: "%.2f", elapsed))s",
                category: .asr
            )

            return result
        } catch {
            AppLogger.error("Gemma4 转录失败: \(error.localizedDescription)", category: .asr)
            throw ASRError.transcriptionFailed(error)
        }
    }

    // MARK: - 繁→简转换

    private func traditionalToSimplified(_ text: String) -> String {
        let t2s: [Character: Character] = [
            "對": "对", "實": "实", "驗": "验", "確": "确", "認": "认",
            "開": "开", "這": "这", "們": "们", "會": "会", "議": "议",
            "應": "应", "該": "该", "準": "准", "備": "备", "節": "节",
            "點": "点", "時": "时", "間": "间", "範": "范", "圍": "围",
            "處": "处", "計": "计", "劃": "划", "書": "书", "項": "项",
            "報": "报", "導": "导", "數": "数", "據": "据", "層": "层",
            "東": "东", "關": "关", "聯": "联", "結": "结", "構": "构",
            "題": "题", "標": "标", "發": "发", "條": "条", "執": "执",
            "編": "编", "輯": "辑", "預": "预", "覽": "览", "線": "线",
            "單": "单", "選": "选", "擇": "择", "圖": "图", "純": "纯",
            "號": "号", "鍵": "键", "際": "际", "異": "异", "軟": "软",
            "環": "环", "學": "学", "紀": "纪", "錄": "录", "則": "则",
            "組": "组", "碼": "码", "體": "体", "設": "设", "問": "问",
            "調": "调", "試": "试", "進": "进", "還": "还", "過": "过",
            "運": "运", "動": "动", "從": "从", "來": "来", "經": "经",
            "現": "现", "見": "见", "說": "说", "話": "话", "語": "语",
            "個": "个", "裡": "里", "後": "后", "種": "种", "樣": "样",
            "讓": "让", "給": "给", "與": "与", "為": "为", "長": "长",
            "機": "机", "無": "无", "電": "电", "區": "区", "廠": "厂",
        ]
        return String(text.map { t2s[$0] ?? $0 })
    }
}

// MARK: - ASREngineProtocol

extension Gemma4ASREngine: ASREngineProtocol {
    var isReady: Bool { isModelLoaded }

    func prepare() async throws {
        let settings = AppSettings.shared
        try await loadModel(modelId: settings.gemma4ModelId)
    }

    func release() {
        unloadModel()
    }

    func startStreaming(config: ASREngineConfig) async throws {
        isRecognizing = true
    }

    func feedAudio(samples: [Float], sampleRate: Int) {
        // Gemma4 不支持流式 feed
    }

    func stopStreaming() {
        isRecognizing = false
    }

    func cancelStreaming() {
        isRecognizing = false
    }

    func transcribe(audio: [Float], sampleRate: Int) async throws -> String {
        try await transcribe(audio: audio, sampleRate: sampleRate, prompt: nil)
    }
}
