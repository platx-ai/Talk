//
//  BenchmarkTests.swift
//  TalkTests
//
//  Performance benchmarks for Talk — model loading, ASR inference, LLM inference, memory.
//  Run with: make benchmark
//  Results written to: /tmp/talk-benchmark-results.txt
//

import Testing
import Foundation
@testable import Talk

// MARK: - Benchmark Output

private let benchmarkOutputPath = "/tmp/talk-benchmark-results.txt"

private func benchLog(_ line: String) {
    NSLog("BENCH: %@", line)
    let entry = line + "\n"
    if let data = entry.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: benchmarkOutputPath) {
            if let handle = FileHandle(forWritingAtPath: benchmarkOutputPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: benchmarkOutputPath, contents: data)
        }
    }
}

@MainActor
private func measureTime(_ label: String, _ block: () async throws -> Void) async rethrows -> TimeInterval {
    let start = CFAbsoluteTimeGetCurrent()
    try await block()
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    benchLog("⏱ [\(label)] \(String(format: "%.2f", elapsed))s")
    return elapsed
}

@MainActor
private func currentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.resident_size) / 1_048_576.0
}

// MARK: - ASR Benchmarks

@Suite("ASR Benchmarks")
struct ASRBenchmarks {

    @Test @MainActor
    func asrModelLoadTime() async throws {
        // Clear previous results
        try? FileManager.default.removeItem(atPath: benchmarkOutputPath)
        benchLog("===== Talk Benchmark Results =====")
        benchLog("Date: \(ISO8601DateFormatter().string(from: Date()))")
        benchLog("macOS: \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)")
        benchLog("")

        let asr = ASRService.shared
        if asr.isModelLoaded { asr.unloadModel() }

        let memBefore = currentMemoryMB()
        let loadTime = try await measureTime("ASR Model Load") {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }
        let memAfter = currentMemoryMB()

        benchLog("📊 ASR Model Load: \(String(format: "%.2f", loadTime))s")
        benchLog("📊 ASR Memory Delta: \(String(format: "%.1f", memAfter - memBefore)) MB")
        benchLog("📊 Total Memory: \(String(format: "%.1f", memAfter)) MB")
        benchLog("")

        #expect(asr.isModelLoaded)
    }

    @Test @MainActor
    func asrInferenceTime() async throws {
        let asr = ASRService.shared
        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }

        let sampleRate = 16000
        let duration = 3.0
        let sampleCount = Int(Double(sampleRate) * duration)
        let silentAudio = [Float](repeating: 0.0, count: sampleCount)

        let inferTime = try await measureTime("ASR Inference (3s silence)") {
            _ = try await asr.transcribe(audio: silentAudio, sampleRate: sampleRate)
        }

        benchLog("📊 ASR Inference (3s audio): \(String(format: "%.2f", inferTime))s")
        benchLog("📊 ASR Real-time Factor: \(String(format: "%.2fx", duration / inferTime))")
        benchLog("")
    }

    @Test @MainActor
    func asrInference5Seconds() async throws {
        let asr = ASRService.shared
        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }

        let sampleRate = 16000
        let duration = 5.0
        let sampleCount = Int(Double(sampleRate) * duration)
        var audio = [Float](repeating: 0.0, count: sampleCount)
        for i in 0..<sampleCount {
            audio[i] = Float.random(in: -0.001...0.001)
        }

        let inferTime = try await measureTime("ASR Inference (5s noise)") {
            _ = try await asr.transcribe(audio: audio, sampleRate: sampleRate)
        }

        benchLog("📊 ASR Inference (5s audio): \(String(format: "%.2f", inferTime))s")
        benchLog("📊 ASR Real-time Factor: \(String(format: "%.2fx", duration / inferTime))")
        benchLog("")
    }
}

// MARK: - LLM Benchmarks

@Suite("LLM Benchmarks")
struct LLMBenchmarks {

