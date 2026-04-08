//
//  LLMStripThinkingTests.swift
//  TalkTests
//
//  stripThinkingBlock 后处理测试
//

import Testing
import Foundation
@testable import Talk

@Suite("LLM Strip Thinking Block Tests")
struct LLMStripThinkingTests {

    @Test
    func stripXMLThinkBlock() {
        let input = "<think>\nI need to clean this text.\n</think>\n\n你好世界。"
        let result = LLMService.stripThinkingBlock(input)
        #expect(result == "你好世界。")
    }

    @Test
    func stripEmptyThinkBlock() {
        let input = "<think>\n\n</think>\n\n你好世界。"
        let result = LLMService.stripThinkingBlock(input)
        #expect(result == "你好世界。")
    }

    @Test
    func stripThinkingProcessText() {
        let input = """
        Thinking Process:

        1. **Analyze the Request:**
           * Role: Text Cleaning Assistant
           * Task: Remove filler words

        2. **Output:**
           The cleaned text.
        """
        let result = LLMService.stripThinkingBlock(input)
        // Should extract content after "Output:"
        #expect(result.contains("cleaned text"))
        #expect(!result.contains("Thinking Process"))
    }

    @Test
    func stripThinkingProcessNoOutput() {
        // When the entire response is thinking with no useful output
        let input = """
        Thinking Process:

        1. Analyze the request
        2. The sentence is fine as is
        """
        let result = LLMService.stripThinkingBlock(input)
        #expect(result.isEmpty)
    }

    @Test
    func noThinkingBlockPassthrough() {
        let input = "你好世界。"
        let result = LLMService.stripThinkingBlock(input)
        #expect(result == "你好世界。")
    }

    @Test
    func stripOrphanedTags() {
        let input = "<think>some thinking你好世界。"
        let result = LLMService.stripThinkingBlock(input)
        #expect(result == "some thinking你好世界。")
    }

    @Test
    func contentBeforeThinkingProcess() {
        let input = "你好世界。\nThinking Process:\n1. analysis"
        let result = LLMService.stripThinkingBlock(input)
        #expect(result == "你好世界。")
    }
}
