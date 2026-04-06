//
//  ASRStreamBatchTest.swift
//  TalkTests
//
//  Reproduce the real-world scenario: streaming first, then batch fallback.
//  Compare with batch-only to isolate whether streaming contaminates batch results.
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

@Suite("ASR Stream→Batch Isolation")
struct ASRStreamBatchTest {

    /// Audio files that caused hallucination in production
    static let problemFiles = [
        "6033E7E9-557A-4D09-9952-315D9337BBB8.m4a",  // hallucinated "Claude Agent SDK" loop
        "B37D88D0-C1AA-495F-B27A-BC73969091C1.m4a",  // "飞书" test
    ]

    static let hotwordPrompt = "Vocabulary: Claude Code, 飞书, Claude Agent SDK"

    @Test @MainActor
    func batchOnlyVsStreamThenBatch() async throws {
        let asr = ASRService.shared
        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }

        let audioDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Talk/audio")

        var report = "===== Stream→Batch Isolation Test =====\n\n"

        for filename in Self.problemFiles {
            let url = audioDir.appendingPathComponent(filename)
            guard let audio = loadM4A(url) else {
                report += "[\(filename)] SKIPPED\n\n"
                continue
            }

            report += "[\(filename)] (\(audio.count) samples, \(String(format: "%.1f", Double(audio.count)/16000))s)\n"

            // Test 1: Batch only, no hotwords
            let batchNoHW = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: nil)
            report += "  1. Batch only, no HW:     \(batchNoHW.prefix(100))\n"

            // Test 2: Batch only, with hotwords
            let batchHW = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: Self.hotwordPrompt)
            report += "  2. Batch only, HW:        \(batchHW.prefix(100))\n"

            // Test 3: Simulate streaming first (feed audio in chunks), then batch without hotwords
            try await asr.startStreaming(language: "Chinese")
            let chunkSize = 1600  // 100ms chunks
            var offset = 0
            while offset < audio.count {
                let end = min(offset + chunkSize, audio.count)
                let chunk = Array(audio[offset..<end])
                asr.feedAudio(samples: chunk, sampleRate: 16000)
                try await Task.sleep(for: .milliseconds(10))
                offset = end
            }
            try await Task.sleep(for: .milliseconds(500))
            asr.stopStreaming()
            try await Task.sleep(for: .milliseconds(100))

            let streamThenBatchNoHW = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: nil)
            report += "  3. Stream→Batch, no HW:   \(streamThenBatchNoHW.prefix(100))\n"

            // Test 4: Streaming first, then batch WITH hotwords
            try await asr.startStreaming(language: "Chinese")
            offset = 0
            while offset < audio.count {
                let end = min(offset + chunkSize, audio.count)
                let chunk = Array(audio[offset..<end])
                asr.feedAudio(samples: chunk, sampleRate: 16000)
                try await Task.sleep(for: .milliseconds(10))
                offset = end
            }
            try await Task.sleep(for: .milliseconds(500))
            asr.stopStreaming()
            try await Task.sleep(for: .milliseconds(100))

            let streamThenBatchHW = try await asr.transcribe(audio: audio, sampleRate: 16000, initialPrompt: Self.hotwordPrompt)
            report += "  4. Stream→Batch, HW:      \(streamThenBatchHW.prefix(100))\n"

            report += "\n"
        }

        let reportPath = "/tmp/talk-stream-batch-test.txt"
        try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
        NSLog("STREAM_BATCH: Results at \(reportPath)")
        print(report)
    }
}
