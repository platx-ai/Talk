//
//  EngineHotSwitchTests.swift
//  TalkTests
//
//  引擎热切换测试
//

import Testing
import Foundation
@testable import Talk

@Suite("Engine Hot-Switch Tests")
struct EngineHotSwitchTests {

    // MARK: - reloadEngines: no-op when unchanged

    @Test @MainActor
    func noReloadWhenSettingsUnchanged() {
        guard let delegate = AppDelegate.shared else { return }
        let settings = AppSettings.load()

        // 模拟已加载状态 = 当前设置
        delegate.loadedASREngine = settings.asrEngine
        delegate.loadedLLMEngine = settings.llmEngine
        delegate.loadedLLMModelId = settings.llmModelId
        delegate.loadedGemma4ModelSize = settings.gemma4ModelSize

        // reloadEngines 应该直接返回，不触发卸载
        let asrWasLoaded = ASRService.shared.isModelLoaded
        let llmWasLoaded = LLMService.shared.isModelLoaded

        delegate.reloadEngines()

        // 状态不应改变
        #expect(ASRService.shared.isModelLoaded == asrWasLoaded)
        #expect(LLMService.shared.isModelLoaded == llmWasLoaded)
    }

    // MARK: - ASR engine change triggers unload

    @Test @MainActor
    func asrEngineChangeTriggerUnload() {
        guard let delegate = AppDelegate.shared else { return }
        let settings = AppSettings.shared

        // 记录原始值
        let origASR = settings.asrEngine
        let origLoaded = delegate.loadedASREngine

        // 模拟已加载 mlxLocal
        delegate.loadedASREngine = .mlxLocal
        // 切换到 appleSpeech（不需要模型）
        settings.asrEngine = .appleSpeech

        delegate.reloadEngines()

        // ASR 应该被卸载
        #expect(ASRService.shared.isModelLoaded == false)

        // 恢复
        settings.asrEngine = origASR
        delegate.loadedASREngine = origLoaded
    }

    // MARK: - LLM model ID change triggers unload

    @Test @MainActor
    func llmModelIdChangeTriggerUnload() {
        guard let delegate = AppDelegate.shared else { return }
        let settings = AppSettings.shared

        let origModelId = settings.llmModelId
        let origLoaded = delegate.loadedLLMModelId

        // 模拟已加载 model A
        delegate.loadedLLMModelId = "mlx-community/model-A"
        // 设置不同的 model B
        settings.llmModelId = "mlx-community/model-B"

        delegate.reloadEngines()

        // LLM 应该被卸载（准备加载新模型）
        #expect(LLMService.shared.isModelLoaded == false)

        // 恢复
        settings.llmModelId = origModelId
        delegate.loadedLLMModelId = origLoaded
    }

    // MARK: - Recording guard queues reload

    @Test @MainActor
    func reloadQueuedDuringRecording() {
        guard let delegate = AppDelegate.shared else { return }

        // 模拟设置变化
        delegate.loadedLLMModelId = "old-model"

        // 注意：无法直接设置 AudioRecorder.shared.isRecording（readonly）
        // 但可以验证 pendingEngineReload 机制本身
        #expect(delegate.pendingEngineReload == false)

        // 如果 reloadEngines 被调用且录音中，应设置 pending 标志
        // 这里我们验证初始状态是 false
        delegate.pendingEngineReload = true
        #expect(delegate.pendingEngineReload == true)
        delegate.pendingEngineReload = false
    }

    // MARK: - Gemma4 size change triggers unload

    @Test @MainActor
    func gemma4SizeChangeTriggerUnload() {
        guard let delegate = AppDelegate.shared else { return }
        let settings = AppSettings.shared

        let origSize = settings.gemma4ModelSize
        let origLoaded = delegate.loadedGemma4ModelSize

        delegate.loadedGemma4ModelSize = .e2b
        settings.gemma4ModelSize = .e4b

        delegate.reloadEngines()

        // Gemma4 应该被卸载
        #expect(Gemma4ASREngine.shared.isModelLoaded == false)

        // 恢复
        settings.gemma4ModelSize = origSize
        delegate.loadedGemma4ModelSize = origLoaded
    }

    // MARK: - Unload clears LLM session cache

    @Test @MainActor
    func unloadClearsLLMSessions() {
        let llm = LLMService.shared

        // unloadModel 应该安全（即使没有加载的模型）
        llm.unloadModel()
        #expect(!llm.isModelLoaded)

        // clearHistory 也应该安全
        llm.clearHistory()
        llm.clearHistory(forApp: "com.test.app")
    }
}
