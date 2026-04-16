//
//  TalkError.swift
//  Talk
//
//  统一错误类型
//

import Foundation

/// Talk 统一错误类型
public enum TalkError: LocalizedError, Equatable {
    // MARK: - 模型相关
    case modelNotLoaded(modelName: String)
    case modelDownloadFailed(modelName: String, reason: String)
    case modelLoadTimeout(modelName: String)
    
    // MARK: - 音频相关
    case audioCaptureFailed(reason: String)
    case audioDeviceNotFound(deviceID: String)
    case audioPermissionDenied
    
    // MARK: - 推理相关
    case inferenceFailed(step: InferenceStep, reason: String)
    case inferenceTimeout(step: InferenceStep)
    
    // MARK: - 权限相关
    case permissionDenied(permission: PermissionType)
    case permissionNotGranted(permission: PermissionType)
    
    // MARK: - 文件相关
    case fileNotFound(path: String)
    case fileWriteFailed(path: String, reason: String)
    case fileReadFailed(path: String, reason: String)
    
    // MARK: - 通用
    case unknown(reason: String)
    
    public enum InferenceStep: String {
        case asr = "语音识别"
        case llm = "文本润色"
        case output = "文本注入"
    }
    
    public enum PermissionType: String {
        case microphone = "麦克风"
        case accessibility = "辅助功能"
        case camera = "摄像头"
    }
    
    // MARK: - LocalizedError 实现
    
    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let model):
            return String(localized: "模型未加载：\(model)")
        case .modelDownloadFailed(let model, let reason):
            return String(localized: "模型下载失败（\(model)）：\(reason)")
        case .modelLoadTimeout(let model):
            return String(localized: "模型加载超时：\(model)")
        case .audioCaptureFailed(let reason):
            return String(localized: "音频捕获失败：\(reason)")
        case .audioDeviceNotFound(let deviceID):
            return String(localized: "未找到音频设备：\(deviceID)")
        case .audioPermissionDenied:
            return String(localized: "麦克风权限被拒绝")
        case .inferenceFailed(let step, let reason):
            return String(localized: "\(step.rawValue)失败：\(reason)")
        case .inferenceTimeout(let step):
            return String(localized: "\(step.rawValue)超时")
        case .permissionDenied(let permission):
            return String(localized: "\(permission.rawValue)权限被拒绝")
        case .permissionNotGranted(let permission):
            return String(localized: "未授予\(permission.rawValue)权限")
        case .fileNotFound(let path):
            return String(localized: "文件不存在：\(path)")
        case .fileWriteFailed(let path, let reason):
            return String(localized: "文件写入失败（\(path)）：\(reason)")
        case .fileReadFailed(let path, let reason):
            return String(localized: "文件读取失败（\(path)）：\(reason)")
        case .unknown(let reason):
            return String(localized: "未知错误：\(reason)")
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .modelNotLoaded, .modelLoadTimeout:
            return String(localized: "模型尚未加载完成，请稍后重试")
        case .modelDownloadFailed:
            return String(localized: "网络连接问题或模型文件损坏")
        case .audioPermissionDenied, .permissionDenied:
            return String(localized: "请在系统设置中授予相应权限")
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .modelNotLoaded, .modelLoadTimeout:
            return String(localized: "等待模型加载完成后重试")
        case .modelDownloadFailed:
            return String(localized: "检查网络连接后重新下载")
        case .audioPermissionDenied, .permissionDenied:
            return String(localized: "打开系统设置 → 隐私与安全性 → 授予权限")
        case .audioDeviceNotFound:
            return String(localized: "连接音频设备或在设置中选择其他输入设备")
        case .inferenceFailed, .inferenceTimeout:
            return String(localized: "重试或重启应用")
        default:
            return nil
        }
    }
}

/// 用户可执行的恢复操作
public enum RecoveryAction {
    case retry(action: () async throws -> Void)
    case openSettings
    case downloadModel
    case restartApp
    case ignore
    
    var buttonTitle: String {
        switch self {
        case .retry: return String(localized: "重试")
        case .openSettings: return String(localized: "打开设置")
        case .downloadModel: return String(localized: "重新下载")
        case .restartApp: return String(localized: "重启应用")
        case .ignore: return String(localized: "忽略")
        }
    }
}