    @Test @MainActor
    func llmModelLoadTime() async throws {
        let llm = LLMService.shared
        if llm.isModelLoaded { llm.unloadModel() }

        let memBefore = currentMemoryMB()
        let loadTime = try await measureTime("LLM Model Load") {
            try await llm.loadModel(modelId: "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        }
        let memAfter = currentMemoryMB()

        benchLog("📊 LLM Model Load: \(String(format: "%.2f", loadTime))s")
        benchLog("📊 LLM Memory Delta: \(String(format: "%.1f", memAfter - memBefore)) MB")
        benchLog("📊 Total Memory: \(String(format: "%.1f", memAfter)) MB")
        benchLog("")

        #expect(llm.isModelLoaded)
    }

    @Test @MainActor
    func llmPolishShortText() async throws {
        let llm = LLMService.shared
        if !llm.isModelLoaded {
            try await llm.loadModel(modelId: "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        }

        let input = "嗯我想说的是这个项目呢特别简单就是一个语音输入的工具"

        var output = ""
        let inferTime = try await measureTime("LLM Polish (short)") {
            output = try await llm.polish(text: input, intensity: .medium)
        }

        benchLog("📊 LLM Polish (short, \(input.count) chars): \(String(format: "%.2f", inferTime))s")
        benchLog("📊 LLM Input:  \(input)")
        benchLog("📊 LLM Output: \(output)")
        benchLog("")
    }

    @Test @MainActor
    func llmPolishLongText() async throws {
        let llm = LLMService.shared
        if !llm.isModelLoaded {
            try await llm.loadModel(modelId: "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        }

        let input = "嗯那个就是我们这个项目呢主要是做一个语音输入的工具啊然后呢它的核心特点就是完全本地运行不需要联网嗯基于Apple的MLX框架然后支持中英文的语音识别啊还有一个文本润色的功能就是把你说的话呃整理成比较规范的书面语然后直接粘贴到你当前使用的应用里面"

        var output = ""
        let inferTime = try await measureTime("LLM Polish (long)") {
            output = try await llm.polish(text: input, intensity: .medium)
        }

        benchLog("📊 LLM Polish (long, \(input.count) chars): \(String(format: "%.2f", inferTime))s")
        benchLog("📊 LLM Input:  \(input.prefix(60))...")
        benchLog("📊 LLM Output: \(output.prefix(60))...")
        benchLog("")
    }
}

// MARK: - End-to-End Pipeline Benchmark

@Suite("Pipeline Benchmarks")
struct PipelineBenchmarks {

    @Test @MainActor
    func fullPipelineWithSilentAudio() async throws {
        let asr = ASRService.shared
        let llm = LLMService.shared

        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }
        if !llm.isModelLoaded {
            try await llm.loadModel(modelId: "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        }

        let sampleRate = 16000
        let duration = 3.0
        let sampleCount = Int(Double(sampleRate) * duration)
        let silentAudio = [Float](repeating: 0.0, count: sampleCount)

        let totalStart = CFAbsoluteTimeGetCurrent()

        let asrStart = CFAbsoluteTimeGetCurrent()
        let rawText = try await asr.transcribe(audio: silentAudio, sampleRate: sampleRate)
        let asrTime = CFAbsoluteTimeGetCurrent() - asrStart

        let llmStart = CFAbsoluteTimeGetCurrent()
        let polished = try await llm.polish(text: rawText.isEmpty ? "测试文本" : rawText, intensity: .medium)
        let llmTime = CFAbsoluteTimeGetCurrent() - llmStart

        let totalTime = CFAbsoluteTimeGetCurrent() - totalStart

        benchLog("📊 ===== Full Pipeline =====")
        benchLog("📊 ASR Time:    \(String(format: "%.2f", asrTime))s")
        benchLog("📊 LLM Time:    \(String(format: "%.2f", llmTime))s")
        benchLog("📊 Total Time:  \(String(format: "%.2f", totalTime))s")
        benchLog("📊 Memory:      \(String(format: "%.1f", currentMemoryMB())) MB")
        benchLog("📊 ASR Output:  \(rawText.isEmpty ? "(empty)" : rawText)")
        benchLog("📊 LLM Output:  \(polished)")
        benchLog("📊 ===========================")
        benchLog("")
    }

    @Test @MainActor
    func memoryAfterUnload() async throws {
        let asr = ASRService.shared
        let llm = LLMService.shared

        if !asr.isModelLoaded {
            try await asr.loadModel(modelId: "mlx-community/Qwen3-ASR-0.6B-4bit")
        }
        if !llm.isModelLoaded {
            try await llm.loadModel(modelId: "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        }

        let memLoaded = currentMemoryMB()

        asr.unloadModel()
        llm.unloadModel()
        autoreleasepool {}

        let memUnloaded = currentMemoryMB()

        benchLog("📊 ===== Memory =====")
        benchLog("📊 Models loaded:   \(String(format: "%.1f", memLoaded)) MB")
        benchLog("📊 Models unloaded: \(String(format: "%.1f", memUnloaded)) MB")
        benchLog("📊 Memory freed:    \(String(format: "%.1f", memLoaded - memUnloaded)) MB")
        benchLog("📊 ====================")
    }
}
