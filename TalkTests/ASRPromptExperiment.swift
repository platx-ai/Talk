//
//  ASRPromptExperiment.swift
//  TalkTests
//
//  Experiment: compare different system prompt strategies for hotword injection
//  using real recorded audio from ~/Library/Application Support/Talk/audio/
//
//  Run with: xcodebuild test -only-testing:"TalkTests/ASRPromptExperiment" DEVELOPMENT_TEAM=7A8HPDPNNX ...
//

import Testing
import Foundation
@testable import Talk

// MARK: - Audio Loader (M4A via AVFoundation)

import AVFoundation

private func loadM4A(_ url: URL) -> [Float]? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    // Read in native format first, then convert
    let nativeFormat = audioFile.processingFormat
    let frameCount = AVAudioFrameCount(audioFile.length)
    guard let nativeBuffer = AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: frameCount) else { return nil }
    try? audioFile.read(into: nativeBuffer)

    // Convert to 16kHz mono float32
    guard let converter = AVAudioConverter(from: nativeFormat, to: format) else { return nil }
    let ratio = 16000.0 / nativeFormat.sampleRate
    let outputCapacity = AVAudioFrameCount(Double(frameCount) * ratio + 100)
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else { return nil }

    var error: NSError?
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return nativeBuffer
    }

    guard error == nil else { return nil }
    let ptr = outputBuffer.floatChannelData![0]
    return Array(UnsafeBufferPointer(start: ptr, count: Int(outputBuffer.frameLength)))
}

// MARK: - Prompt Strategies

struct PromptStrategy {
    let name: String
    let builder: ([String]) -> String?  // hotwords -> system prompt content (or nil for baseline)
}

let strategies: [PromptStrategy] = [
    PromptStrategy(name: "baseline (no prompt)") { _ in nil },

    PromptStrategy(name: "English instruction") { hotwords in
        "The following terms may appear in the audio: \(hotwords.joined(separator: ", "))"
    },

    PromptStrategy(name: "Terse keywords only") { hotwords in
        hotwords.joined(separator: ", ")
    },

    PromptStrategy(name: "Chinese instruction") { hotwords in
        "音频中可能出现以下术语：\(hotwords.joined(separator: "、"))"
    },

    PromptStrategy(name: "Vocabulary context") { hotwords in
        "Vocabulary: \(hotwords.joined(separator: ", "))"
    },

    PromptStrategy(name: "Short hint") { hotwords in
        "Hint: \(hotwords.prefix(3).joined(separator: ", "))"
    },
]

// MARK: - Test Cases from Real Audio

struct RealTestCase {
    let audioFilename: String  // UUID.m4a in audio dir
    let expectedContent: String  // what the person actually said (ground truth)
    let expectedKeywords: [String]
}

let realTestCases: [RealTestCase] = [
    RealTestCase(
        audioFilename: "B37D88D0-C1AA-495F-B27A-BC73969091C1.m4a",
        expectedContent: "飞书的channel怎么不工作了",
        expectedKeywords: ["飞书", "channel"]
    ),
    RealTestCase(
        audioFilename: "6033E7E9-557A-4D09-9952-315D9337BBB8.m4a",
        expectedContent: "你看一下现在这几次语音识别的结果",  // the one that produced hallucination
        expectedKeywords: ["语音识别"]
    ),
    RealTestCase(
        audioFilename: "50B64517-E0DB-4258-AA55-6576B23ECBAA.m4a",
        expectedContent: "不是说这个有问题就直接退回去，你看能不能修正",
        expectedKeywords: ["修正"]
    ),
    RealTestCase(
        audioFilename: "52C49B7E-99C7-4832-8FFD-D9B6F65A60E3.m4a",
        expectedContent: "你的系统提示词可以去调，然后用这些错误的案例去测试一下",
        expectedKeywords: ["系统", "提示词", "测试"]
    ),
]

let testHotwords = ["Claude Code", "飞书", "Claude Agent SDK"]

// MARK: - Experiment

@Suite("ASR Prompt Experiment")
struct ASRPromptExperiment {

    @Test @MainActor
    func comparePromptStrategies() async throws {
        let asr = ASRService.shared
        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }

        let audioDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Talk/audio")

        var report = "===== ASR Prompt Strategy Experiment =====\n"
        report += "Date: \(ISO8601DateFormatter().string(from: Date()))\n"
        report += "Hotwords: \(testHotwords.joined(separator: ", "))\n\n"

        for tc in realTestCases {
            let url = audioDir.appendingPathComponent(tc.audioFilename)
            guard let audio = loadM4A(url) else {
                report += "[\(tc.audioFilename)] SKIPPED — file not found\n\n"
                continue
            }

            report += "[\(tc.audioFilename)]\n"
            report += "  Expected: \(tc.expectedContent)\n"
            report += "  Keywords: \(tc.expectedKeywords)\n"

            for strategy in strategies {
                let prompt = strategy.builder(testHotwords)
                let text = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: prompt)

                let hits = tc.expectedKeywords.filter { text.localizedCaseInsensitiveContains($0) }.count
                let truncated = text.prefix(120)
                let marker = hits == tc.expectedKeywords.count ? "✅" : (hits > 0 ? "⚠️" : "❌")

                report += "  \(marker) [\(strategy.name)] (\(hits)/\(tc.expectedKeywords.count)): \(truncated)\n"
            }
            report += "\n"
        }

        // Write report
        let reportPath = "/tmp/talk-prompt-experiment.txt"
        try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
        NSLog("PROMPT_EXP: Results at \(reportPath)")
        print(report)
    }
}
