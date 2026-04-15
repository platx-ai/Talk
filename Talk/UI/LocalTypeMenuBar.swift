//
//  LocalTypeMenuBar.swift
//  Talk
//
//  菜单栏控制器
//

import SwiftUI
import AppKit

@MainActor
final class LocalTypeMenuBar {
    static let shared = LocalTypeMenuBar()

    private var statusItem: NSStatusItem?
    private var menuBarView: NSHostingController<MenuBarView>?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var popover: NSPopover?
    private let viewModel = MenuViewModel()
    private let floatingIndicator = FloatingIndicatorWindow()
    private let stateMachine = ProcessingStateMachine()
    private var flashCapsulePanel: FloatingPanel?
    private var flashCapsuleDismissWorkItem: DispatchWorkItem?

    private init() {
        setupMenuBar()
        setupHotwordNotificationListener()
        
        // 监听状态变化
        stateMachine.onStateChange = { [weak self] oldState, newState in
            self?.updateUI(for: newState)
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else {
            AppLogger.error("无法创建状态栏项", category: .ui)
            return
        }

        statusItem.button?.action = #selector(statusBarButtonClicked)
        statusItem.button?.target = self

        let view = MenuBarView(viewModel: viewModel)
            .onOpenSettings { [weak self] in self?.openSettings() }
            .onOpenHistory { [weak self] in self?.openHistory() }

        menuBarView = NSHostingController(rootView: view)
        
        if let view = menuBarView?.view {
            view.frame = NSRect(x: 0, y: 0, width: 30, height: 20)
            statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
            statusItem.button?.addSubview(view)
        }

        AppLogger.info("菜单栏设置完成", category: .ui)
    }

    func updateProcessingStatus(_ status: MenuViewModel.ProcessingStatus, isEditMode: Bool = false) {
        let newState = mapToProcessingState(status, isEditMode: isEditMode)
        
        if !stateMachine.transition(to: newState) {
            // 状态转换失败，记录日志但不阻塞
            AppLogger.warning("状态转换失败：\(stateMachine.currentState.description) → \(newState.description)")
        }
    }
    
    /// 将 MenuViewModel.ProcessingStatus 映射到 ProcessingState
    private func mapToProcessingState(_ status: MenuViewModel.ProcessingStatus, isEditMode: Bool) -> ProcessingState {
        switch status {
        case .idle:
            return .idle
        case .loadingModel:
            return .loadingModel(modelName: "Qwen3", progress: 0.5)
        case .recording:
            return .recording(startDate: Date(), isEditMode: isEditMode)
        case .asr:
            return .recognizing
        case .polishing:
            return .polishing
        case .outputting:
            return .outputting
        }
    }
    
    /// 根据状态更新 UI
    private func updateUI(for state: ProcessingState) {
        // 更新 floatingIndicator
        switch state {
        case .idle:
            floatingIndicator.dismiss()
        case .loadingModel(let name, let progress):
            floatingIndicator.updatePhase(.loadingModel(name: name, progress: progress))
            floatingIndicator.show()
        case .recording(let startDate, let isEditMode):
            floatingIndicator.updatePhase(.recording(startDate: startDate, isEditMode: isEditMode))
            floatingIndicator.show()
        case .recognizing:
            floatingIndicator.updatePhase(.recognizing)
            floatingIndicator.show()
        case .polishing:
            floatingIndicator.updatePhase(.polishing)
        case .outputting:
            floatingIndicator.updatePhase(.outputting)
        case .error(let error):
            floatingIndicator.updatePhase(.error(error))
        }
        
        // 更新 viewModel
        viewModel.processingStatus = mapToMenuViewModelStatus(state)
    }
    
    /// 将 ProcessingState 映射回 MenuViewModel.ProcessingStatus
    private func mapToMenuViewModelStatus(_ state: ProcessingState) -> MenuViewModel.ProcessingStatus {
        switch state {
        case .idle: return .idle
        case .loadingModel(let name, let progress): return .loadingModel(name: name, progress: progress)
        case .recording: return .recording
        case .recognizing: return .asr
        case .polishing: return .polishing
        case .outputting: return .outputting
        case .error(let error): return .error(error)
        }
    }

    func updateDownloadProgress(modelName: String, progress: Double) {
        floatingIndicator.updatePhase(.loadingModel(name: modelName, progress: progress))
        floatingIndicator.show()
    }

    func updateFloatingAudioLevel(_ level: Float) {
        floatingIndicator.updateAudioLevel(level)
    }

    func updateFloatingRealtimeText(_ text: String) {
        floatingIndicator.updateRealtimeText(text)
    }

    /// Show "done" on the floating indicator, then auto-dismiss after 1.5s
    func showDoneAndDismiss() {
        viewModel.processingStatus = .idle
        viewModel.isRecording = false
        floatingIndicator.updatePhase(.done)
    }

    @objc private func statusBarButtonClicked() {
        showPopover()
    }

    private func showPopover() {
        guard statusItem != nil else { return }

        let view = MenuBarView(viewModel: viewModel)
            .onOpenSettings { [weak self] in self?.openSettings() }
            .onOpenHistory { [weak self] in self?.openHistory() }

        popover = NSPopover()
        popover?.contentViewController = NSHostingController(rootView: view)
        popover?.behavior = .transient
        popover?.animates = true

        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds,
                          of: button,
                          preferredEdge: .minY)
        }
    }

    private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = String(localized: "设置")
            settingsWindow?.contentViewController = NSHostingController(rootView: settingsView)
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("打开设置窗口", category: .ui)
    }

    private func openHistory() {
        if historyWindow == nil {
            let historyView = HistoryView()
            historyWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            historyWindow?.title = String(localized: "历史记录")
            historyWindow?.contentViewController = NSHostingController(rootView: historyView)
            historyWindow?.center()
            historyWindow?.isReleasedWhenClosed = false
        }

        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("打开历史记录窗口", category: .ui)
    }

    /// Open settings window (called from onboarding "open settings" link)
    func openSettingsFromOnboarding() {
        openSettings()
    }

    func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        // 不播放声音，避免打扰用户
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - 闪电胶囊通知（热词学习反馈）

    private func setupHotwordNotificationListener() {
        NotificationCenter.default.addObserver(
            forName: .hotwordLearned,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let corrections = notification.userInfo?["corrections"] as? [String],
                  !corrections.isEmpty else { return }
            Task { @MainActor in
                self?.showFlashCapsule(corrections: corrections)
            }
        }
    }

    private func showFlashCapsule(corrections: [String]) {
        // 取消上一次的自动消失
        flashCapsuleDismissWorkItem?.cancel()

        let message = corrections.joined(separator: "  ")
        let capsuleView = FlashCapsuleView(message: message)
        let hostingView = NSHostingView(rootView: capsuleView)

        let panelWidth: CGFloat = min(CGFloat(message.count * 12 + 80), 500)
        let panelHeight: CGFloat = 36

        let screenFrame = NSScreen.main?.frame ?? .zero
        let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - menuBarHeight - panelHeight - 8

        if flashCapsulePanel == nil {
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
            flashCapsulePanel = panel
        }

        flashCapsulePanel?.setFrame(
            NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            display: false
        )
        flashCapsulePanel?.contentView = hostingView
        flashCapsulePanel?.alphaValue = 0
        flashCapsulePanel?.orderFront(nil)

        // 淡入
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            flashCapsulePanel?.animator().alphaValue = 1
        }

        // 5 秒后淡出
        let workItem = DispatchWorkItem { [weak self] in
            guard let panel = self?.flashCapsulePanel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
        flashCapsuleDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }
}

// MARK: - 闪电胶囊视图

struct FlashCapsuleView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.yellow)
            Text(String(localized: "已收录"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
