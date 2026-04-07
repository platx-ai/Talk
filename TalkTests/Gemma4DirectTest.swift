import Testing
import Foundation
import AVFoundation
import MLX
import MLXVLM
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

    @Test
    func compareMelWithPythonRef() throws {
        let audioDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Talk/audio")
        let url = audioDir.appendingPathComponent("7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a")
        guard let audio = loadM4A(url) else { Issue.record("No audio"); return }

        Issue.record("Audio samples: \(audio.count)")

        let extractor = Gemma4AudioFeatureExtractor()
        let (mel, mask) = extractor.extract(audio: audio)
        eval(mel, mask)

        let mean = mel.mean().item(Float.self)
        let min_val = mel.min().item(Float.self)
        let max_val = mel.max().item(Float.self)

        // Get frame 0 values
        let frame0 = mel[0]
        eval(frame0)
        var frame0vals = [Float]()
        for i in 0..<min(10, frame0.dim(0)) {
            frame0vals.append(frame0[i].item(Float.self))
        }

        Issue.record("Swift mel: shape=\(mel.shape) mean=\(mean) min=\(min_val) max=\(max_val)")
        Issue.record("Swift frame0[0:10]: \(frame0vals)")

        // Python reference (28900 samples):
        // mean=-2.951809, min=-6.9078, max=1.3959
        // frame0[0:10]: [-4.613, -4.013, -3.061, -2.486, -2.138, -1.942, -1.868, -1.895, -2.005, -2.173]
        Issue.record("Python ref: mean=-2.952 min=-6.908 max=1.396")
        Issue.record("Python frame0: [-4.613, -4.013, -3.061, -2.486, -2.138, -1.942, -1.868, -1.895, -2.005, -2.173]")

        let meanDiff = abs(mean - (-2.952))
        Issue.record("Mean diff: \(meanDiff)")
        #expect(meanDiff < 0.01, "Swift mel=\(mean) Python=-2.952 diff=\(meanDiff) frame0=\(frame0vals)")

        // Check frame 0 first value diff
        let f0diff = abs(frame0vals[0] - (-4.613))
        Issue.record("Frame0[0] diff: \(f0diff)")
    }
}
