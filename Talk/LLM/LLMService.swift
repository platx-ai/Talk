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
你是一个智能文本清理助手。你的任务是对语音识别的文本进行清理和修正。

任务：
1. 去除口语填充词（如"嗯"、"啊"、"呃"、"um"、"uh"等）
2. 添加合适的标点符号
3. 理解用户的拼写说明，用正确的拼写替换原文中的错误
   - 如果有字母拼写说明（如"C-L-A-U-D-E"），找出对应的错误词并替换为正确的拼写
   - 如果有字义解释（如"仲欣就是那个重量的仲"），保留正确的写法，删除解释部分
4. 自我修正识别（识别"不对"、"其实"、"我是说"等修正词，保留最终意图）
5. 智能排版（根据语义自动分段，识别列表格式）
6. 保留原本的表达风格和语气
7. 结合对话上下文，理解专有名词和人名

示例：
- 输入："Crowdcode是怎么拼的呢？就是C-L-A-U-D-E。" → 输出："Claude是怎么拼的呢？"
- 输入："我晚上要给丁仲欣打电话。仲欣就是那个重量的重，心脏的心。" → 输出："我晚上要给丁重心打电话。"
- 输入："我们约明天下午三点，不对，五点" → 输出："我们约明天下午五点。"

请直接返回清理后的文本，不要添加任何解释或说明。如果输入的内容为空，则直接返回空字符串。
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
            if modelId.hasPrefix("/") {
                let config = ModelConfiguration(directory: URL(fileURLWithPath: modelId))
                modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config)
            } else {
                modelContainer = try await loadModelContainer(id: modelId)
            }
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

        let instructions: String
        let userMessage: String

        if let selectedText, !selectedText.isEmpty {
            // 选中修正模式：语音输入是指令，选中文本是操作对象
            instructions = """
            你是一个智能文本编辑助手。用户选中了一段文本，然后用语音给出了修改指令。

            你的任务是：
            1. 理解用户的语音指令（可能包含纠错、改写、格式转换等要求）
            2. 对选中的文本执行用户要求的操作
            3. 直接返回修改后的完整文本，不要添加任何解释

            注意：
            - 语音指令可能包含语音识别的错误，请根据上下文理解真实意图
            - 如果指令是纠正某个字词，找到对应的错误并替换
            - 如果指令是改变风格（如"变成口语"），则改写整段文本
            - 只返回修改后的文本，不要包含解释、引号或其他标记
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

        do {
            let session = ChatSession(modelContainer, instructions: instructions)
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


