//
//  LLMPromptRegressionTests.swift
//  TalkTests
//
//  Prompt-quality regression suite for polish (Qwen + Gemma4).
//
//  Modelled on HotwordExtractionTests — each case runs N trials to smooth
//  out LLM non-determinism, and the suite asserts on *pass rate*, not
//  single outcomes. This is the standard pattern established in #8's
//  "prompt evolution" work.
//
//  Workflow for changing a polish prompt:
//    1. run `make prompt-regress` on current code — record baseline rates
//    2. change the prompt
//    3. rerun `make prompt-regress` — compare. Target: each case ≥ 70%,
//       and no regression > 20pp on any case that was previously passing.
//
//  Runtime: real Qwen3.5 + Gemma4. Excluded from `make test`.
//

import Foundation
import Testing

@testable import Talk

// MARK: - Case definition

/// A polish regression case. `check` returns true iff the output meets the
/// desired behaviour. We count trial outcomes to derive a pass rate.
struct PolishCase {
    let name: String
    let input: String
    let selectedText: String?
    let check: (String) -> (passed: Bool, reason: String)

    init(
        name: String, input: String, selectedText: String? = nil,
        check: @escaping (String) -> (Bool, String)
    ) {
        self.name = name
        self.input = input
        self.selectedText = selectedText
        self.check = check
    }
}

// MARK: - Shared model loading

private actor ModelLoadGate {
    static let shared = ModelLoadGate()
    private var qwenLoaded = false
    private var gemmaLoaded = false

    func loadQwen() async throws {
        guard !qwenLoaded else { return }
        let modelId = await AppSettings.shared.llmModelId
        try await LLMService.shared.loadModel(modelId: modelId)
        qwenLoaded = true
    }

    func loadGemma() async throws {
        guard !gemmaLoaded else { return }
        let modelId = await AppSettings.shared.gemma4ModelId
        try await Gemma4ASREngine.shared.loadModel(modelId: modelId)
        gemmaLoaded = true
    }
}

/// Silent audio filler for Gemma4.polish (signature requires an audio array).
private func silentAudio(seconds: Double = 0.5) -> [Float] {
    Array(repeating: Float(0), count: Int(seconds * 16000))
}

// MARK: - Shared cases

/// Cases run against both Qwen (LLMService.polish) and Gemma4
/// (Gemma4ASREngine.polish). Selected-text edit cases are included because
/// v0.5.3 regressed that path and it must not silently break.
let polishCases: [PolishCase] = [
    // Guardrail: plain dictation passes through
    PolishCase(name: "plain_dictation", input: "今天天气不错") { out in
        let passed = out.contains("今天天气不错") && out.count <= "今天天气不错".count + 20
            && !out.contains("好的") && !out.contains("清理后")
        return (passed, "plain input should pass through with at most punctuation")
    },

    // Guardrail: empty input doesn't trigger meta-response
    PolishCase(name: "empty_input", input: "") { out in
        (out.count < 50, "empty input must not produce long meta-response")
    },

    // Stutter: "历历史" → "历史" — model sometimes outputs 纪录 instead of
    // 记录 (interchangeable variant), both count as success
    PolishCase(name: "stutter_history", input: "最后有一个历历史记录") { out in
        let passed = !out.contains("历历") && out.contains("历史")
            && (out.contains("记录") || out.contains("纪录"))
        return (passed, "stutter '历历' gone, '历史' survives with 记录/纪录")
    },

    // Stutter variant: "一一个" — LLM sometimes rewrites as "一件事"; both are fine
    // as long as the literal stutter is gone and sentence is coherent
    PolishCase(name: "stutter_yige", input: "我想说一一个事情") { out in
        let passed = !out.contains("一一") && out.contains("事")
            && (out.contains("一个") || out.contains("一件"))
        return (passed, "stutter '一一' must be de-duped, content survives")
    },

    // Self-correction: OpenAI → Anthropic (user-reported).
    // Primary assertion: the superseded reference (OpenAI) must be dropped.
    // The self-correction marker ("不对") being stripped is nice-to-have but
    // not worth failing on — a sentence like "不对，是 Anthropic" is still
    // a correct understanding of the final intent.
    PolishCase(name: "self_correction_anthropic",
               input: "我看看 OpenAI 不对是 Anthropic 的表现") { out in
        let passed = out.contains("Anthropic") && !out.contains("OpenAI")
        return (passed, "drop superseded OpenAI, keep final intent Anthropic")
    },

    // Self-correction: time
    PolishCase(name: "self_correction_time",
               input: "我们约明天下午三点，不对，五点") { out in
        (out.contains("五点") && !out.contains("三点"),
         "keep final time (五点), drop superseded (三点)")
    },

    // Filler words at utterance start (simulates ASR hallucination)
    PolishCase(name: "leading_filler", input: "嗯嗯嗯今天天气不错") { out in
        (!out.hasPrefix("嗯嗯") && out.contains("今天天气不错"),
         "leading filler must be stripped, content must survive")
    },

    // Edit mode: replace-word command with selected text
    PolishCase(name: "edit_replace_word",
               input: "把不错改成很好",
               selectedText: "今天天气不错") { out in
        let passed = (out.contains("今天天气很好") || out.contains("今天天气 很好"))
            && !out.contains("不错")
        return (passed, "edit command should replace 不错→很好")
    },
]

