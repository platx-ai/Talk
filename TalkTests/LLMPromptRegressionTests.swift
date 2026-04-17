//
//  LLMPromptRegressionTests.swift
//  TalkTests
//
//  Prompt-level regression suite for LLMService.polish (Qwen) and
//  Gemma4ASREngine.polish (Gemma4 as LLM).
//
//  Purpose: guard the default system prompts. Any change to the polish
//  instructions MUST keep these passing. New desired behaviour (e.g. strip
//  stutter, honour self-corrections) is added by (a) extending the prompt,
//  (b) adding the expectation here. Release must not ship on red.
//
//  Runtime: real models. Excluded from `make test`; run via `make prompt-regress`.
//
//  Assertions are deliberately lenient — LLM output varies between runs.
//  We assert on observable *symptoms* (contains / not-contains / length
//  bounds) rather than exact string equality.
//

import Foundation
import Testing

@testable import Talk

// MARK: - Shared loading

private actor ModelLoadGate {
    static let shared = ModelLoadGate()
    private var qwenLoaded = false
    private var gemmaLoaded = false

    func loadQwen() async throws {
        guard !qwenLoaded else { return }
        let settings = await AppSettings.shared
        let modelId = await settings.llmModelId
        try await LLMService.shared.loadModel(modelId: modelId)
        qwenLoaded = true
    }

    func loadGemma() async throws {
        guard !gemmaLoaded else { return }
        let settings = await AppSettings.shared
        let modelId = await settings.gemma4ModelId
        try await Gemma4ASREngine.shared.loadModel(modelId: modelId)
        gemmaLoaded = true
    }
}

// MARK: - Helpers

private func normalised(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: " ", with: "")
        .lowercased()
}

/// Silent 16kHz audio filler — Gemma4.polish requires an audio input.
/// For text-level regression we feed 500ms of silence; the polish path
/// exercises the same decode loop regardless.
private func silentAudio(seconds: Double = 0.5, sampleRate: Int = 16000) -> [Float] {
    Array(repeating: Float(0), count: Int(seconds * Double(sampleRate)))
}

// MARK: - Qwen3.5 regression suite

@Suite("LLM Prompt Regression (Qwen)", .serialized)
struct QwenPromptRegressionTests {

    // --- Guardrails: must-hold invariants ---

    @Test @MainActor
    func plainDictationStaysPlain() async throws {
        try await ModelLoadGate.shared.loadQwen()
        let input = "今天天气不错"
        let output = try await LLMService.shared.polish(text: input, intensity: .medium)
        let norm = normalised(output)
        #expect(norm.contains("今天天气不错"),
                "plain input should pass through with at most punctuation added, got: \(output)")
        #expect(output.count <= input.count + 20,
                "output grew unexpectedly (\(output.count) vs \(input.count)): \(output)")
        #expect(!output.contains("好的"), "must not emit conversational filler: \(output)")
        #expect(!output.contains("清理后"), "must not emit meta-response: \(output)")
    }

    @Test @MainActor
    func emptyInputReturnsSomething() async throws {
        // A safety net: empty/whitespace must not throw or emit a meta-response.
        try await ModelLoadGate.shared.loadQwen()
        let output = try await LLMService.shared.polish(text: "", intensity: .medium)
        #expect(output.count < 50, "empty input should not trigger a long response: \(output)")
    }

    // --- Desired behaviours (current or target) ---

    @Test @MainActor
    func stutterStrip_historyRecord() async throws {
        // Observed user bug: ASR output "最后有一个历历史记录" is passed through verbatim.
        // Desired: polish should de-duplicate the stutter.
        try await ModelLoadGate.shared.loadQwen()
        let input = "最后有一个历历史记录"
        let output = try await LLMService.shared.polish(text: input, intensity: .medium)
        #expect(!output.contains("历历"),
                "stutter '历历' must be de-duplicated, got: \(output)")
        #expect(output.contains("历史记录"),
                "final intent must survive, got: \(output)")
    }

    @Test @MainActor
    func selfCorrection_anthropic() async throws {
        // Observed user bug: "我看看 OpenAI 不对是 Anthropic 的表现" should become
        // "我看看 Anthropic 的表现"
        try await ModelLoadGate.shared.loadQwen()
        let input = "我看看 OpenAI 不对是 Anthropic 的表现"
        let output = try await LLMService.shared.polish(text: input, intensity: .medium)
        #expect(output.contains("Anthropic"), "final intent lost, got: \(output)")
        #expect(!output.contains("OpenAI"),
                "superseded reference must be dropped, got: \(output)")
        #expect(!output.contains("不对"),
                "self-correction marker must be consumed, got: \(output)")
    }

    @Test @MainActor
    func selfCorrection_time() async throws {
        // Already called out in the default prompt example — regression guard.
        try await ModelLoadGate.shared.loadQwen()
        let input = "我们约明天下午三点，不对，五点"
        let output = try await LLMService.shared.polish(text: input, intensity: .medium)
        #expect(output.contains("五点"), "final intent lost, got: \(output)")
        #expect(!output.contains("三点"),
                "superseded time must be dropped, got: \(output)")
    }

    @Test @MainActor
    func fillerWord_stripped() async throws {
        try await ModelLoadGate.shared.loadQwen()
        // "嗯嗯嗯今天天气不错" — leading stream-hallucination style filler.
        let input = "嗯嗯嗯今天天气不错"
        let output = try await LLMService.shared.polish(text: input, intensity: .medium)
        #expect(!output.hasPrefix("嗯嗯"),
                "leading filler must be removed, got: \(output)")
        #expect(output.contains("今天天气不错"),
                "content must survive, got: \(output)")
    }

    @Test @MainActor
    func editMode_replaceWord() async throws {
        // Regression for v0.5.3 fix: selectedText + voice command = edit, not dictate.
        try await ModelLoadGate.shared.loadQwen()
        let selected = "今天天气不错"
        let command = "把不错改成很好"
        let output = try await LLMService.shared.polish(
            text: command, intensity: .medium, selectedText: selected
        )
        #expect(output.contains("今天天气很好") || output.contains("今天天气 很好"),
                "edit command should replace, got: \(output)")
        #expect(!output.contains("不错"),
                "old word should be gone, got: \(output)")
    }
}

