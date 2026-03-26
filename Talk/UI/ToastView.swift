//
//  ToastView.swift
//  Talk
//
//  Toast 提示组件
//

import SwiftUI

/// Toast 视图
struct ToastView: View {
    @State private var manager = ToastManager.shared

    var body: some View {
        if manager.isShowing {
            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Text(manager.message)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.8))
                                .shadow(radius: 4)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    Spacer()
                }
                .padding(.bottom, 40)
            }
            .animation(.easeOut(duration: 0.3), value: manager.isShowing)
        }
    }
}

// MARK: - View Extension for Toast

extension View {
    /// 显示 Toast 提示
    func toast() -> some View {
        ZStack(alignment: .bottom) {
            self
            ToastView()
        }
    }
}
