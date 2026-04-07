import Testing
import Foundation
import MLX
import MLXVLM
import MLXLMCommon
import MLXNN
import AVFoundation
@testable import Talk

@Suite("Gemma4 Audio Encoder Debug")
struct Gemma4AudioEncoderDebug {

    @Test @MainActor
    func debugFullPipeline() async throws {
        let config = ModelConfiguration(id: "mlx-community/gemma-4-e2b-it-4bit")
        let context = try await VLMModelFactory.shared.load(configuration: config)
        Issue.record("Model loaded")

        // Load real audio
        let audioDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Talk/audio")
        let testFile = audioDir.appendingPathComponent("7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a")
        guard let audio = loadM4A(testFile) else {
            Issue.record("Audio not found"); return
        }

        // Build input
        var input = UserInput(prompt: "Transcribe this audio verbatim.")
        input.audios = [audio]

        let lmInput = try await context.processor.prepare(input: input)
        eval(lmInput.text.tokens)
        Issue.record("LMInput: tokens=\(lmInput.text.tokens.shape), hasAudio=\(lmInput.audio != nil)")

        if let af = lmInput.audio?.features {
            eval(af)
            Issue.record("Audio features: \(af.shape), dtype=\(af.dtype)")
        }

        // Try generate with very few tokens to trigger the audio encoder
        var iterator = try TokenIterator(
            input: lmInput, model: context.model, parameters: .init(maxTokens: 5))
        Issue.record("TokenIterator created")

        if let firstToken = iterator.next() {
            Issue.record("First token: \(firstToken)")
        } else {
            Issue.record("No tokens generated")
        }
    }

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
}
