//
//  ToastManager.swift
//  Talk
//
//  Toast 管理器
//

import SwiftUI
import Observation

/// Toast 管理器（全局单例）
@Observable
@MainActor
final class ToastManager {
    static let shared = ToastManager()

    private(set) var isShowing = false
    private(set) var message = ""

    private var hideTask: Task<Void, Never>?

    private init() {}

    /// 显示 Toast
    func show(_ message: String, duration: TimeInterval = 1.5) {
        // 取消之前的隐藏任务
        hideTask?.cancel()

        self.message = message
        self.isShowing = true

        // 设置自动隐藏
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                self.isShowing = false
            }
        }
    }

    /// 隐藏 Toast
    func hide() {
        hideTask?.cancel()
        isShowing = false
    }
}
