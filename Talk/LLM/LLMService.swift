//
//  LLMService.swift
//  Talk
//
//  LLM 服务 - 文本润色
//

import Foundation
import MLXLLM
import MLXLMCommon

/// LLM 服务
@Observable
@MainActor
final class LLMService {
    // MARK: - 单例

    @MainActor static let shared = LLMService()

    // MARK: - 属性

    private var modelContainer: ModelContainer?
    private var maxHistoryRounds: Int = 5
    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress: Double = 0
    /// 是否正在执行润色（供 EditObserver 判断是否空闲）
    private(set) var isPolishing = false

    /// Per-app ChatSession 缓存 — 复用 KV Cache 加速推理
    /// key = bundleId (nil 用 "__global__")
    private var appSessions: [String: ChatSession] = [:]
    /// 每个 app 的对话轮数计数
    private var appRoundCounts: [String: Int] = [:]

    // MARK: - 系统提示词

    static let defaultSystemPrompt = """
你是一个文本清理器。你的输出会直接替换用户的原始文本。

【严格规则】
- 只输出清理后的文本，禁止输出任何解释、说明、前言
- 禁止输出"好的"、"已修改"、"清理后的文本如下"等回应性语句
- 如果输入为空，返回空字符串

【清理任务】
1. 去除口语填充词（嗯、啊、呃、um、uh 等）
2. 添加合适的标点符号
3. 理解拼写说明并修正（"C-L-A-U-D-E" → Claude）
4. 理解字义解释并修正（"仲欣就是那个重量的重" → 保留正确写法，删除解释）
5. 识别自我修正（"不对"、"其实"、"我是说" → 保留最终意图）
6. 智能排版（自动分段，识别列表）
7. 保留原文的表达风格和语气
8. 结合上下文理解专有名词（技术术语 ASR 容易听错，如 "la laam" → "LLM"）

【示例】
输入："我们约明天下午三点，不对，五点" → 输出："我们约明天下午五点。"
输入："Crowdcode是怎么拼的呢？就是C-L-A-U-D-E。" → 输出："Claude是怎么拼的呢？"
"""

    static let defaultEditPrompt = """
你是一个文本编辑器。用户选中了一段文本，然后用语音给出修改指令。

【严格规则】
- 你的输出会直接替换用户选中的文本
- 只输出修改后的文本，禁止任何解释、前言、总结
- 如果不确定如何修改，原样返回选中文本

【指令类型和示例】

1. 替换词语："把X改成Y" / "X替换成Y" / "把SQL改成SKILL"
   → 只替换指定的词，其他内容不变

2. 风格改写："变成口语" / "改成正式" / "转成Markdown"
   → 改写整段文本的风格或格式，保留核心含义

3. 纠错："把错别字改了" / "修正语法"
   → 只修正错误，不改变表达

4. 格式转换："变成列表" / "加上标题" / "转成代码注释"
   → 改变文本的排版格式

【注意】
- 语音指令经过 ASR，可能有听错（如 "SKILL" 听成 "思考"）
- 根据上下文推断用户真实意图
- 替换指令只改指定的词，不要重写整段文本
"""

    private func getPolishPrompt(intensity: AppSettings.PolishIntensity) -> String {
        switch intensity {
        case .light:
            return "\n【轻度润色】仅去除明显的填充词和基本标点，保持原文风格。"
        case .medium:
            return "\n【中度润色】去除填充词、添加标点、修正拼写、基本排版。"
        case .strong:
            return "\n【强度润色】完整清理所有问题，包括填充词、标点、拼写、自我修正、智能排版等。"
        }
    }

    private init() {}

    // MARK: - 模型管理

    func loadModel(modelId: String) async throws {
        guard !isModelLoaded else {
            AppLogger.info("LLM 模型已加载", category: .llm)
            return
        }
        guard !isLoading else {
            AppLogger.info("LLM 模型正在加载中，等待完成", category: .llm)
            while isLoading { try await Task.sleep(for: .milliseconds(200)) }
            return
        }

        if let reason = MLXRuntimeValidator.missingMetalLibraryReason() {
            AppLogger.error("LLM 运行时检查失败: \(reason)", category: .llm)
            throw LLMError.runtimeUnavailable(reason)
        }

        isLoading = true
        loadingProgress = 0

        AppLogger.info("开始加载 LLM 模型: \(modelId)", category: .llm)

        do {
            // 在后台线程加载模型，避免阻塞主线程/UI
            let container: ModelContainer = try await Task.detached(priority: .userInitiated) {
                if modelId.hasPrefix("/") {
                    let config = ModelConfiguration(directory: URL(fileURLWithPath: modelId))
                    return try await LLMModelFactory.shared.loadContainer(configuration: config)
                } else {
                    return try await loadModelContainer(id: modelId)
                }
            }.value

            modelContainer = container
            isModelLoaded = true
            loadingProgress = 1.0
            isLoading = false

            AppLogger.info("LLM 模型加载成功", category: .llm)
        } catch {
            isLoading = false
            AppLogger.error("LLM 模型加载失败: \(error.localizedDescription)", category: .llm)
            throw LLMError.modelLoadFailed(error)
        }
    }

