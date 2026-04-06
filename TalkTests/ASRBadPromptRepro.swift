//
//  ASRBadPromptRepro.swift
//  TalkTests
//
//  Reproduce the exact prompts that caused hallucination in production.
//

import Testing
import Foundation
import AVFoundation
@testable import Talk

private func loadM4A(_ url: URL) -> [Float]? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
    let nativeFormat = audioFile.processingFormat
    let frameCount = AVAudioFrameCount(audioFile.length)
    guard let nativeBuffer = AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: frameCount) else { return nil }
    try? audioFile.read(into: nativeBuffer)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
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

@Suite("ASR Bad Prompt Reproduction")
struct ASRBadPromptRepro {

    // The exact prompts from production logs that caused hallucination
    static let badPrompts: [(name: String, prompt: String)] = [
        // From log: "Claude Code, 飞书, 飞书, Claude Agent SDK, issue. "
        ("original bad (duplicates + trailing period)", "The following terms may appear in the audio: Claude Code, 飞书, 飞书, Claude Agent SDK, issue"),
        // Deduplicated but same format
        ("dedup same format", "The following terms may appear in the audio: Claude Code, 飞书, Claude Agent SDK, issue"),
        // Remove "issue" (common English word, may confuse)
        ("dedup no issue", "The following terms may appear in the audio: Claude Code, 飞书, Claude Agent SDK"),
        // Terse vocabulary format
        ("Vocabulary format", "Vocabulary: Claude Code, 飞书, Claude Agent SDK"),
        // Vocabulary without "issue"
        ("Vocabulary + issue", "Vocabulary: Claude Code, 飞书, Claude Agent SDK, issue"),
        // Just the terms, nothing else
        ("bare terms", "Claude Code, 飞书, Claude Agent SDK"),
        // Very minimal
        ("minimal 2 terms", "Vocabulary: Claude Code, 飞书"),
    ]

    @Test @MainActor
    func reproduceWithProblemAudio() async throws {
        let asr = ASRService.shared
        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }

        let audioDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Talk/audio")

        // Use the audio that produced hallucination: 6033E7E9
        let files = [
            ("6033E7E9 (hallucinated)", "6033E7E9-557A-4D09-9952-315D9337BBB8.m4a"),
            ("D976813D (', 飞书。')", "D976813D-0C1E-4727-90F8-AF4ACDEF1236.m4a"),
            ("163F0255 ('language Chinese')", "163F0255-DD1E-41E9-B396-28B6F2AFA663.m4a"),
        ]

        var report = "===== Bad Prompt Reproduction =====\n\n"

        for (label, filename) in files {
            let url = audioDir.appendingPathComponent(filename)
            guard let audio = loadM4A(url) else {
                report += "[\(label)] SKIPPED — file not found\n\n"
                continue
            }

            report += "[\(label)] (\(String(format: "%.1f", Double(audio.count)/16000))s)\n"

            // Baseline
            let baseline = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: nil)
            let baselineTrunc = String(baseline.prefix(100))
            report += "  baseline:  \(baselineTrunc)\n"

            for (name, prompt) in Self.badPrompts {
                let result = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: prompt)
                let truncated = String(result.prefix(100))
                let isHallucination = truncated.contains("Claude Agent SDK, issue") ||
                    truncated.contains("飞书, Claude") ||
                    truncated.hasPrefix(", ") ||
                    truncated.hasPrefix("language ")
                let marker = isHallucination ? "💀" : "✅"
                report += "  \(marker) [\(name)]:  \(truncated)\n"
            }
            report += "\n"
        }

        let reportPath = "/tmp/talk-bad-prompt-repro.txt"
        try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
        NSLog("BAD_PROMPT: Results at \(reportPath)")
        print(report)
    }
}
