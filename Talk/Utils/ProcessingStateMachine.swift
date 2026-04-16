//
//  ProcessingStateMachine.swift
//  Talk
//
//  处理状态机 - 管理状态转换并记录日志
//

import Foundation
import OSLog

/// 处理状态机 — 管理状态转换并记录日志
@MainActor
final public class ProcessingStateMachine {
    private(set) var currentState: ProcessingState = .idle
    private let logger = Logger(subsystem: "com.talk.app", category: "StateMachine")
    
    var onStateChange: ((ProcessingState, ProcessingState) -> Void)?
    
    /// 尝试转换状态
    /// - Parameter newState: 目标状态
    /// - Returns: 是否转换成功
    func transition(to newState: ProcessingState) -> Bool {
        guard self.currentState.canTransition(to: newState) else {
            logger.warning("非法状态转换：\(self.currentState.description) → \(newState.description)")
            return false
        }
        
        let oldState = self.currentState
        self.currentState = newState
        
        logger.info("状态转换：\(oldState.description) → \(newState.description)")
        onStateChange?(oldState, newState)
        
        return true
    }
    
    /// 强制转换状态（仅用于错误恢复）
    func forceTransition(to newState: ProcessingState) {
        let oldState = currentState
        currentState = newState
        logger.warning("强制状态转换：\(oldState.description) → \(newState.description)")
        onStateChange?(oldState, newState)
    }
    
    /// 重置为空闲状态
    func reset() {
        transition(to: .idle)
    }
    
    /// 检查是否在忙碌状态
    var isBusy: Bool {
        switch self.currentState {
        case .idle, .error: return false
        default: return true
        }
    }
}
