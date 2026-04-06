//
//  ASRHotwordTests.swift
//  TalkTests
//
//  End-to-end tests for ASR hotword/initialPrompt feature.
//  Compares recognition accuracy with and without hotword hints.
//
//  Run with: make benchmark
//

import Testing
import Foundation
@testable import Talk

// MARK: - Test Audio Loader

private func loadTestAudio(_ filename: String) -> [Float]? {
    // Look relative to source file
    let srcDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let url = srcDir.appendingPathComponent("TestAudio/\(filename).wav")
    guard FileManager.default.fileExists(atPath: url.path) else {
        NSLog("HOTWORD_TEST: Audio file not found: \(url.path)")
        return nil
    }
    guard let data = try? Data(contentsOf: url) else { return nil }
    // Skip 44-byte WAV header, read 16-bit mono PCM samples
    guard data.count > 44 else { return nil }
    let pcmData = data.advanced(by: 44)
    let sampleCount = pcmData.count / 2
    var samples = [Float](repeating: 0, count: sampleCount)
    pcmData.withUnsafeBytes { raw in
        let int16Ptr = raw.bindMemory(to: Int16.self)
        for i in 0..<sampleCount {
            samples[i] = Float(int16Ptr[i]) / 32768.0
        }
    }
    return samples
}

// MARK: - ASR Hotword Tests

@Suite("ASR Hotword Tests")
struct ASRHotwordTests {

    struct TestCase {
        let audioFile: String
        let expectedKeywords: [String]
        let hotwords: String
        let description: String
    }

    static let testCases: [TestCase] = [
        TestCase(
            audioFile: "en_claude_code",
            expectedKeywords: ["Claude", "Code"],
            hotwords: "Claude Code, Claude, Anthropic. ",
            description: "English: 'Claude Code'"
        ),
        TestCase(
            audioFile: "en_anthropic",
            expectedKeywords: ["Anthropic", "Claude"],
            hotwords: "Anthropic, Claude. ",
            description: "English: 'Anthropic' and 'Claude'"
        ),
        TestCase(
            audioFile: "en_technical",
            expectedKeywords: ["LLM", "Apple", "Silicon", "MLX"],
            hotwords: "LLM, Apple Silicon, MLX. ",
            description: "English: technical terms"
        ),
        TestCase(
            audioFile: "zh_claude",
            expectedKeywords: ["Claude"],
            hotwords: "Claude Code, Claude. ",
            description: "Chinese: 'Claude Code'"
        ),
    ]

    @Test @MainActor
    func asrWithAndWithoutHotwords() async throws {
        let asr = ASRService.shared
        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }

        var results: [(desc: String, baseline: String, withHotwords: String, baselineHits: Int, hotwordHits: Int)] = []

        for tc in Self.testCases {
            guard let audio = loadTestAudio(tc.audioFile) else {
                Issue.record("Missing test audio: \(tc.audioFile).wav")
                continue
            }

            // Baseline: no initialPrompt
            let baselineText = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: nil)

            // With hotwords
            var hotwordText = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: tc.hotwords)
            // Strip the hotword prefix if model echoed it
            if hotwordText.hasPrefix(tc.hotwords.trimmingCharacters(in: .whitespaces)) {
                hotwordText = String(hotwordText.dropFirst(tc.hotwords.trimmingCharacters(in: .whitespaces).count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let baselineHits = tc.expectedKeywords.filter { baselineText.localizedCaseInsensitiveContains($0) }.count
            let hotwordHits = tc.expectedKeywords.filter { hotwordText.localizedCaseInsensitiveContains($0) }.count

            results.append((tc.description, baselineText, hotwordText, baselineHits, hotwordHits))

            NSLog("HOTWORD_TEST: [\(tc.audioFile)]")
            NSLog("  Keywords: \(tc.expectedKeywords)")
            NSLog("  Baseline (\(baselineHits)/\(tc.expectedKeywords.count)): \(baselineText)")
            NSLog("  Hotword  (\(hotwordHits)/\(tc.expectedKeywords.count)): \(hotwordText)")
        }

        // Summary
        let totalBaseline = results.reduce(0) { $0 + $1.baselineHits }
        let totalHotword = results.reduce(0) { $0 + $1.hotwordHits }
        let totalExpected = Self.testCases.reduce(0) { $0 + $1.expectedKeywords.count }

        // Write report
        let reportPath = "/tmp/talk-hotword-test-results.txt"
        var report = "===== ASR Hotword Test Results =====\n"
        report += "Date: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        for r in results {
            report += "[\(r.desc)]\n"
            report += "  Baseline (\(r.baselineHits) hits): \(r.baseline)\n"
            report += "  Hotword  (\(r.hotwordHits) hits): \(r.withHotwords)\n\n"
        }
        report += "Total: Baseline \(totalBaseline)/\(totalExpected) vs Hotword \(totalHotword)/\(totalExpected)\n"
        try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)

        NSLog("HOTWORD_TEST: ===== Summary =====")
        NSLog("HOTWORD_TEST: Baseline: \(totalBaseline)/\(totalExpected)")
        NSLog("HOTWORD_TEST: Hotword:  \(totalHotword)/\(totalExpected)")
        NSLog("HOTWORD_TEST: Results at \(reportPath)")
    }
}
