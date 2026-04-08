//
//  FloatingIndicatorWindow.swift
//  Talk
//
//  浮动状态指示窗口
//

import SwiftUI
import AppKit

// MARK: - Floating Indicator State

@Observable
@MainActor
final class FloatingIndicatorState {
    enum Phase: Equatable {
        case loadingModel(name: String = "", progress: Double = -1) // progress < 0 = indeterminate
        case recording(startDate: Date, isEditMode: Bool)
        case recognizing
        case polishing
        case outputting
        case done

        var animationKey: String {
            switch self {
            case .loadingModel: return "loading"
            case .recording: return "recording"
            case .recognizing: return "recognizing"
            case .polishing: return "polishing"
            case .outputting: return "outputting"
            case .done: return "done"
            }
        }
    }

    var phase: Phase = .recording(startDate: Date(), isEditMode: false)
    var audioLevel: Float = 0.0
    var realtimeText: String = ""
}

// MARK: - NSPanel Subclass

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Floating Indicator Window Controller

@MainActor
final class FloatingIndicatorWindow {
    private var panel: FloatingPanel?
    private let state = FloatingIndicatorState()
    private var dismissWorkItem: DispatchWorkItem?

    func show() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        if panel != nil {
            panel?.orderFront(nil)
            return
        }

        // 用 ZStack + clear 背景确保 SwiftUI 层不绘制任何默认背景
        let wrappedView = ZStack {
            Color.clear
            FloatingIndicatorContentView(state: state)
        }
        .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: wrappedView)

        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 80

        // 屏幕上边沿、左右居中，紧贴刘海下方
        let screenFrame = NSScreen.main?.frame ?? .zero
        let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY  // 菜单栏高度（含刘海）
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - menuBarHeight - panelHeight - 4

        let panel = FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        panel.contentView = hostingView

        panel.orderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        // 渐隐消失
        if let panel = panel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                panel.orderOut(nil)
                panel.alphaValue = 1  // 重置为下次使用
                self?.panel = nil
            })
        }
    }

    func updatePhase(_ phase: FloatingIndicatorState.Phase) {
        state.phase = phase

        if case .done = phase {
            let workItem = DispatchWorkItem { [weak self] in
                self?.dismiss()
            }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        } else {
            dismissWorkItem?.cancel()
            dismissWorkItem = nil
        }
    }

    func updateAudioLevel(_ level: Float) {
        state.audioLevel = level
    }

    func updateRealtimeText(_ text: String) {
        state.realtimeText = text
    }

    func clearRealtimeText() {
        state.realtimeText = ""
    }
}

// MARK: - SwiftUI Content View

struct FloatingIndicatorContentView: View {
    var state: FloatingIndicatorState
    @State private var auraRotation: Double = 0
    @State private var pulse: Bool = false
    @State private var wavePhase: Double = 0

    private var auraColors: [Color] {
        switch state.phase {
        case .recording(_, let isEditMode):
            return isEditMode
                ? [.orange, .yellow, .orange.opacity(0.3), .yellow, .orange]
                : [.cyan, .purple, .cyan.opacity(0.3), .purple, .cyan]
        case .recognizing:  return [.blue, .cyan, .blue.opacity(0.3), .cyan, .blue]
        case .polishing:    return [.purple, .indigo, .purple.opacity(0.3), .indigo, .purple]
        case .outputting:   return [.cyan, .mint, .cyan.opacity(0.3), .mint, .cyan]
        case .done:         return [.green, .mint, .green.opacity(0.3), .mint, .green]
        case .loadingModel: return [.white.opacity(0.3), .white.opacity(0.1), .white.opacity(0.3), .white.opacity(0.1), .white.opacity(0.3)]
        }
    }

    private var isActive: Bool {
        if case .done = state.phase { return false }
        return true
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
            textView
            if case .recording = state.phase {
                waveformView
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minWidth: 150)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .clipShape(Capsule())
        .overlay(
            // Aura 光环 — 贴着胶囊边缘，缓慢旋转
            Capsule()
                .strokeBorder(
                    AngularGradient(
                        colors: auraColors,
                        center: .center,
                        startAngle: .degrees(auraRotation),
                        endAngle: .degrees(auraRotation + 360)
                    ),
                    lineWidth: 1.5
                )
                .opacity(isActive ? 0.9 : 0.3)
        )
        .shadow(color: auraColors[0].opacity(isActive ? 0.4 : 0), radius: isActive ? 8 : 0)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                auraRotation = 360
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state.phase.animationKey)
    }

    @ViewBuilder
    private var iconView: some View {
        switch state.phase {
        case .loadingModel(_, let progress) where progress >= 0:
            // 有进度时显示环形进度
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2)
                    .frame(width: 16, height: 16)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
            }
        case .loadingModel:
            ProgressView().controlSize(.small)
        case .recording(_, let isEditMode):
            if isEditMode {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14, weight: .medium))
                    .symbolEffect(.pulse, isActive: true)
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulse ? 1.0 : 0.5)
            }
        case .recognizing:
            Image(systemName: "waveform")
                .foregroundStyle(.primary)
                .font(.system(size: 13, weight: .medium))
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .polishing:
            Image(systemName: "sparkles")
                .foregroundStyle(.primary)
                .font(.system(size: 13, weight: .medium))
                .symbolEffect(.pulse, isActive: true)
        case .outputting:
            Image(systemName: "paperplane.fill")
                .foregroundStyle(.primary)
                .font(.system(size: 13, weight: .medium))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14, weight: .medium))
        }
    }

    @ViewBuilder
    private var textView: some View {
        switch state.phase {
        case .loadingModel(let name, let progress):
            if progress >= 0 {
                Text("\(String(localized: "下载")) \(name) \(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            } else if !name.isEmpty {
                Text("\(String(localized: "加载")) \(name)...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            } else {
                Text(String(localized: "加载模型中..."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
        case .recording(let startDate, let isEditMode):
            if state.realtimeText.isEmpty {
                TimelineView(.periodic(from: startDate, by: 0.5)) { context in
                    let elapsed = context.date.timeIntervalSince(startDate)
                    let minutes = Int(elapsed) / 60
                    let seconds = Int(elapsed) % 60
                    HStack(spacing: 4) {
                        if isEditMode {
                            Text(String(localized: "编辑"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        Text(String(format: "%d:%02d", minutes, seconds))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            } else {
                Text(String(state.realtimeText.suffix(15)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
        case .recognizing:
            if state.realtimeText.isEmpty {
                Text(String(localized: "识别中..."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            } else {
                Text(String(state.realtimeText.suffix(10)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
        case .polishing:
            Text(String(localized: "润色中..."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        case .outputting:
            Text(String(localized: "输出中..."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        case .done:
            Text(String(localized: "完成"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    /// 音频波形 — 多条竖线随音频电平跳动
    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let offset = Double(i) * 0.6
                let height = waveBarHeight(index: i)
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [.primary.opacity(0.6), .primary],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: height)
                    .animation(.easeInOut(duration: 0.1), value: state.audioLevel)
            }
        }
        .frame(height: 20)
    }

    private func waveBarHeight(index: Int) -> CGFloat {
        let level = CGFloat(state.audioLevel)
        let phase = sin(wavePhase + Double(index) * 1.2)
        let base: CGFloat = 3
        let dynamic = level * 17 * (0.5 + 0.5 * CGFloat(phase))
        return max(base, base + dynamic)
    }
}
