//
//  VADServiceTests.swift
//  TalkTests
//
//  VAD 服务单元测试
//

import Testing
import Foundation
@testable import Talk

@Suite("VAD Service Tests")
struct VADServiceTests {

    @Test("splitIntoChunks 会按固定大小切分并补零")
    func splitIntoChunksPadsLastChunk() {
        let audio: [Float] = [1, 2, 3, 4, 5]
        let chunks = VADService.splitIntoChunks(audio, chunkSize: 4)

        #expect(chunks.count == 2)
        #expect(chunks[0] == [1, 2, 3, 4])
        #expect(chunks[1] == [5, 0, 0, 0])
    }

    @Test("expandSpeechFlags 会扩展语音片段前后上下文")
    func expandSpeechFlagsAppliesPadding() {
        let flags = [false, false, true, false, false]
        let expanded = VADService.expandSpeechFlags(flags, paddingChunks: 1)

        #expect(expanded == [false, true, true, true, false])
    }

    @Test("extractSpeech 在语音片段不足时返回空")
    func extractSpeechRequiresMinimumSpeechChunks() throws {
        let audio: [Float] = [
            1, 1, 1, 1,
            2, 2, 2, 2,
            3, 3, 3, 3
        ]

        var index = 0
        let output = try VADService.extractSpeech(
            audio: audio,
            chunkSize: 4,
            threshold: 0.5,
            paddingChunks: 0,
            minSpeechChunks: 2
        ) { _ in
            defer { index += 1 }
            return index == 1 ? 0.8 : 0.1
        }

        #expect(output.isEmpty)
    }

    @Test("extractSpeech 会保留语音及相邻上下文片段")
    func extractSpeechKeepsSpeechAndPadding() throws {
        let audio: [Float] = [
            1, 1, 1, 1,
            2, 2, 2, 2,
            3, 3, 3, 3
        ]

        var index = 0
        let output = try VADService.extractSpeech(
            audio: audio,
            chunkSize: 4,
            threshold: 0.5,
            paddingChunks: 1,
            minSpeechChunks: 1
        ) { _ in
            defer { index += 1 }
            return index == 1 ? 0.9 : 0.1
        }

        #expect(output == audio)
    }

    @Test("mergeChunks 会截断补零到原始长度")
    func mergeChunksTrimsToOriginalLength() {
        let chunks: [[Float]] = [
            [1, 2, 3, 4],
            [5, 6, 0, 0]
        ]
        let merged = VADService.mergeChunks(chunks, selectedFlags: [true, true], originalCount: 6)

        #expect(merged == [1, 2, 3, 4, 5, 6])
    }

    @Test("流式 VAD：静音帧应先缓存不输出")
    func streamingDecisionBuffersSilence() {
        let chunk = [Float](repeating: 0, count: 4)
        let initial = StreamingVADDecisionState()

        let (output, next) = VADService.applyStreamingDecision(
            chunk: chunk,
            isSpeech: false,
            paddingChunks: 1,
            state: initial
        )

        #expect(output.isEmpty)
        #expect(next.preSpeechBuffer.count == 1)
        #expect(next.hangoverFrames == 0)
    }

    @Test("流式 VAD：检测到语音时应输出缓存上下文")
    func streamingDecisionFlushesBufferedContextOnSpeech() {
        let silence = [Float](repeating: 0, count: 4)
        let speech = [Float](repeating: 1, count: 4)
        let initial = StreamingVADDecisionState(preSpeechBuffer: [silence], hangoverFrames: 0)

        let (output, next) = VADService.applyStreamingDecision(
            chunk: speech,
            isSpeech: true,
            paddingChunks: 1,
            state: initial
        )

        #expect(output == silence + speech)
        #expect(next.preSpeechBuffer.isEmpty)
        #expect(next.hangoverFrames == 1)
    }

    @Test("流式 VAD：语音后的静音应在补偿帧内继续输出")
    func streamingDecisionEmitsHangoverSilence() {
        let silence = [Float](repeating: 0, count: 4)
        let initial = StreamingVADDecisionState(preSpeechBuffer: [], hangoverFrames: 1)

        let (output, next) = VADService.applyStreamingDecision(
            chunk: silence,
            isSpeech: false,
            paddingChunks: 1,
            state: initial
        )

        #expect(output == silence)
        #expect(next.hangoverFrames == 0)
    }
}