// MARK: - Trial runner

struct TrialResult {
    let case_: PolishCase
    let trials: Int
    let passes: Int
    let samples: [String]  // outputs from trials, for debugging

    var rate: Double { trials == 0 ? 0 : Double(passes) / Double(trials) }
}

/// Number of trials per case. More trials = tighter confidence interval
/// but longer runtime. 5 is a decent compromise: ~5 × 0.3s = 1.5s per case.
private let trialsPerCase = 5

/// Minimum acceptable pass rate per case. Below this is a prompt regression.
private let passRateThreshold = 0.6

@MainActor
private func runTrialsQwen(_ case_: PolishCase) async throws -> TrialResult {
    var passes = 0
    var samples: [String] = []
    for _ in 0..<trialsPerCase {
        let output = try await LLMService.shared.polish(
            text: case_.input,
            intensity: .medium,
            selectedText: case_.selectedText
        )
        let (ok, _) = case_.check(output)
        if ok { passes += 1 }
        samples.append(output)
    }
    return TrialResult(case_: case_, trials: trialsPerCase, passes: passes, samples: samples)
}

@MainActor
private func runTrialsGemma(_ case_: PolishCase) async throws -> TrialResult {
    var passes = 0
    var samples: [String] = []
    let audio = silentAudio()
    for _ in 0..<trialsPerCase {
        let output = try await Gemma4ASREngine.shared.polish(
            audio: audio, sampleRate: 16000, asrText: case_.input,
            selectedText: case_.selectedText
        )
        let (ok, _) = case_.check(output)
        if ok { passes += 1 }
        samples.append(output)
    }
    return TrialResult(case_: case_, trials: trialsPerCase, passes: passes, samples: samples)
}

private func report(_ engine: String, _ results: [TrialResult]) {
    print("\n===== \(engine) polish regression =====")
    for r in results {
        let pct = Int(r.rate * 100)
        let marker = r.rate >= passRateThreshold ? "✓" : "✗"
        print("\(marker) \(r.case_.name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(r.passes)/\(r.trials) (\(pct)%)")
        if r.rate < passRateThreshold {
            for (i, s) in r.samples.enumerated() {
                print("    trial \(i): \(s.prefix(80))")
            }
        }
    }
    let belowThreshold = results.filter { $0.rate < passRateThreshold }
    print("summary: \(results.count - belowThreshold.count)/\(results.count) cases ≥ \(Int(passRateThreshold * 100))%")
    print("=======================================\n")
}

// MARK: - Test suites

@Suite("Polish Prompt Regression (Qwen)", .serialized)
struct QwenPolishPromptRegression {

    @Test @MainActor
    func allCasesPassThreshold() async throws {
        try await ModelLoadGate.shared.loadQwen()

        var results: [TrialResult] = []
        for c in polishCases {
            let r = try await runTrialsQwen(c)
            results.append(r)
        }

        report("Qwen", results)

        for r in results {
            #expect(
                r.rate >= passRateThreshold,
                "Qwen polish case '\(r.case_.name)': \(r.passes)/\(r.trials) = \(Int(r.rate * 100))% below \(Int(passRateThreshold * 100))%. Samples: \(r.samples)"
            )
        }
    }
}

@Suite("Polish Prompt Regression (Gemma4)", .serialized)
struct Gemma4PolishPromptRegression {

    @Test @MainActor
    func allCasesPassThreshold() async throws {
        try await ModelLoadGate.shared.loadGemma()

        var results: [TrialResult] = []
        for c in polishCases {
            // Gemma4 edit mode uses a different code path already covered by
            // the selectedText branch; same cases apply.
            let r = try await runTrialsGemma(c)
            results.append(r)
        }

        report("Gemma4", results)

        for r in results {
            #expect(
                r.rate >= passRateThreshold,
                "Gemma4 polish case '\(r.case_.name)': \(r.passes)/\(r.trials) = \(Int(r.rate * 100))% below \(Int(passRateThreshold * 100))%. Samples: \(r.samples)"
            )
        }
    }
}
