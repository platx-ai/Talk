//
//  ProcessingState.swift
//  Talk
//
//  处理状态定义
//

import Foundation

/// 处理状态
enum ProcessingState: Equatable {
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
            return state == .loadingModel || state == .recording
            
        case .loadingModel:
            return state == .idle || state == .recording
            
        case .recording:
            return state == .recognizing || state == .idle
            
        case .recognizing:
            return state == .polishing || state == .error || state == .idle
            
        case .polishing:
            return state == .outputting || state == .error || state == .idle
            
        case .outputting:
            return state == .idle || state == .error
            
        case .error:
            return state == .idle
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
