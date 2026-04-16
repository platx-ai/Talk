//
//  ProcessingState.swift
//  Talk
//
//  处理状态定义
//

import Foundation

/// 处理状态
public enum ProcessingState: Equatable {
    case idle
    case loadingModel(modelName: String, progress: Double)
    case recording(startDate: Date, isEditMode: Bool)
    case recognizing
    case polishing
    case outputting
    case error(TalkError)
    
    /// 定义允许的状态转换
    func canTransition(to state: ProcessingState) -> Bool {
        switch self {
        case .idle:
            if case .loadingModel = state { return true }
            if case .recording = state { return true }
            return false
            
        case .loadingModel:
            if case .idle = state { return true }
            if case .recording = state { return true }
            return false
            
        case .recording:
            if case .recognizing = state { return true }
            if case .idle = state { return true }
            return false
            
        case .recognizing:
            if case .polishing = state { return true }
            if case .error = state { return true }
            if case .idle = state { return true }
            return false
            
        case .polishing:
            if case .outputting = state { return true }
            if case .error = state { return true }
            if case .idle = state { return true }
            return false
            
        case .outputting:
            if case .idle = state { return true }
            if case .error = state { return true }
            return false
            
        case .error:
            if case .idle = state { return true }
            return false
        }
    }
    
    /// 获取状态的描述文本
    var description: String {
        switch self {
        case .idle: return String(localized: "空闲")
        case .loadingModel(let name, let progress):
            return String(localized: "加载模型：\(name) (\(Int(progress * 100))%)")
        case .recording: return String(localized: "录音中")
        case .recognizing: return String(localized: "识别中")
        case .polishing: return String(localized: "润色中")
        case .outputting: return String(localized: "输出中")
        case .error(let error): return String(localized: "错误：\(error.errorDescription ?? "")")
        }
    }
}