    func unloadModel() {
        modelContainer = nil
        appSessions.removeAll()
        appRoundCounts.removeAll()
        isModelLoaded = false
        AppLogger.info("LLM 模型已卸载", category: .llm)
    }

    // MARK: - 文本润色

    func polish(text: String, intensity: AppSettings.PolishIntensity, customPrompt: String? = nil, customEditPrompt: String? = nil, selectedText: String? = nil, appBundleId: String? = nil) async throws -> String {
        guard isModelLoaded else {
            AppLogger.error("LLM 模型未加载", category: .llm)
            throw LLMError.modelNotLoaded
        }

        guard let modelContainer = modelContainer else {
            AppLogger.error("LLM 模型为空", category: .llm)
            throw LLMError.modelNotLoaded
        }

        AppLogger.debug("开始文本润色: \(text)", category: .llm)
        isPolishing = true
        defer { isPolishing = false }

        var instructions: String
        let userMessage: String

        // Get learned corrections for LLM context
        let corrections = VocabularyManager.shared.getHighFrequencyItems(limit: 20)
        var correctionContext = ""
        if !corrections.isEmpty {
            let correctionLines = corrections.map { "\($0.word) → \($0.correctedForm ?? $0.word)" }.joined(separator: "\n")
            correctionContext = "\n\n【已学习的纠正】\n" + correctionLines
        }

        if let selectedText, !selectedText.isEmpty {
            // 选中编辑模式：用户自定义编辑提示词优先
            if let customEditPrompt, !customEditPrompt.isEmpty {
                instructions = customEditPrompt
            } else {
                instructions = Self.defaultEditPrompt
            }
            userMessage = "【选中的文本】\n\(selectedText)\n\n【语音指令】\n\(text)"
        } else {
            // 普通润色模式
            if let customPrompt, !customPrompt.isEmpty {
                instructions = customPrompt
            } else {
                instructions = Self.defaultSystemPrompt
            }
            var msg = ""
            if customPrompt == nil || customPrompt?.isEmpty == true {
                msg += getPolishPrompt(intensity: intensity)
            }
            msg += "\n\n请清理以下文本：\(text)"
            userMessage = msg
        }

        // Append learned corrections to instructions
        if !correctionContext.isEmpty {
            instructions += correctionContext
        }

        do {
            let inputLength = text.count + (selectedText?.count ?? 0)
            let maxTokens = min(1024, max(200, inputLength * 3))
            let params = GenerateParameters(maxTokens: maxTokens)

            let sessionKey = appBundleId ?? "__global__"

            // 获取或创建 per-app ChatSession（复用 KV Cache）
            let session: ChatSession
            if let existing = appSessions[sessionKey],
               existing.instructions == instructions {
                // 复用已有 session — KV Cache 中已有之前对话的 token
                session = existing
                session.generateParameters = params
                AppLogger.debug("复用 ChatSession (app=\(sessionKey), rounds=\(appRoundCounts[sessionKey] ?? 0))", category: .llm)
            } else {
                // 新 session 或 instructions 变了（提示词切换）
                session = ChatSession(modelContainer, instructions: instructions, generateParameters: params)
                appSessions[sessionKey] = session
                appRoundCounts[sessionKey] = 0
                AppLogger.debug("新建 ChatSession (app=\(sessionKey))", category: .llm)
            }

            let startTime = CFAbsoluteTimeGetCurrent()
            let response = try await session.respond(to: userMessage)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            let polishedText = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // 更新轮数计数
            let rounds = (appRoundCounts[sessionKey] ?? 0) + 1
            appRoundCounts[sessionKey] = rounds

            // 超过 maxHistoryRounds 时重置 session（防止 KV Cache 无限增长）
            if rounds >= maxHistoryRounds {
                appSessions.removeValue(forKey: sessionKey)
                appRoundCounts.removeValue(forKey: sessionKey)
                AppLogger.info("ChatSession 已重置 (app=\(sessionKey), 达到 \(maxHistoryRounds) 轮上限)", category: .llm)
            }

            AppLogger.info("润色完成: \(String(format: "%.2f", elapsed))s, app=\(sessionKey), round=\(rounds)", category: .llm)

            AppLogger.debug("文本润色完成: \(polishedText)", category: .llm)
            return polishedText
        } catch {
            AppLogger.error("文本润色失败: \(error.localizedDescription)", category: .llm)
            throw LLMError.polishFailed(error)
        }
    }