// MARK: - Gemma4 regression suite

@Suite("LLM Prompt Regression (Gemma4)", .serialized)
struct Gemma4PromptRegressionTests {

    // Gemma4.polish signature: audio + asrText → polished text.
    // We feed short silence + realistic ASR text.

    @Test @MainActor
    func plainDictationStaysPlain_gemma() async throws {
        try await ModelLoadGate.shared.loadGemma()
        let input = "今天天气不错"
        let audio = silentAudio()
        let output = try await Gemma4ASREngine.shared.polish(
            audio: audio, sampleRate: 16000, asrText: input
        )
        #expect(output.contains("今天天气不错"),
                "plain input should pass through, got: \(output)")
        #expect(output.count <= input.count + 20,
                "output grew unexpectedly: \(output)")
    }

    @Test @MainActor
    func stutterStrip_historyRecord_gemma() async throws {
        try await ModelLoadGate.shared.loadGemma()
        let input = "最后有一个历历史记录"
        let audio = silentAudio()
        let output = try await Gemma4ASREngine.shared.polish(
            audio: audio, sampleRate: 16000, asrText: input
        )
        #expect(!output.contains("历历"),
                "stutter must be removed, got: \(output)")
        #expect(output.contains("历史记录"),
                "final intent lost, got: \(output)")
    }

    @Test @MainActor
    func selfCorrection_anthropic_gemma() async throws {
        try await ModelLoadGate.shared.loadGemma()
        let input = "我看看 OpenAI 不对是 Anthropic 的表现"
        let audio = silentAudio()
        let output = try await Gemma4ASREngine.shared.polish(
            audio: audio, sampleRate: 16000, asrText: input
        )
        #expect(output.contains("Anthropic"), "final intent lost, got: \(output)")
        #expect(!output.contains("OpenAI"),
                "superseded reference must be dropped, got: \(output)")
    }

    @Test @MainActor
    func editMode_gemma() async throws {
        // Regression for v0.5.3 fix: Gemma4.polish with selectedText.
        try await ModelLoadGate.shared.loadGemma()
        let selected = "今天天气不错"
        let command = "把不错改成很好"
        let audio = silentAudio()
        let output = try await Gemma4ASREngine.shared.polish(
            audio: audio, sampleRate: 16000, asrText: command, selectedText: selected
        )
        #expect(output.contains("今天天气很好") || output.contains("今天天气 很好"),
                "edit command should replace, got: \(output)")
    }
}
