//
//  VADService.swift
//  Talk
//
//  Silero VAD 语音活动检测服务
//

import Foundation
import SileroVAD

struct VADFilterResult {
    let speechAudio: [Float]
    let speechDetected: Bool
    let maxProbability: Float
}

struct StreamingVADResult {
    let filteredSamples: [Float]
    let processedFrames: Int
    let speechFrames: Int
    let maxProbability: Float

    init(filteredSamples: [Float], processedFrames: Int, speechFrames: Int, maxProbability: Float) {
        self.filteredSamples = filteredSamples
        self.processedFrames = processedFrames
        self.speechFrames = speechFrames
        self.maxProbability = maxProbability
    }
}

struct StreamingVADDecisionState {
    var preSpeechBuffer: [[Float]]
    var hangoverFrames: Int

    init(preSpeechBuffer: [[Float]] = [], hangoverFrames: Int = 0) {
        self.preSpeechBuffer = preSpeechBuffer
        self.hangoverFrames = hangoverFrames
    }
}

final class VADService {
    static let shared = VADService()

    private let queue = DispatchQueue(label: "com.kongjiaming.talk.vad", qos: .userInitiated)
    private var vad: SileroVAD?
    private var streamingRemainder: [Float] = []
    private var streamingPreSpeechBuffer: [[Float]] = []
    private var streamingHangoverFrames = 0
    private var streamingPreviousSpeechState: Bool?
    private var streamingFrameIndex = 0
    private var didLogStreamingSampleRateMismatch = false

    private init() {}

    func reset() {
        queue.sync {
            vad?.reset()
            streamingRemainder = []
            streamingPreSpeechBuffer = []
            streamingHangoverFrames = 0
            streamingPreviousSpeechState = nil
            streamingFrameIndex = 0
            didLogStreamingSampleRateMismatch = false
        }
    }

