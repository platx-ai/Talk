//
//  LLMPromptRegressionTests.swift
//  TalkTests
//
//  Polish prompt regression — drives the polish path with REAL audio
//  fixtures captured from user history, with hand-curated ground truth
//  (must-contain / must-not-contain assertions).
//
//  Audio fixtures live in TalkTests/Fixtures/PolishAudio/, definitions
//  in TalkTests/Fixtures/polish_cases.json.
//
//  Adding a new case:
//    1. In Talk's history view, edit a polished result to ground truth.
//    2. Find the .m4a in ~/Library/Application Support/Talk/audio/.
//    3. Copy to TalkTests/Fixtures/PolishAudio/<case_name>.m4a.
//    4. Add an entry to polish_cases.json with must_contain/must_not_contain.
//
//  Workflow when changing a polish prompt:
//    `make prompt-regress` → record per-case pass rates → tune → repeat.
//

import AVFoundation
import Foundation
import Testing

@testable import Talk

// MARK: - Case loading

struct AudioPolishCase: Decodable {
    let name: String
    let audioFixture: String
    let rawText: String
    let groundTruthPolished: String
    let mustContain: [String]
    let mustNotContain: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case audioFixture = "audio_fixture"
        case rawText = "raw_text"
        case groundTruthPolished = "ground_truth_polished"
        case mustContain = "must_contain"
        case mustNotContain = "must_not_contain"
    }

    func check(_ output: String) -> (passed: Bool, reason: String) {
        for token in mustContain where !output.contains(token) {
            return (false, "missing required token '\(token)'")
        }
        for token in mustNotContain where output.contains(token) {
            return (false, "contains forbidden token '\(token)'")
        }
        return (true, "")
    }
}

private final class TestBundleAnchor {}

private func loadCases() throws -> [AudioPolishCase] {
    let bundle = Bundle(for: TestBundleAnchor.self)
    guard let url = bundle.url(forResource: "polish_cases", withExtension: "json") else {
        throw NSError(
            domain: "LLMPromptRegressionTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "polish_cases.json not in test bundle"])
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([AudioPolishCase].self, from: data)
}

// MARK: - Audio loading

/// Decode a fixture .m4a into 16kHz mono Float samples.
/// Returns nil if the file cannot be read.
private func loadFixtureAudio(_ filename: String) throws -> [Float] {
    let bundle = Bundle(for: TestBundleAnchor.self)
    let basename = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    guard let url = bundle.url(forResource: basename, withExtension: ext) else {
        throw NSError(
            domain: "LLMPromptRegressionTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "fixture \(filename) not in test bundle"])
    }
    let file = try AVAudioFile(forReading: url)
    let nativeFormat = file.processingFormat

    guard
        let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: nativeFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )
    else {
        return []
    }
    try file.read(into: pcmBuffer)

    // Convert to 16kHz mono Float
    let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!
    guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
        return []
    }
    let outputCapacity = AVAudioFrameCount(
        Double(pcmBuffer.frameLength) * (16000.0 / nativeFormat.sampleRate) + 1024
    )
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity)
    else { return [] }

    var error: NSError?
    var bufferConsumed = false
    converter.convert(to: outputBuffer, error: &error) { _, status in
        if bufferConsumed {
            status.pointee = .endOfStream
            return nil
        }
        bufferConsumed = true
        status.pointee = .haveData
        return pcmBuffer
    }
    if let error { throw error }

    let count = Int(outputBuffer.frameLength)
    let ptr = outputBuffer.floatChannelData![0]
    return Array(UnsafeBufferPointer(start: ptr, count: count))
}

// MARK: - Model loading

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

// MARK: - Trial runner

private struct TrialResult {
    let caseName: String
    let trials: Int
    let passes: Int
    let samples: [String]
    var rate: Double { trials == 0 ? 0 : Double(passes) / Double(trials) }
}

private let trialsPerCase = 3
private let passRateThreshold = 0.66  // 2/3

@MainActor
private func runQwen(_ c: AudioPolishCase) async throws -> TrialResult {
    var passes = 0
    var samples: [String] = []
    for _ in 0..<trialsPerCase {
        let out = try await LLMService.shared.polish(text: c.rawText, intensity: .medium)
        if c.check(out).passed { passes += 1 }
        samples.append(out)
    }
    return TrialResult(caseName: c.name, trials: trialsPerCase, passes: passes, samples: samples)
}

@MainActor
private func runGemma(_ c: AudioPolishCase) async throws -> TrialResult {
    let audio = try loadFixtureAudio(c.audioFixture)
    var passes = 0
    var samples: [String] = []
    for _ in 0..<trialsPerCase {
        let out = try await Gemma4ASREngine.shared.polish(
            audio: audio, sampleRate: 16000, asrText: c.rawText
        )
        if c.check(out).passed { passes += 1 }
        samples.append(out)
    }
    return TrialResult(caseName: c.name, trials: trialsPerCase, passes: passes, samples: samples)
}

// MARK: - Suites

@Suite("Polish Prompt Regression (Qwen)", .serialized)
struct QwenPolishPromptRegression {

    @Test @MainActor
    func allCasesPassThreshold() async throws {
        try await ModelLoadGate.shared.loadQwen()
        let cases = try loadCases()
        var results: [TrialResult] = []
        for c in cases {
            results.append(try await runQwen(c))
        }
        for r in results {
            #expect(
                r.rate >= passRateThreshold,
                "Qwen '\(r.caseName)' \(r.passes)/\(r.trials) (\(Int(r.rate * 100))%) below threshold. Samples: \(r.samples)"
            )
        }
    }
}

@Suite("Polish Prompt Regression (Gemma4)", .serialized)
struct Gemma4PolishPromptRegression {

    @Test @MainActor
    func allCasesPassThreshold() async throws {
        try await ModelLoadGate.shared.loadGemma()
        let cases = try loadCases()
        var results: [TrialResult] = []
        for c in cases {
            results.append(try await runGemma(c))
        }
        for r in results {
            #expect(
                r.rate >= passRateThreshold,
                "Gemma4 '\(r.caseName)' \(r.passes)/\(r.trials) (\(Int(r.rate * 100))%) below threshold. Samples: \(r.samples)"
            )
        }
    }
}