    // MARK: - 热词提取

    /// 热词修正结构
    struct HotwordCorrection: Codable {
        let original: String
        let corrected: String
        let type: String  // "proper_noun" | "homophone" | "abbreviation"
    }

    private static let hotwordExtractionPrompt = """
你是一个热词提取器。给定语音识别的原始输出和用户的修正版本，提取出属于 ASR 误识别导致的词语修正。

只提取以下类型：
1. 专有名词拼写错误（公司名、产品名、人名、技术术语）
2. ASR 同音字/近音字错误
3. 缩写/术语识别错误

不要提取：
- 语法润色、删减口语词、调整语序
- 标点变化
- 纯粹的措辞偏好改写

返回 JSON 数组，无修正则返回 []。每个元素包含 original、corrected、type 三个字段。
type 取值: proper_noun, homophone, abbreviation
"""

    /// 从用户编辑中提取热词修正（后台空闲时调用）
    func extractHotwords(original: String, edited: String) async -> [HotwordCorrection] {
        guard isModelLoaded, let modelContainer = modelContainer else {
            return []
        }

        let sessionKey = "__hotword_extraction__"
        let instructions = Self.hotwordExtractionPrompt
        let userMessage = "【原始文本】\n\(original)\n\n【用户修改后】\n\(edited)"

        do {
            let maxTokens = 512
            let params = GenerateParameters(maxTokens: maxTokens)

            // 每次创建新 session（热词提取是独立任务，不需要历史上下文）
            let session = ChatSession(modelContainer, instructions: instructions, generateParameters: params)

            let startTime = CFAbsoluteTimeGetCurrent()
            let response = try await session.respond(to: userMessage)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            AppLogger.info("热词提取完成: \(String(format: "%.2f", elapsed))s", category: .llm)

            // 解析 JSON
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return parseHotwordJSON(trimmed)
        } catch {
            AppLogger.error("热词提取失败: \(error.localizedDescription)", category: .llm)
            return []
        }
    }

    /// 解析 LLM 返回的 JSON，容错处理
    private func parseHotwordJSON(_ text: String) -> [HotwordCorrection] {
        // 尝试从文本中提取 JSON 数组部分
        var jsonString = text
        if let start = text.firstIndex(of: "["),
           let end = text.lastIndex(of: "]") {
            jsonString = String(text[start...end])
        }

        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let corrections = try JSONDecoder().decode([HotwordCorrection].self, from: data)
            // 过滤：长度合理、非空、不完全相同
            return corrections.filter { c in
                !c.original.isEmpty &&
                !c.corrected.isEmpty &&
                c.original != c.corrected &&
                c.original.count <= 30 &&
                c.corrected.count <= 30
            }
        } catch {
            AppLogger.debug("热词 JSON 解析失败: \(error.localizedDescription), raw=\(text.prefix(100))", category: .llm)
            return []
        }
    }

    // MARK: - 历史管理

    func setMaxHistoryRounds(_ rounds: Int) {
        maxHistoryRounds = rounds
        AppLogger.info("设置对话历史最大轮数为 \(rounds)", category: .llm)
    }

    func clearHistory() {
        appSessions.removeAll()
        appRoundCounts.removeAll()
        AppLogger.info("已清空所有 app 对话历史和 KV Cache", category: .llm)
    }

    /// 清除特定 app 的对话历史
    func clearHistory(forApp bundleId: String) {
        appSessions.removeValue(forKey: bundleId)
        appRoundCounts.removeValue(forKey: bundleId)
        AppLogger.info("已清空 \(bundleId) 的对话历史", category: .llm)
    }
}

// MARK: - LLM 错误

enum LLMError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(any Error)
    case polishFailed(any Error)
    case invalidResponse
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "LLM 模型未加载"
        case .modelLoadFailed(let error):
            return "模型加载失败: \(error.localizedDescription)"
        case .polishFailed(let error):
            return "文本润色失败: \(error.localizedDescription)"
        case .invalidResponse:
            return "模型返回了无效的响应"
        case .runtimeUnavailable(let reason):
            return "LLM 运行环境不可用: \(reason)"
        }
    }
}


