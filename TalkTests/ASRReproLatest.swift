//
//  ASRReproLatest.swift
//  TalkTests
//
//  Use the actual VAD-filtered audio from production failures to reproduce.
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

@Suite("ASR Reproduce Latest Failures")
struct ASRReproLatest {

    struct FailCase {
        let filename: String
        let prodOutput: String
        let hotwords: String  // exact hotwords from production context
    }

    static let failures: [FailCase] = [
        FailCase(
            filename: "678A427B-EF9C-46F2-ACE1-7463F0586D89.m4a",
            prodOutput: "飞书 x30 loop",
            hotwords: "issue, 飞书, Claude Code, Claude Agent SDK"
        ),
        FailCase(
            filename: "26752467-BEE7-4D26-8521-147907E1D79B.m4a",
            prodOutput: ", 返回， 返回。",
            hotwords: "Claude Code, issue, Claude Agent SDK, 飞书"
        ),
        FailCase(
            filename: "B3A31278-EDE1-49CD-8D40-62046FFB7FAB.m4a",
            prodOutput: ", Chinese.",
            hotwords: "issue, 飞书, Claude Code, Claude Agent SDK"
        ),
        FailCase(
            filename: "D976813D-0C1E-4727-90F8-AF4ACDEF1236.m4a",
            prodOutput: ", 飞书。",
            hotwords: "飞书, Claude Code, Claude Agent SDK, issue"
        ),
    ]

    @Test @MainActor
    func reproduceWithExactProductionConditions() async throws {
        let asr = ASRService.shared
        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }

        let audioDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Talk/audio")

        var report = "===== Reproduce Latest Failures =====\n\n"

        for fc in Self.failures {
            let url = audioDir.appendingPathComponent(fc.filename)
            guard let audio = loadM4A(url) else {
                report += "[\(fc.filename)] SKIPPED\n\n"
                continue
            }

            let durSec = Double(audio.count) / 16000
            report += "[\(fc.filename)] \(String(format: "%.1f", durSec))s, \(audio.count) samples\n"
            report += "  Production output: \(fc.prodOutput)\n"
            report += "  Production hotwords: \(fc.hotwords)\n"

            // A: baseline
            let baseline = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: nil)
            report += "  A baseline:           \(baseline.prefix(100))\n"

            // B: exact production prompt format (old style)
            let oldPrompt = "The following terms may appear in the audio: \(fc.hotwords)"
            let oldResult = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: oldPrompt)
            report += "  B old prompt:         \(oldResult.prefix(100))\n"

            // C: Vocabulary format (current)
            let vocabPrompt = "Vocabulary: \(fc.hotwords)"
            let vocabResult = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: vocabPrompt)
            report += "  C Vocabulary:         \(vocabResult.prefix(100))\n"

            // D: raw hotwords only
            let rawResult = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: fc.hotwords)
            report += "  D raw hotwords:       \(rawResult.prefix(100))\n"

            report += "\n"
        }

        let reportPath = "/tmp/talk-repro-latest.txt"
        try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
        print(report)
    }
}