    func filterStreamingSpeechAsync(
        samples: [Float],
        sampleRate: Int,
        threshold: Float = 0.5,
        paddingChunks: Int = 1
    ) async -> StreamingVADResult {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.filterStreamingSpeechLocked(
                    samples: samples,
                    sampleRate: sampleRate,
                    threshold: threshold,
                    paddingChunks: paddingChunks
                )
                continuation.resume(returning: result)
            }
        }
    }

    func filterStreamingSpeech(
        samples: [Float],
        sampleRate: Int,
        threshold: Float = 0.5,
        paddingChunks: Int = 1
    ) -> StreamingVADResult {
        queue.sync {
            filterStreamingSpeechLocked(
                samples: samples,
                sampleRate: sampleRate,
                threshold: threshold,
                paddingChunks: paddingChunks
            )
        }
    }

    private func filterStreamingSpeechLocked(
        samples: [Float],
        sampleRate: Int,
        threshold: Float,
        paddingChunks: Int
    ) -> StreamingVADResult {
        guard !samples.isEmpty else {
            return StreamingVADResult(filteredSamples: [], processedFrames: 0, speechFrames: 0, maxProbability: 0)
        }

        guard sampleRate == SileroVAD.sampleRate else {
            if !didLogStreamingSampleRateMismatch {
                AppLogger.warning(
                    "流式 VAD 跳过：采样率不是 16kHz (\(sampleRate)Hz)",
                    category: .audio
                )
                didLogStreamingSampleRateMismatch = true
            }
            return StreamingVADResult(
                filteredSamples: samples,
                processedFrames: 0,
                speechFrames: 0,
                maxProbability: 1
            )
        }

        do {
            let vad = try ensureVADLoaded()
            let chunkSize = SileroVAD.chunkSize

            var working = streamingRemainder
            working.append(contentsOf: samples)

            var chunks: [[Float]] = []
            var offset = 0
            while offset + chunkSize <= working.count {
                chunks.append(Array(working[offset..<(offset + chunkSize)]))
                offset += chunkSize
            }
            streamingRemainder = Array(working[offset..<working.count])

            guard !chunks.isEmpty else {
                return StreamingVADResult(filteredSamples: [], processedFrames: 0, speechFrames: 0, maxProbability: 0)
            }

            var output: [Float] = []
            var maxProbability: Float = 0
            var speechFrames = 0

            for chunk in chunks {
                let probability = try vad.process(chunk)
                if probability > maxProbability {
                    maxProbability = probability
                }

                let isSpeech = probability >= threshold
                if streamingPreviousSpeechState == nil {
                    let stateText = isSpeech ? "speech" : "silence"
                    AppLogger.debug(
                        "流式 VAD 初始状态 -> \(stateText), frame=\(streamingFrameIndex), prob=\(String(format: "%.3f", probability)), threshold=\(String(format: "%.2f", threshold))",
                        category: .audio
                    )
                } else if let previousState = streamingPreviousSpeechState, previousState != isSpeech {
                    let stateText = isSpeech ? "speech" : "silence"
                    AppLogger.debug(
                        "流式 VAD 状态切换 -> \(stateText), frame=\(streamingFrameIndex), prob=\(String(format: "%.3f", probability)), threshold=\(String(format: "%.2f", threshold))",
                        category: .audio
                    )
                }
                streamingPreviousSpeechState = isSpeech

                let (decisionOutput, newState) = Self.applyStreamingDecision(
                    chunk: chunk,
                    isSpeech: isSpeech,
                    paddingChunks: paddingChunks,
                    state: StreamingVADDecisionState(
                        preSpeechBuffer: streamingPreSpeechBuffer,
                        hangoverFrames: streamingHangoverFrames
                    )
                )
                if isSpeech {
                    speechFrames += 1
                }
                output.append(contentsOf: decisionOutput)
                streamingPreSpeechBuffer = newState.preSpeechBuffer
                streamingHangoverFrames = newState.hangoverFrames

                streamingFrameIndex += 1
            }

            return StreamingVADResult(
                filteredSamples: output,
                processedFrames: chunks.count,
                speechFrames: speechFrames,
                maxProbability: maxProbability
            )
        } catch {
            AppLogger.warning("流式 VAD 推理失败，回退为原始音频: \(error.localizedDescription)", category: .audio)
            return StreamingVADResult(
                filteredSamples: samples,
                processedFrames: 0,
                speechFrames: 0,
                maxProbability: 1
            )
        }
    }

    internal static func applyStreamingDecision(
        chunk: [Float],
        isSpeech: Bool,
        paddingChunks: Int,
        state: StreamingVADDecisionState
    ) -> ([Float], StreamingVADDecisionState) {
        var output: [Float] = []
        var newState = state

        if isSpeech {
            if !newState.preSpeechBuffer.isEmpty {
                for buffered in newState.preSpeechBuffer {
                    output.append(contentsOf: buffered)
                }
                newState.preSpeechBuffer.removeAll(keepingCapacity: true)
            }
            output.append(contentsOf: chunk)
            newState.hangoverFrames = paddingChunks
            return (output, newState)
        }

        if newState.hangoverFrames > 0 {
            output.append(contentsOf: chunk)
            newState.hangoverFrames -= 1
            return (output, newState)
        }

        if paddingChunks > 0 {
            newState.preSpeechBuffer.append(chunk)
            if newState.preSpeechBuffer.count > paddingChunks {
                newState.preSpeechBuffer.removeFirst(newState.preSpeechBuffer.count - paddingChunks)
            }
        }

        return (output, newState)
    }

    func filterSpeech(
        audio: [Float],
        sampleRate: Int,
        threshold: Float = 0.5,
        paddingChunks: Int = 1,
        minSpeechChunks: Int = 2
    ) -> VADFilterResult {
        queue.sync {
            filterSpeechLocked(
                audio: audio,
                sampleRate: sampleRate,
                threshold: threshold,
                paddingChunks: paddingChunks,
                minSpeechChunks: minSpeechChunks
            )
        }
    }

    private func filterSpeechLocked(
        audio: [Float],
        sampleRate: Int,
        threshold: Float,
        paddingChunks: Int,
        minSpeechChunks: Int
    ) -> VADFilterResult {
        guard !audio.isEmpty else {
            return VADFilterResult(speechAudio: [], speechDetected: false, maxProbability: 0)
        }

        guard sampleRate == SileroVAD.sampleRate else {
            AppLogger.warning(
                "VAD 跳过：采样率不是 16kHz (\(sampleRate)Hz)",
                category: .audio
            )
            return VADFilterResult(speechAudio: audio, speechDetected: true, maxProbability: 1)
        }

        do {
            let vad = try ensureVADLoaded()
            vad.reset()

            var maxProbability: Float = 0
            let speechAudio = try Self.extractSpeech(
                audio: audio,
                chunkSize: SileroVAD.chunkSize,
                threshold: threshold,
                paddingChunks: paddingChunks,
                minSpeechChunks: minSpeechChunks
            ) { chunk in
                let probability = try vad.process(chunk)
                if probability > maxProbability {
                    maxProbability = probability
                }
                return probability
            }

            return VADFilterResult(
                speechAudio: speechAudio,
                speechDetected: !speechAudio.isEmpty,
                maxProbability: maxProbability
            )
        } catch {
            AppLogger.warning("VAD 推理失败，回退为原始音频: \(error.localizedDescription)", category: .audio)
            return VADFilterResult(speechAudio: audio, speechDetected: true, maxProbability: 1)
        }
    }

    private func ensureVADLoaded() throws -> SileroVAD {
        if let vad {
            return vad
        }

        let loaded = try SileroVAD()
        vad = loaded
        AppLogger.info("Silero VAD 初始化完成", category: .audio)
        return loaded
    }

    internal static func extractSpeech(
        audio: [Float],
        chunkSize: Int,
        threshold: Float,
        paddingChunks: Int,
        minSpeechChunks: Int,
        score: ([Float]) throws -> Float
    ) throws -> [Float] {
        guard !audio.isEmpty else { return [] }

        let chunks = splitIntoChunks(audio, chunkSize: chunkSize)
        guard !chunks.isEmpty else { return [] }

        var speechFlags = [Bool](repeating: false, count: chunks.count)
        var previousState: Bool?

        for index in chunks.indices {
            let probability = try score(chunks[index])
            let isSpeech = probability >= threshold
            speechFlags[index] = isSpeech

            if previousState == nil {
                let stateText = isSpeech ? "speech" : "silence"
                AppLogger.debug(
                    "VAD 初始状态 -> \(stateText), chunk=\(index), prob=\(String(format: "%.3f", probability)), threshold=\(String(format: "%.2f", threshold))",
                    category: .audio
                )
            } else if let previousState, previousState != isSpeech {
                let stateText = isSpeech ? "speech" : "silence"
                AppLogger.debug(
                    "VAD 状态切换 -> \(stateText), chunk=\(index), prob=\(String(format: "%.3f", probability)), threshold=\(String(format: "%.2f", threshold))",
                    category: .audio
                )
            }

            previousState = isSpeech
        }

        let speechChunkCount = speechFlags.reduce(0) { partial, isSpeech in
            partial + (isSpeech ? 1 : 0)
        }

        guard speechChunkCount >= minSpeechChunks else {
            AppLogger.info(
                "VAD 结果: 未达到最少语音帧，speechChunks=\(speechChunkCount), minRequired=\(minSpeechChunks), totalChunks=\(chunks.count)",
                category: .audio
            )
            return []
        }

        let expandedFlags = expandSpeechFlags(speechFlags, paddingChunks: paddingChunks)
        let expandedSpeechCount = expandedFlags.reduce(0) { partial, isSpeech in
            partial + (isSpeech ? 1 : 0)
        }
        AppLogger.info(
            "VAD 结果: speechChunks=\(speechChunkCount), expandedSpeechChunks=\(expandedSpeechCount), totalChunks=\(chunks.count), padding=\(paddingChunks)",
            category: .audio
        )
        return mergeChunks(chunks, selectedFlags: expandedFlags, originalCount: audio.count)
    }

    internal static func splitIntoChunks(_ audio: [Float], chunkSize: Int) -> [[Float]] {
        guard chunkSize > 0 else { return [] }
        guard !audio.isEmpty else { return [] }

        var chunks: [[Float]] = []
        chunks.reserveCapacity((audio.count + chunkSize - 1) / chunkSize)

        var offset = 0
        while offset < audio.count {
            let end = min(offset + chunkSize, audio.count)
            var chunk = Array(audio[offset..<end])
            if chunk.count < chunkSize {
                chunk.append(contentsOf: repeatElement(0, count: chunkSize - chunk.count))
            }
            chunks.append(chunk)
            offset += chunkSize
        }

        return chunks
    }

    internal static func expandSpeechFlags(_ flags: [Bool], paddingChunks: Int) -> [Bool] {
        guard paddingChunks > 0 else { return flags }
        guard !flags.isEmpty else { return flags }

        var expanded = flags
        for index in flags.indices where flags[index] {
            let left = max(0, index - paddingChunks)
            let right = min(flags.count - 1, index + paddingChunks)
            for i in left...right {
                expanded[i] = true
            }
        }

        return expanded
    }

    internal static func mergeChunks(
        _ chunks: [[Float]],
        selectedFlags: [Bool],
        originalCount: Int
    ) -> [Float] {
        guard chunks.count == selectedFlags.count else { return [] }

        var merged: [Float] = []
        for index in chunks.indices where selectedFlags[index] {
            merged.append(contentsOf: chunks[index])
        }

        if merged.count > originalCount {
            merged.removeSubrange(originalCount..<merged.count)
        }

        return merged
    }
}
