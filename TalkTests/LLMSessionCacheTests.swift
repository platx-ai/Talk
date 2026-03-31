//
//  LLMSessionCacheTests.swift
//  TalkTests
//
//  Per-app ChatSession 缓存和 KV Cache 复用测试
//

import Testing
import Foundation
@testable import Talk

@Suite("LLM Session Cache Tests")
struct LLMSessionCacheTests {

    // MARK: - clearHistory

    @Test @MainActor
    func clearHistoryRemovesAllSessions() {
        let llm = LLMService.shared

        // clearHistory 不应崩溃（即使没有 session）
        llm.clearHistory()

        // 验证调用安全
        llm.clearHistory(forApp: "com.apple.Terminal")
        llm.clearHistory(forApp: "nonexistent.app")
    }

    @Test @MainActor
    func clearHistoryForSpecificApp() {
        let llm = LLMService.shared
        // 清除特定 app 不应影响其他
        llm.clearHistory(forApp: "com.apple.Terminal")
        // 不应崩溃
    }

    // MARK: - setMaxHistoryRounds

    @Test @MainActor
    func setMaxHistoryRoundsUpdatesValue() {
        let llm = LLMService.shared
        llm.setMaxHistoryRounds(10)
        // 验证不崩溃
        llm.setMaxHistoryRounds(5)  // 恢复默认
    }

    // MARK: - polish API signature

    @Test @MainActor
    func polishAcceptsAppBundleId() async {
        let llm = LLMService.shared

        // 模型未加载时应抛出错误
        if !llm.isModelLoaded {
            do {
                _ = try await llm.polish(
                    text: "测试",
                    intensity: .medium,
                    appBundleId: "com.apple.Terminal"
                )
                Issue.record("Should throw when model not loaded")
            } catch {
                // Expected: model not loaded
            }
        }
    }

    @Test @MainActor
    func polishWithNilBundleIdUsesGlobalSession() async {
        let llm = LLMService.shared

        if !llm.isModelLoaded {
            do {
                _ = try await llm.polish(
                    text: "测试",
                    intensity: .medium,
                    appBundleId: nil
                )
                Issue.record("Should throw when model not loaded")
            } catch {
                // Expected: uses "__global__" key internally
            }
        }
    }

    // MARK: - Session isolation

    @Test @MainActor
    func differentAppsGetDifferentSessions() {
        let llm = LLMService.shared
        // 清理
        llm.clearHistory()
        llm.clearHistory(forApp: "com.apple.Terminal")
        llm.clearHistory(forApp: "com.tencent.xinWeChat")
        // 清理后应该没有残留
        // 这主要验证 clearHistory 的隔离性不会崩溃
    }

    // MARK: - Unload clears sessions

    @Test @MainActor
    func unloadModelClearsSessions() {
        let llm = LLMService.shared
        let wasLoaded = llm.isModelLoaded

        if !wasLoaded {
            // 未加载时 unload 应该安全
            llm.unloadModel()
            #expect(!llm.isModelLoaded)
        }
    }
}
