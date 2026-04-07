import Testing
import Foundation
import AVFoundation
import MLX
import MLXLMCommon
import MLXVLM
import Tokenizers
@testable import Talk

@Suite("Gemma4 Direct Test")
struct Gemma4DirectTest {

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
    func inspectAudioEncoderOutput() async throws {
        let config = ModelConfiguration(id: "mlx-community/gemma-4-e2b-it-4bit")
        let context = try await VLMModelFactory.shared.load(configuration: config)

        let audioDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Talk/audio")
        let url = audioDir.appendingPathComponent("7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a")
        guard let audio = loadM4A(url) else { Issue.record("No audio"); return }

        let extractor = Gemma4AudioFeatureExtractor()
        let (mel, melMask) = extractor.extract(audio: audio)
        eval(mel, melMask)
        Issue.record("mel=\(mel.shape) mask=\(melMask.shape)")

        // Use prepareWithAudio to see audio encoder output shape
        let model = context.model as! Gemma4

        // Manually call audioTower to see output shape
        // Access via mirror
        let mirror = Mirror(reflecting: model)
        for child in mirror.children {
            if child.label == "_audioTower" {
                Issue.record("audioTower type: \(type(of: child.value))")
            }
        }

        // Build a minimal LMInput with 45 audio tokens and call prepare
        let audioTokenId: Int32 = 258881
        var tokenArray: [Int32] = [2] // BOS
        for _ in 0..<45 { tokenArray.append(audioTokenId) }
        tokenArray.append(3) // EOS
        let tokens = MLXArray(tokenArray).expandedDimensions(axis: 0)

        let lmInput = LMInput(
            text: .init(tokens: tokens),
            audio: .init(features: mel.expandedDimensions(axis: 0), mask: melMask.expandedDimensions(axis: 0))
        )

        // Call prepare — this triggers audio encoder
        let cache = model.newCache(parameters: nil)
        let result = try model.prepare(lmInput, cache: cache, windowSize: nil)

        // Generate one token to see if audio was used
        switch result {
        case .logits(let output):
            let firstLogits = output.logits[0..., -1, 0...]
            let topToken = firstLogits.argMax(axis: -1).item(Int.self)
            let decoded = context.tokenizer.decode(tokens: [topToken])
            Issue.record("First token from prepare: \(topToken) = '\(decoded)'")
        case .tokens:
            Issue.record("Got tokens instead of logits")
        }
    }
}
