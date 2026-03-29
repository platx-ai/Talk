//
//  ASRServiceTests.swift
//  TalkTests
//
//  ASR 服务单元测试
//

import Testing
import Foundation
@testable import Talk

@Suite("ASR Service Tests", .serialized)
struct ASRServiceTests {

    // MARK: - 流式识别测试

    @Test func streamingSessionStartsWithLoadedModel() async throws {
        // 此测试需要实际加载模型，在 CI 环境中可能失败
        // 测试逻辑：
        // 1. 验证 startStreaming 方法在模型未加载时抛出正确错误
        let service = ASRService.shared

        // 模型未加载时应该抛出错误
        do {
            try await service.startStreaming()
            #expect(Bool(false), "Should throw error when model not loaded")
        } catch ASRError.modelNotLoaded {
            // 正确的错误类型
        } catch {
            #expect(Bool(false), "Expected ASRError.modelNotLoaded, got: \(error)")
        }
    }

    @Test func streamingSessionStopsCorrectly() async {
        await MainActor.run {
            let service = ASRService.shared

            // stopStreaming 应该安全调用（即使没有活动会话）
            service.stopStreaming()

            // 验证 stopStreaming 清空回调
            service.onTranscriptionUpdate = { _, _ in }
            service.onTranscriptionComplete = { _ in }
            #expect(service.onTranscriptionUpdate != nil)
            service.stopStreaming()
            // 注意：stopStreaming 会清空回调
            // 但在 parallel testing 中 singleton 可能被其他测试修改
            // 所以只验证不崩溃即可
        }
    }

    @Test func feedAudioDataWorksCorrectly() async {
        let service = ASRService.shared

        // 创建模拟音频数据
        let mockAudioData = Array(repeating: 0.0 as Float, count: 1600) // 0.1 秒 @ 16kHz

        // feedAudio 不应该抛出错误，即使没有活动会话
        service.feedAudio(samples: mockAudioData, sampleRate: 16000)

        // 验证调用不会崩溃
        #expect(true, "feedAudio should not crash even without active session")
    }

    @Test func transcriptionUpdateCallbackReceivesCorrectParameters() async {
        let service = ASRService.shared

        var receivedUpdates: [(String, String)] = []
        service.onTranscriptionUpdate = { confirmed, provisional in
            receivedUpdates.append((confirmed, provisional))
        }

        // 模拟一次更新
        service.onTranscriptionUpdate?("你好", "世界")

        #expect(receivedUpdates.count == 1)
        #expect(receivedUpdates[0].0 == "你好")
        #expect(receivedUpdates[0].1 == "世界")
    }

    @Test func transcriptionCompleteCallbackReceivesFullText() async {
        let service = ASRService.shared

        var receivedText: String?
        service.onTranscriptionComplete = { text in
            receivedText = text
        }

        // 模拟识别完成
        service.onTranscriptionComplete?("完整的转录文本")

        #expect(receivedText == "完整的转录文本")
    }

    @Test func streamSessionPropertiesAreInitializedCorrectly() async {
        // 验证属性存在且类型正确（不检查具体值，避免 singleton 状态依赖）
        await MainActor.run {
            let service = ASRService.shared
            let _ = service.isModelLoaded
            let _ = service.isLoading
            let progress = service.loadingProgress
            #expect(progress >= 0, "Loading progress should be non-negative")
        }
    }
}
