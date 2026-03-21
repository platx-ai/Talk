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

    private init() {
        setupMenuBar()
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

    func updateProcessingStatus(_ status: MenuViewModel.ProcessingStatus) {
        viewModel.processingStatus = status
        viewModel.isRecording = status == .recording

        switch status {
        case .idle:
            floatingIndicator.dismiss()
        case .loadingModel:
            floatingIndicator.updatePhase(.loadingModel)
            floatingIndicator.show()
        case .recording:
            floatingIndicator.updatePhase(.recording(startDate: Date()))
            floatingIndicator.show()
        case .asr:
            floatingIndicator.updatePhase(.recognizing)
            floatingIndicator.show()
        case .polishing:
            floatingIndicator.updatePhase(.polishing)
        case .outputting:
            floatingIndicator.updatePhase(.outputting)
        }
    }

    func updateFloatingAudioLevel(_ level: Float) {
        floatingIndicator.updateAudioLevel(level)
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
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "设置"
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
            historyWindow?.title = "历史记录"
            historyWindow?.contentViewController = NSHostingController(rootView: historyView)
            historyWindow?.center()
            historyWindow?.isReleasedWhenClosed = false
        }

        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("打开历史记录窗口", category: .ui)
    }

    func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName

        NSUserNotificationCenter.default.deliver(notification)
    }
}
