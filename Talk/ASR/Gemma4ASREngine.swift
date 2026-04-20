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

    /// Build prompt for one-pass mode, incorporating user settings and vocabulary corrections
    static func buildPrompt(
        intensity: AppSettings.PolishIntensity = .medium,
        customPrompt: String? = nil,
        appPrompt: String? = nil
    ) -> String {
        var prompt = defaultPrompt

        // Polish intensity
        switch intensity {
        case .light:
            break  // verbatim only
        case .medium:
            prompt += " Add proper punctuation."
        case .strong:
            prompt += " Clean up filler words (um, uh, 嗯, 啊), add punctuation, and format into clean paragraphs."
        }

        // Per-app prompt takes priority over global custom prompt
        if let appPrompt, !appPrompt.isEmpty {
            prompt += " Additional instructions: \(appPrompt)"
        } else if let customPrompt, !customPrompt.isEmpty {
            prompt += " Additional instructions: \(customPrompt)"
        }

        // Inject vocabulary corrections
        let corrections = VocabularyManager.shared.getHighFrequencyItems(limit: 30)
        if !corrections.isEmpty {
            let correctionLines = corrections.map { "\($0.word) → \($0.correctedForm ?? $0.word)" }.joined(separator: ", ")
            prompt += " IMPORTANT word corrections (must apply): \(correctionLines)"
        }

        return prompt
    }

    // MARK: - 模型管理

    func loadModel(modelId: String) async throws {
        guard !isModelLoaded else { return }
        guard !isLoading else {
            while isLoading { try await Task.sleep(for: .milliseconds(200)) }
            return
        }

        isLoading = true
        AppLogger.info("开始加载 Gemma4 模型: \(modelId)", category: .asr)

        // 本地 snapshot 直连（参见 LLMService.loadModel 的注释）：
        // 走 ~/.cache/huggingface/hub/models--<org>--<repo>/snapshots/<hash>/，
        // ModelConfiguration(directory:) 让 downloadModel() 短路到 case .directory，
        // 0 网络 / 0 ETag 校验，纯 mmap。
        let cachedSnapshot: URL? = modelId.hasPrefix("/")
            ? URL(fileURLWithPath: modelId)
            : HFCacheResolver.snapshotDirectory(for: modelId)
        if let snapshot = cachedSnapshot {
            AppLogger.info("Gemma4 本地直接加载: \(snapshot.path)", category: .asr)
        }

        do {
            let context: ModelContext
            if let snapshot = cachedSnapshot {
                let configuration = ModelConfiguration(directory: snapshot)
                context = try await VLMModelFactory.shared.load(configuration: configuration)
            } else {
                // 本地无缓存：联网下载
                let configuration = ModelConfiguration(id: modelId)
                context = try await VLMModelFactory.shared.load(configuration: configuration)
            }

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
    ///
    /// 推理跑在 `Task.detached` 后台 task 里，不占主线程。这是为了避免
    /// 当 Talk 不是前台 app 时（用户在 Feishu / Cursor / Terminal 中），
    /// 主线程 run loop 被 macOS 降 QoS 而导致每 token 调度间隔从 ~10ms 涨到
    /// ~50ms，使一次推理从 1s 飙到 14s。整段循环在同一个 detached task
    /// 中执行，所有 MLX 对象（model / cache / tokenizer / MLXArray）都
    /// 在该 task 内创建和使用，不跨 task hop，等价于单线程访问 — 不需
    /// 要 ModelContainer 那层 actor 包装。
    func transcribe(audio: [Float], sampleRate: Int, prompt: String? = nil) async throws -> String {
        guard isModelLoaded, let context = modelContext else {
            throw ASRError.modelNotLoaded
        }

        let effectivePrompt = prompt ?? Self.defaultPrompt
        let enableT2S = AppSettings.shared.gemma4EnableT2S

        AppLogger.debug(
            "Gemma4 开始转录，音频长度: \(audio.count) 样点",
            category: .asr
        )

        do {
            let result = try await Task.detached(priority: .userInitiated) { [audio] in
                try await Self.runGenerate(
                    context: context,
                    prompt: effectivePrompt,
                    audio: audio,
                    enableT2S: enableT2S,
                    label: "转录",
                    category: .asr
                )
            }.value
            return result
        } catch {
            AppLogger.error("Gemma4 转录失败: \(error.localizedDescription)", category: .asr)
            throw ASRError.transcriptionFailed(error)
        }
    }

    // MARK: - 音频感知润色（Gemma4 作为 LLM 引擎）

    /// Audio-aware polish: Gemma4 receives both audio and ASR text, corrects errors.
    /// When `selectedText` is provided, switch to edit-command mode:
    /// treat `asrText` as a voice instruction acting on the selected text.
    func polish(
        audio: [Float], sampleRate: Int, asrText: String,
        prompt: String? = nil, selectedText: String? = nil
    ) async throws -> String {
        guard isModelLoaded, let context = modelContext else {
            throw ASRError.modelNotLoaded
        }

        // Skip the model on degenerate inputs:
        // - Empty input: would hallucinate "我觉得我觉得..." pages of filler.
        // - Single-character or pure-filler input ("嗯", "啊", "好"): observed
        //   2026-04-17 20:19:41 — input "嗯。" produced "我想说昨天的事。" because
        //   the model mimicked one of our few-shot prompt examples instead of
        //   actually polishing.
        // Edit mode still runs because the command itself lives in selectedText.
        let trimmedAsr = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEditMode = !(selectedText?.isEmpty ?? true)
        if !isEditMode {
            if trimmedAsr.isEmpty { return "" }
            // Pure filler / sub-2-character input: just return as-is, no polish.
            let stripped = trimmedAsr.unicodeScalars.filter {
                !["嗯", "啊", "呃", "哦", "唔", "诶", "。", "，", "！", "？", "."].contains(String($0))
            }
            if stripped.count < 2 {
                AppLogger.debug("Gemma4 polish 跳过过短输入: \(trimmedAsr)", category: .llm)
                return trimmedAsr
            }
        }
        let polishPrompt: String
        if let prompt {
            polishPrompt = prompt
        } else if isEditMode, let selectedText {
            polishPrompt = """
            你是一个文本编辑器。用户选中了一段文本，然后用语音给出修改指令（音频 + 粗转录）。
            严格规则：
            - 只输出修改后的文本，禁止任何解释、前言、总结
            - 禁止输出思考过程、分析步骤
            - 如果不确定如何修改，原样返回选中文本
            指令类型包括替换词语、风格改写、纠错、格式转换等。
            【选中的文本】
            \(selectedText)
            【语音指令粗转录】
            \(asrText)
            """
        } else {
            polishPrompt = """
            你听到一段音频，同时收到一份 ASR 粗转录文本。
            你的任务是输出用户【意图表达的内容】，而不是逐字转录。

            处理原则（按优先级）：
            1. 保守第一：当不确定时，保留转录原文，不要猜测改写。
               宁可漏改一处口语，也不要把对的改成错的。
            2. 去除明显的 ASR 错误：字符不自然地连续重复，输出去重后的形式。
            3. 处理明显的自我修正：当用户带"不对"、"我是说"、"应该是" 等
               修正词时，以修正后版本为准，丢弃被修正的内容。
            4. 删除口语填充词（如"嗯"、"啊"、"呃"等）。
            5. 按自然停顿加合适的中文标点。

            输出规则：
            - 直接输出最终文本，不要解释、不要加前言、不要重复任务说明。
            - 不要复述本提示中的任何示例或规则文本。
            - 使用简体中文，保留英文单词原样。

            参考转录：\(asrText)
            """
        }

        AppLogger.debug(
            "Gemma4 开始\(isEditMode ? "编辑模式" : "音频感知润色")，ASR 文本: \(asrText.prefix(50))...",
            category: .llm
        )

        let enableT2S = AppSettings.shared.gemma4EnableT2S
        let editLabel = isEditMode ? "编辑" : "润色"

        do {
            let result = try await Task.detached(priority: .userInitiated) { [audio] in
                try await Self.runGenerate(
                    context: context,
                    prompt: polishPrompt,
                    audio: audio,
                    enableT2S: enableT2S,
                    label: editLabel,
                    category: .llm
                )
            }.value
            return result
        } catch {
            AppLogger.error("Gemma4 润色失败: \(error.localizedDescription)", category: .llm)
            throw error
        }
    }

    // MARK: - 推理后台执行

    /// 推理核心：在调用方提供的 task 上下文里跑（典型场景是 detached background task）。
    ///
    /// nonisolated 意味着可以从任何 actor 上下文调用 — 但 caller 必须保证
    /// 对单个 ModelContext 的串行访问（model/cache 不是 thread-safe）。我们
    /// 通过"每次只在一个 detached task 里调用"满足这个约束。
    nonisolated private static func runGenerate(
        context: ModelContext,
        prompt: String,
        audio: [Float],
        enableT2S: Bool,
        label: String,
        category: AppLogger.Category
    ) async throws -> String {
        let startTime = CFAbsoluteTimeGetCurrent()

        var input = UserInput(prompt: prompt)
        input.audios = [audio]

        let lmInput = try await context.processor.prepare(input: input)
        eval(lmInput.text.tokens)

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

        // No more Task.yield(): we're on a background detached task, the main
        // thread is free regardless of how long this loop runs.
        for _ in 0..<500 {
            let lastLogits = logits[0..., -1, 0...]
            let nextToken = lastLogits.argMax(axis: -1).item(Int.self)
            // Stop on EOS tokens (from model's generation_config.json)
            // <eos>=1, <turn|>=106, <tool_call|>=50
            if [1, 106, 50].contains(nextToken) { break }
            outputTokens.append(nextToken)
            let nextTokenArray = MLXArray([Int32(nextToken)]).expandedDimensions(axis: 0)
            logits = model.callAsFunction(nextTokenArray, cache: cache)
            eval(logits)
        }

        let text = context.tokenizer.decode(tokens: outputTokens)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if enableT2S {
            result = Self.traditionalToSimplified(result)
        }

        AppLogger.info(
            "Gemma4 \(label)完成: \(String(format: "%.2f", elapsed))s",
            category: category
        )
        return result
    }

    // MARK: - 繁→简转换

    nonisolated private static func traditionalToSimplified(_ text: String) -> String {
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
