import Testing
import Foundation
import AVFoundation
import MLXLMCommon
import MLXVLM
@testable import Talk

@Suite("Gemma4 Output Check")
struct Gemma4OutputCheck {

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
    func checkOutputContent() async throws {
        let engine = Gemma4ASREngine.shared
        if !engine.isModelLoaded {
            try await engine.loadModel(modelId: "mlx-community/gemma-4-e2b-it-4bit")
        }

        let audioDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Talk/audio")

        // Test with known audio
        let file = "7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a"
        let url = audioDir.appendingPathComponent(file)
        guard let audio = loadM4A(url) else {
            Issue.record("Audio not found: \(file)")
            return
        }

        let result = try await engine.transcribe(audio: audio, sampleRate: 16000, prompt: "Transcribe this audio verbatim.")

        // Force print the output as a test failure so we can see it
        #expect(result.count < 5, "OUTPUT[\(result.count)]: \(result)")
    }
}
