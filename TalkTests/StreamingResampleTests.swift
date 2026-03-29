//
//  StreamingResampleTests.swift
//  TalkTests
//
//  流式音频重采样测试
//

import Testing
import Foundation
@testable import Talk

@Suite("Streaming Audio Resample Tests")
struct StreamingResampleTests {

    // MARK: - resampleLinear 单元测试

    @Test("重采样：48kHz -> 16kHz 应正确转换样点数")
    func resampleLinear_48kTo16k_ShouldReduceSampleCount() {
        let recorder = AudioRecorder.shared

        // 1 秒的音频 @ 48kHz = 48000 样点
        let input48k = Array(repeating: 0.5 as Float, count: 48000)

        // 重采样到 16kHz
        let output16k = recorder.resampleLinear(input48k, from: 48000.0, to: 16000.0)

        // 验证输出样点数约为输入的 1/3
        #expect(output16k.count == 16000, "48kHz->16kHz 应产生 16000 样点，实际: \(output16k.count)")
    }

    @Test("重采样：44.1kHz -> 16kHz 应正确计算样点数")
    func resampleLinear_44k1To16k_ShouldReduceSampleCount() {
        let recorder = AudioRecorder.shared

        // 1 秒的音频 @ 44.1kHz = 44100 样点
        let input44k1 = Array(repeating: 0.3 as Float, count: 44100)

        // 重采样到 16kHz
        let output16k = recorder.resampleLinear(input44k1, from: 44100.0, to: 16000.0)

        // 44100 * (16000 / 44100) = 16000
        #expect(output16k.count == 16000, "44.1kHz->16kHz 应产生 16000 样点，实际: \(output16k.count)")
    }

    @Test("重采样：16kHz -> 16kHz 应保持原样")
    func resampleLinear_16kTo16k_ShouldReturnSameArray() {
        let recorder = AudioRecorder.shared

        let input16k = Array(repeating: 0.7 as Float, count: 16000)

        // 重采样到相同采样率
        let output16k = recorder.resampleLinear(input16k, from: 16000.0, to: 16000.0)

        // 验证输出与输入完全相同
        #expect(output16k.count == input16k.count, "相同采样率应保持样点数不变")
        #expect(output16k == input16k, "相同采样率应返回相同数组")
    }

    @Test("重采样：空数组应返回空数组")
    func resampleLinear_EmptyInput_ShouldReturnEmptyArray() {
        let recorder = AudioRecorder.shared

        let emptyInput: [Float] = []
        let output = recorder.resampleLinear(emptyInput, from: 48000.0, to: 16000.0)

        #expect(output.isEmpty, "空输入应返回空输出")
    }

    @Test("重采样：短数组处理应正确")
    func resampleLinear_ShortArray_ShouldHandleGracefully() {
        let recorder = AudioRecorder.shared

        // 0.01 秒的音频 @ 48kHz = 480 样点
        let shortInput = Array(repeating: Float.random(in: -1...1), count: 480)

        let output16k = recorder.resampleLinear(shortInput, from: 48000.0, to: 16000.0)

        // 480 * (16000 / 48000) = 160
        #expect(output16k.count == 160, "短数组应正确重采样到 160 样点，实际: \(output16k.count)")
    }

    @Test("重采样：96kHz -> 16kHz 应大幅压缩")
    func resampleLinear_96kTo16k_ShouldCompressSignificantly() {
        let recorder = AudioRecorder.shared

        // 1 秒的音频 @ 96kHz = 96000 样点
        let input96k = Array(repeating: 0.2 as Float, count: 96000)

        // 重采样到 16kHz
        let output16k = recorder.resampleLinear(input96k, from: 96000.0, to: 16000.0)

        // 96000 * (16000 / 96000) = 16000
        #expect(output16k.count == 16000, "96kHz->16kHz 应产生 16000 样点，实际: \(output16k.count)")
    }

    @Test("重采样：16kHz -> 48kHz 应正确扩展")
    func resampleLinear_16kTo48k_ShouldExpandCorrectly() {
        let recorder = AudioRecorder.shared

        // 1 秒的音频 @ 16kHz = 16000 样点
        let input16k = Array(repeating: 0.4 as Float, count: 16000)

        // 重采样到 48kHz
        let output48k = recorder.resampleLinear(input16k, from: 16000.0, to: 48000.0)

        // 16000 * (48000 / 16000) = 48000
        #expect(output48k.count == 48000, "16kHz->48kHz 应产生 48000 样点，实际: \(output48k.count)")
    }

