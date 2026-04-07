//
//  Gemma4AlignmentTests.swift
//  TalkTests
//
//  Verify Gemma4 audio tower Swift implementation matches Python reference.
//  Runs in Talk's xcodebuild environment (has Metal GPU access).
//

import Testing
import Foundation
import MLX
import MLXVLM
import AVFoundation

// MARK: - Mel Spectrogram Alignment

@Suite("Gemma4 Mel Alignment")
struct Gemma4MelAlignmentTests {

    @Test
    func melFilterBankShape() {
        // 512 FFT → 257 bins, 128 mel filters
        let bank = gemma4MelFilterBank(
            numFrequencyBins: 257,
            numMelFilters: 128,
            minFrequency: 0,
            maxFrequency: 8000,
            samplingRate: 16000
        )
        eval(bank)

        #expect(bank.shape == [257, 128])
        let minVal = bank.min().item(Float.self)
        #expect(minVal >= 0, "Filter bank should be non-negative")
    }

    @Test
    func melSpectrogramShape() {
        // 0.5s of 440Hz sine wave at 16kHz = 8000 samples
        // Expected: 49 frames × 128 mel bins (Python reference)
        var audio = [Float](repeating: 0, count: 8000)
        for i in 0..<8000 {
            audio[i] = sin(2.0 * .pi * 440.0 * Float(i) / 16000.0)
        }

        let extractor = Gemma4AudioFeatureExtractor()
        let (mel, mask) = extractor.extract(audio: audio)
        eval(mel, mask)

        // Python reference: mel_shape = [49, 128]
        #expect(mel.shape[0] == 49, "Frame count: got \(mel.shape[0]), expected 49")
        #expect(mel.shape[1] == 128, "Mel bins: got \(mel.shape[1]), expected 128")
    }

    @Test
    func melSpectrogramStats() {
        // Same input as Python reference
        var audio = [Float](repeating: 0, count: 8000)
        for i in 0..<8000 {
            audio[i] = sin(2.0 * .pi * 440.0 * Float(i) / 16000.0)
        }

        let extractor = Gemma4AudioFeatureExtractor()
        let (mel, _) = extractor.extract(audio: audio)
        eval(mel)

        let mean = mel.mean().item(Float.self)
        let std = sqrt(mel.variance().item(Float.self))

        // Python reference: mean=-4.3233, std=3.0925
        NSLog("ALIGN: Swift mel mean=\(mean), std=\(std)")
        NSLog("ALIGN: Python ref mean=-4.3233, std=3.0925")

        #expect(abs(mean - (-4.3233)) < 1.0, "Mean too far: \(mean) vs -4.3233")
        #expect(abs(std - 3.0925) < 1.0, "Std too far: \(std) vs 3.0925")
    }

    @Test
    func melSpectrogramDeterministic() {
        var audio = [Float](repeating: 0, count: 8000)
        for i in 0..<8000 {
            audio[i] = sin(2.0 * .pi * 440.0 * Float(i) / 16000.0)
        }

        let extractor = Gemma4AudioFeatureExtractor()
        let (mel1, _) = extractor.extract(audio: audio)
        let (mel2, _) = extractor.extract(audio: audio)
        eval(mel1, mel2)

        let diff = abs(mel1 - mel2).max().item(Float.self)
        #expect(diff < 1e-6, "Mel should be deterministic, max diff=\(diff)")
    }

    @Test
    func melSpectrogramRealAudio() {
        // Test with a real M4A recording if available
        let audioDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Talk/audio")

        let testFile = audioDir.appendingPathComponent(
            "7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a"
        )

        guard FileManager.default.fileExists(atPath: testFile.path) else {
            NSLog("ALIGN: Skip real audio test — file not found")
            return
        }

        // Load M4A as PCM float
        guard let audio = loadAudioFile(testFile) else {
            Issue.record("Failed to load audio file")
            return
        }

        NSLog("ALIGN: Real audio loaded, \(audio.count) samples (\(Float(audio.count)/16000)s)")

        let extractor = Gemma4AudioFeatureExtractor()
        let (mel, mask) = extractor.extract(audio: audio)
        eval(mel, mask)

        NSLog("ALIGN: Real audio mel shape=\(mel.shape)")
        #expect(mel.shape[0] > 0, "Should produce frames")
        #expect(mel.shape[1] == 128, "Should have 128 mel bins")

        let mean = mel.mean().item(Float.self)
        #expect(mean.isFinite, "Mel values should be finite")
    }

    /// Load audio file as 16kHz mono float array using AVFoundation
    private func loadAudioFile(_ url: URL) -> [Float]? {
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
}
