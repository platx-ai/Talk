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
    enum Phase {
        case loadingModel
        case recording(startDate: Date)
        case recognizing
        case polishing
        case outputting
        case done
    }

    var phase: Phase = .recording(startDate: Date())
    var audioLevel: Float = 0.0
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

        let contentView = FloatingIndicatorContentView(state: state)
        let hostingView = NSHostingView(rootView: contentView)

        let panelWidth: CGFloat = 220
        let panelHeight: CGFloat = 56

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight - 12

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
        panel.hasShadow = true
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
        panel?.orderOut(nil)
        panel = nil
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
}

// MARK: - SwiftUI Content View

struct FloatingIndicatorContentView: View {
    var state: FloatingIndicatorState

    var body: some View {
        HStack(spacing: 8) {
            iconView
            textView
            if case .recording = state.phase {
                audioLevelBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minWidth: 140)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(6)
    }

    @ViewBuilder
    private var iconView: some View {
        switch state.phase {
        case .loadingModel:
            ProgressView()
                .controlSize(.small)
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: true)
                .font(.system(size: 14, weight: .medium))
        case .recognizing:
            ProgressView()
                .controlSize(.small)
        case .polishing:
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .font(.system(size: 14, weight: .medium))
                .symbolEffect(.pulse, isActive: true)
        case .outputting:
            Image(systemName: "paperplane.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 14, weight: .medium))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14, weight: .medium))
        }
    }

    @ViewBuilder
    private var textView: some View {
        switch state.phase {
        case .loadingModel:
            Text("加载模型中...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        case .recording(let startDate):
            TimelineView(.periodic(from: startDate, by: 0.5)) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                let minutes = Int(elapsed) / 60
                let seconds = Int(elapsed) % 60
                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        case .recognizing:
            Text("识别中...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        case .polishing:
            Text("润色中...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        case .outputting:
            Text("输出中...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        case .done:
            Text("完成")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var audioLevelBar: some View {
        GeometryReader { geo in
            let level = CGFloat(state.audioLevel)
            let barColor: Color = level > 0.7 ? .yellow : .green
            RoundedRectangle(cornerRadius: 2)
                .fill(barColor.opacity(0.8))
                .frame(width: max(2, geo.size.width * level), height: geo.size.height)
                .animation(.linear(duration: 0.08), value: state.audioLevel)
        }
        .frame(width: 50, height: 6)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.1))
        )
    }
}