    @Test("重采样：线性插值应保持边界值")
    func resampleLinear_ShouldPreserveBoundaryValues() {
        let recorder = AudioRecorder.shared

        // 创建一个明显递增的数组
        var input: [Float] = []
        for i in 0..<100 {
            input.append(Float(i) / 100.0)
        }

        // 重采样：100 -> 200 样点（上采样）
        let output = recorder.resampleLinear(input, from: 100.0, to: 200.0)

        // 第一个样点应该接近 0.0
        #expect(abs(output[0] - 0.0) < 0.01, "第一个样点应接近 0.0，实际: \(output[0])")

        // 最后一个样点应该接近 0.99
        #expect(abs(output.last! - 0.99) < 0.01, "最后一个样点应接近 0.99，实际: \(output.last!)")
    }

    @Test("重采样：无效采样率应返回原数组")
    func resampleLinear_InvalidSampleRates_ShouldReturnInput() {
        let recorder = AudioRecorder.shared

        let input = [0.5, 0.6, 0.7] as [Float]

        // 零采样率
        let output1 = recorder.resampleLinear(input, from: 0.0, to: 16000.0)
        #expect(output1 == input, "零源采样率应返回原数组")

        // 负采样率
        let output2 = recorder.resampleLinear(input, from: -16000.0, to: 16000.0)
        #expect(output2 == input, "负采样率应返回原数组")
    }

    @Test("重采样：微小采样率差异应跳过重采样")
    func resampleLinear_MinimalRateDifference_ShouldSkipResample() {
        let recorder = AudioRecorder.shared

        let input = [0.1, 0.2, 0.3] as [Float]

        // 采样率差异小于 0.5Hz
        let output = recorder.resampleLinear(input, from: 16000.1, to: 16000.3)

        #expect(output == input, "微小采样率差异（<0.5Hz）应跳过重采样")
    }

    // MARK: - 流式场景测试

    @Test("流式场景：模拟 48kHz 设备产生的 chunk 应重采样到 16kHz")
    func streamingScenario_48kDevice_ShouldResampleTo16k() {
        let recorder = AudioRecorder.shared

        // 模拟 48kHz 设备的一个 chunk（约 21ms @ 48kHz = 1024 样点）
        let chunk48k = Array(repeating: Float.random(in: -0.5...0.5), count: 1024)

        // 重采样到 16kHz
        let chunk16k = recorder.resampleLinear(chunk48k, from: 48000.0, to: 16000.0)

        // 1024 * (16000 / 48000) ≈ 341 样点
        let expectedCount = 341
        #expect(chunk16k.count == expectedCount, "48kHz chunk 应重采样到 \(expectedCount) 样点，实际: \(chunk16k.count)")

        // 验证输出在合理范围内（没有放大）
        let maxAbsValue = chunk16k.map { abs($0) }.max() ?? 0
        #expect(maxAbsValue <= 0.5, "重采样后不应引入异常放大")
    }

    @Test("流式场景：模拟 44.1kHz 设备产生的 chunk 应重采样到 16kHz")
    func streamingScenario_44k1Device_ShouldResampleTo16k() {
        let recorder = AudioRecorder.shared

        // 模拟 44.1kHz 设备的一个 chunk（约 23ms @ 44.1kHz = 1024 样点）
        let chunk44k1 = Array(repeating: Float.random(in: -0.3...0.3), count: 1024)

        // 重采样到 16kHz
        let chunk16k = recorder.resampleLinear(chunk44k1, from: 44100.0, to: 16000.0)

        // 1024 * (16000 / 44100) ≈ 371.5 → rounded = 372
        let expectedCount = Int((Double(1024) * 16000.0 / 44100.0).rounded())
        #expect(chunk16k.count == expectedCount, "44.1kHz chunk 应重采样到 \(expectedCount) 样点，实际: \(chunk16k.count)")
    }

    @Test("流式场景：多个 chunk 累积应保持时序正确性")
    func streamingScenario_MultipleChunks_ShouldMaintainTiming() {
        let recorder = AudioRecorder.shared

        // 模拟 3 个连续的 48kHz chunk
        let chunk1 = Array(repeating: Float.random(in: -0.2...0.2), count: 1024)
        let chunk2 = Array(repeating: Float.random(in: -0.2...0.2), count: 1024)
        let chunk3 = Array(repeating: Float.random(in: -0.2...0.2), count: 1024)

        // 分别重采样
        let resampled1 = recorder.resampleLinear(chunk1, from: 48000.0, to: 16000.0)
        let resampled2 = recorder.resampleLinear(chunk2, from: 48000.0, to: 16000.0)
        let resampled3 = recorder.resampleLinear(chunk3, from: 48000.0, to: 16000.0)

        // 每个 chunk 应重采样到相同长度
        #expect(resampled1.count == resampled2.count)
        #expect(resampled2.count == resampled3.count)

        // 验证总长度
        let totalResampled = resampled1.count + resampled2.count + resampled3.count
        #expect(totalResampled > 0, "重采样后的总长度应大于零")
    }
}
