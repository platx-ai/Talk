//
//  Gemma4E2ETests.swift
//  TalkTests
//
//  End-to-end: load Gemma4 model, transcribe real audio, verify output.
//

import Testing
import Foundation
import AVFoundation
import MLXLMCommon
import MLXVLM
@testable import Talk

@Suite("Gemma4 End-to-End")
struct Gemma4E2ETests {

    private func loadM4A(_ url: URL) -> [Float]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let nativeFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let nativeBuffer = AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: frameCount) else { return nil }
        try? audioFile.read(into: nativeBuffer)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: nativeFormat, to: format) else { return nil }
        let outputCapacity = AVAudioFrameCount(Double(frameCount) * 16000.0 / nativeFormat.sampleRate + 100)
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

    @Test @MainActor
    func gemma4TranscribeRealAudio() async throws {
        let engine = Gemma4ASREngine.shared

        // Load model
        if !engine.isModelLoaded {
            try await engine.loadModel(modelId: "mlx-community/gemma-4-e2b-it-4bit")
        }
        #expect(engine.isModelLoaded, "Model should be loaded")

        // Test cases from regression suite
        let audioDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Talk/audio")

        let cases: [(file: String, gt: String, keywords: [String])] = [
            ("7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a", "好的，我来更新一版。", ["更新"]),
            ("6114ED33-A5F1-43C4-B6CA-9F87B7068148.m4a", "不可，如果不确定，就做实验。", ["不确定", "实验"]),
            ("085C511D-EC6D-4090-9101-CED25A00FD5A.m4a", "我觉得可以用。", ["可以用"]),
        ]

        var totalSim: Float = 0
        var totalKW = 0
        var totalKWMax = 0

        for tc in cases {
            let url = audioDir.appendingPathComponent(tc.file)
            guard let audio = loadM4A(url) else {
                Issue.record("GEMMA4_E2E: SKIP \(tc.file) — not found")
                continue
            }

            Issue.record("GEMMA4_E2E: Transcribing \(tc.file) (\(audio.count) samples)...")
            let result = try await engine.transcribe(audio: audio, sampleRate: 16000)
            Issue.record("GEMMA4_E2E: Output: \(result)")
            Issue.record("GEMMA4_E2E: GT:     \(tc.gt)")

            // Check not empty / not error
            #expect(!result.isEmpty, "Output should not be empty")
            #expect(!result.contains("[ERROR"), "Should not be an error")

            // Keyword check
            let hits = tc.keywords.filter { result.localizedCaseInsensitiveContains($0) }.count
            totalKW += hits
            totalKWMax += tc.keywords.count
            Issue.record("GEMMA4_E2E: Keywords: \(hits)/\(tc.keywords.count)")
        }

        Issue.record("GEMMA4_E2E: Total keyword hits: \(totalKW)/\(totalKWMax)")
        // At least some keywords should match
        #expect(totalKW > 0, "Should match at least some keywords")
    }
}
