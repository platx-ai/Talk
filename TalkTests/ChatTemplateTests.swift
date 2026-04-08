//
//  ChatTemplateTests.swift
//  TalkTests
//
//  验证 Qwen3.5 chat template 中 enable_thinking=false 是否正确生效
//

import Testing
import Foundation
import Tokenizers
import Hub

@Suite("Chat Template Tests")
struct ChatTemplateTests {

    @Test
    func qwen35EnableThinkingFalse() async throws {
        let modelId = "mlx-community/Qwen3.5-4B-OptiQ-4bit"
        let hub = HubApi()
        let config = LanguageModelConfigurationFromHub(modelName: modelId, hubApi: hub)

        guard let tokenizerConfig = try await config.tokenizerConfig else {
            Issue.record("No tokenizer config found")
            return
        }
        let tokenizerData = try await config.tokenizerData

        let tokenizer = try PreTrainedTokenizer(
            tokenizerConfig: tokenizerConfig, tokenizerData: tokenizerData)

        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a text cleaner."],
            ["role": "user", "content": "Clean: hello"],
        ]

        // Without enable_thinking (default = thinking ON)
        let tokensDefault = try tokenizer.applyChatTemplate(messages: messages)
        let decodedDefault = tokenizer.decode(tokens: tokensDefault)

        // With enable_thinking=false
        let tokensNoThink = try tokenizer.applyChatTemplate(
            messages: messages,
            additionalContext: ["enable_thinking": false]
        )
        let decodedNoThink = tokenizer.decode(tokens: tokensNoThink)

        print("DEFAULT last 60: \(decodedDefault.suffix(60))")
        print("NOTHINK last 60: \(decodedNoThink.suffix(60))")

        // Default should end with <think>\n (open thinking)
        #expect(decodedDefault.hasSuffix("<think>\n"))

        // NoThink should end with </think>\n\n (closed thinking block)
        #expect(decodedNoThink.contains("<think>\n\n</think>"))

        // NoThink should have MORE tokens (the closing </think> tag)
        #expect(tokensNoThink.count > tokensDefault.count)
    }
}
