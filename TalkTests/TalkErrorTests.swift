//
//  TalkErrorTests.swift
//  Talk
//
//  统一错误类型测试
//

import Testing
import Foundation
@testable import Talk

@Suite("TalkError Tests")
struct TalkErrorTests {
    
    @Test("模型未加载错误描述")
    func modelNotLoadedErrorDescription() {
        let error = TalkError.modelNotLoaded(modelName: "Qwen3-ASR")
        #expect(error.errorDescription == String(localized: "模型未加载：Qwen3-ASR"))
    }
    
    @Test("模型下载失败错误描述")
    func modelDownloadFailedErrorDescription() {
        let error = TalkError.modelDownloadFailed(
            modelName: "Qwen3-LLM",
            reason: "网络超时"
        )
        #expect(error.errorDescription == String(localized: "模型下载失败（Qwen3-LLM）：网络超时"))
    }
    
    @Test("推理失败错误描述")
    func inferenceFailedErrorDescription() {
        let error = TalkError.inferenceFailed(
            step: .asr,
            reason: "内存不足"
        )
        #expect(error.errorDescription == String(localized: "语音识别失败：内存不足"))
    }
    
    @Test("权限拒绝错误描述")
    func permissionDeniedErrorDescription() {
        let error = TalkError.permissionDenied(permission: .microphone)
        #expect(error.errorDescription == String(localized: "麦克风权限被拒绝"))
        #expect(error.recoverySuggestion == String(localized: "打开系统设置 → 隐私与安全性 → 授予权限"))
    }
    
    @Test("恢复建议验证")
    func recoverySuggestions() {
        let modelError = TalkError.modelNotLoaded(modelName: "Test")
        #expect(modelError.recoverySuggestion == String(localized: "等待模型加载完成后重试"))
        
        let downloadError = TalkError.modelDownloadFailed(
            modelName: "Test",
            reason: "Failed"
        )
        #expect(downloadError.recoverySuggestion == String(localized: "检查网络连接后重新下载"))
        
        let unknownError = TalkError.unknown(reason: "Test")
        #expect(unknownError.recoverySuggestion == nil)
    }
    
    @Test("RecoveryAction 按钮标题")
    func recoveryActionTitles() {
        #expect(RecoveryAction.retry {}.buttonTitle == String(localized: "重试"))
        #expect(RecoveryAction.openSettings.buttonTitle == String(localized: "打开设置"))
        #expect(RecoveryAction.downloadModel.buttonTitle == String(localized: "重新下载"))
        #expect(RecoveryAction.restartApp.buttonTitle == String(localized: "重启应用"))
        #expect(RecoveryAction.ignore.buttonTitle == String(localized: "忽略"))
    }
    
    @Test("音频设备未找到错误")
    func audioDeviceNotFound() {
        let error = TalkError.audioDeviceNotFound(deviceID: "test-device")
        #expect(error.errorDescription == String(localized: "未找到音频设备：test-device"))
    }
    
    @Test("推理超时错误")
    func inferenceTimeout() {
        let error = TalkError.inferenceTimeout(step: .llm)
        #expect(error.errorDescription == String(localized: "文本润色超时"))
        #expect(error.recoverySuggestion == String(localized: "重试或重启应用"))
    }
}
