//
//  AppleSpeechServiceTests.swift
//  TalkTests
//
//  Apple Speech Recognition 服务测试
//

import Testing
import Foundation
@testable import Talk

@Suite("Apple Speech Service Tests")
struct AppleSpeechServiceTests {

    @Test @MainActor
    func sharedInstanceExists() {
        let service = AppleSpeechService.shared
        #expect(service != nil)
    }

    @Test @MainActor
    func initialStateIsNotRecognizing() {
        let service = AppleSpeechService.shared
        #expect(!service.isRecognizing)
    }

    @Test @MainActor
    func cancelStreamingDoesNotCrashWhenNotStarted() {
        AppleSpeechService.shared.cancelStreaming()
        #expect(!AppleSpeechService.shared.isRecognizing)
    }

    @Test @MainActor
    func stopStreamingDoesNotCrashWhenNotStarted() {
        AppleSpeechService.shared.stopStreaming()
        #expect(!AppleSpeechService.shared.isRecognizing)
    }

    @Test @MainActor
    func feedAudioSamplesDoesNotCrashWhenNotStarted() {
        // 未开始识别时 feedAudioSamples 不应崩溃
        let samples: [Float] = Array(repeating: 0.0, count: 1024)
        AppleSpeechService.shared.feedAudioSamples(samples, sampleRate: 16000)
    }

    @Test @MainActor
    func callbacksCanBeSetAndCleared() {
        let service = AppleSpeechService.shared

        var updateCalled = false
        var completeCalled = false

        service.onTranscriptionUpdate = { _, _ in updateCalled = true }
        service.onTranscriptionComplete = { _ in completeCalled = true }

        // 回调已设置（不调用，只验证可设置）
        service.onTranscriptionUpdate = nil
        service.onTranscriptionComplete = nil

        #expect(!updateCalled)
        #expect(!completeCalled)
    }
}

@Suite("ASR Engine Settings Tests")
struct ASREngineSettingsTests {

    @Test
    func asrEngineDefaultIsMLXLocal() {
        let settings = AppSettings()
        #expect(settings.asrEngine == .mlxLocal)
    }

    @Test
    func appleSpeechLocaleDefaultIsSystem() {
        let settings = AppSettings()
        #expect(settings.appleSpeechLocale == .system)
    }

    @Test
    func appleSpeechOnDeviceDefaultIsFalse() {
        let settings = AppSettings()
        #expect(settings.appleSpeechOnDevice == false)
    }

    @Test
    func appleSpeechShowRealtimeDefaultIsTrue() {
        let settings = AppSettings()
        #expect(settings.appleSpeechShowRealtime == true)
    }

    @Test
    func appleSpeechLocaleConversion() {
        #expect(AppSettings.AppleSpeechLocale.system.locale == nil)
        #expect(AppSettings.AppleSpeechLocale.zhCN.locale?.identifier == "zh-CN")
        #expect(AppSettings.AppleSpeechLocale.enUS.locale?.identifier == "en-US")
        #expect(AppSettings.AppleSpeechLocale.ja.locale?.identifier == "ja-JP")
        #expect(AppSettings.AppleSpeechLocale.ko.locale?.identifier == "ko-KR")
    }

    @Test
    func asrEngineDisplayNames() {
        #expect(!AppSettings.ASREngine.mlxLocal.displayName.isEmpty)
        #expect(!AppSettings.ASREngine.appleSpeech.displayName.isEmpty)
        #expect(!AppSettings.ASREngine.mlxLocal.subtitle.isEmpty)
        #expect(!AppSettings.ASREngine.appleSpeech.subtitle.isEmpty)
    }
}
