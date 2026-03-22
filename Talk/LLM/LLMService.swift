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
    private var conversationHistory: [(role: String, content: String)] = []
    private var maxHistoryRounds: Int = 5
    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress: Double = 0

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
        conversationHistory = []
        isModelLoaded = false
        AppLogger.info("LLM 模型已卸载", category: .llm)
    }

    // MARK: - 文本润色

    func polish(text: String, intensity: AppSettings.PolishIntensity, customPrompt: String? = nil, selectedText: String? = nil) async throws -> String {
        guard isModelLoaded else {
            AppLogger.error("LLM 模型未加载", category: .llm)
            throw LLMError.modelNotLoaded
        }

        guard let modelContainer = modelContainer else {
            AppLogger.error("LLM 模型为空", category: .llm)
            throw LLMError.modelNotLoaded
        }

        AppLogger.debug("开始文本润色: \(text)", category: .llm)

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
            // 选中修正模式：语音输入是指令，选中文本是操作对象
            instructions = """
            你是一个文本编辑器。用户选中了一段文本，然后用语音给出修改指令。

            【严格规则】
            - 你的输出会直接替换用户选中的文本，所以只能输出修改后的文本本身
            - 禁止输出任何解释、说明、前言、总结、引号、标签
            - 禁止输出"好的"、"已修改"、"按照要求"等回应性语句
            - 如果不确定如何修改，原样返回选中文本

            【理解语音指令】
            - 语音指令经过 ASR 识别，可能有听错的词，请根据上下文推断真实意图
            - 常见 ASR 错误：技术术语容易被听错（如 "LLM" 可能被识别为 "la laam"）
            - 纠错指令：找到目标字词并替换（如"把X改成Y"）
            - 改写指令：按要求改变整段文本的风格或格式
            """
            userMessage = "选中的文本：\n\(selectedText)\n\n语音指令：\(text)"
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
            // 限制最大生成 token 数，防止短输入触发无限生成
            // 润色输出不应超过输入的 3 倍长度，最少 200 tokens，最多 1024 tokens
            let inputLength = text.count + (selectedText?.count ?? 0)
            let maxTokens = min(1024, max(200, inputLength * 3))
            let params = GenerateParameters(maxTokens: maxTokens)
            let session = ChatSession(modelContainer, instructions: instructions, generateParameters: params)
            let response = try await session.respond(to: userMessage)

            let polishedText = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            conversationHistory.append(("user", text))
            conversationHistory.append(("assistant", polishedText))

            while conversationHistory.count > maxHistoryRounds * 2 {
                conversationHistory.removeFirst()
            }

            AppLogger.debug("文本润色完成: \(polishedText)", category: .llm)
            return polishedText
        } catch {
            AppLogger.error("文本润色失败: \(error.localizedDescription)", category: .llm)
            throw LLMError.polishFailed(error)
        }
    }

    // MARK: - 历史管理

    func setMaxHistoryRounds(_ rounds: Int) {
        maxHistoryRounds = rounds
        AppLogger.info("设置对话历史最大轮数为 \(rounds)", category: .llm)
    }

    func clearHistory() {
        conversationHistory = []
        AppLogger.info("已清空对话历史", category: .llm)
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


