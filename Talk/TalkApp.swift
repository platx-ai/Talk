//
//  TalkApp.swift
//  Talk
//
//  应用主入口
//

import SwiftUI
import AppKit
import AVFoundation
import Carbon

@main
struct TalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - 应用委托

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    private var statusBar: LocalTypeMenuBar?
    private var targetApp: NSRunningApplication?
    private var selectedTextBeforeRecording: String?
    private var idleUnloadTimer: Timer?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        AppLogger.info("========================================", category: .general)
        AppLogger.info("Talk 应用启动", category: .general)
        AppLogger.info("macOS 版本: \(ProcessInfo.processInfo.operatingSystemVersionString)", category: .general)

        let settings = AppSettings.load()
        AppLogger.cleanOldLogs()

        setupMenuBar()

        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }

        setupHotKey(settings: settings)
        initializeServices(settings: settings)
        setupMicrophonePermission()
        TextInjector.requestAccessibilityPermissionIfNeeded()

        AppLogger.info("应用初始化完成", category: .general)
        AppLogger.info("========================================", category: .general)
    }

    // MARK: - 空闲卸载

    /// Reset the idle timer — called after each successful recording/processing
    private func resetIdleTimer() {
        idleUnloadTimer?.invalidate()
        let minutes = AppSettings.shared.idleUnloadMinutes
        guard minutes > 0 else { return }  // disabled

        idleUnloadTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.unloadIdleModels()
            }
        }
    }

    private func unloadIdleModels() {
        guard ASRService.shared.isModelLoaded || LLMService.shared.isModelLoaded else { return }
        AppLogger.info("空闲超时，卸载模型以释放内存", category: .general)
        ASRService.shared.unloadModel()
        LLMService.shared.unloadModel()
        isModelsReady = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("应用即将退出", category: .general)
        HotKeyManager.shared.unregisterHotKey()
        ASRService.shared.unloadModel()
        LLMService.shared.unloadModel()
        AudioRecorder.shared.cancelRecording()
    }

    // MARK: - 初始化服务

    private(set) var isModelsReady = false

    private func initializeServices(settings: AppSettings) {
        if let reason = MLXRuntimeValidator.missingMetalLibraryReason() {
            AppLogger.error("启动预加载已跳过: \(reason)", category: .model)
            return
        }

        let bundled = resolveBundledModelSources()
        let llmModelId = bundled.llmModelPath ?? settings.llmModelId

        Task {
            statusBar?.updateProcessingStatus(.loadingModel)

            AppLogger.info("开始加载 ASR 模型...", category: .general)
            do {
                try await ASRService.shared.loadModel(modelId: settings.asrModelId, bundleResourcesURL: bundled.asrBundleResourcesURL)
                AppLogger.info("ASR 模型加载完成", category: .general)
            } catch {
                AppLogger.error("ASR 模型加载失败: \(error.localizedDescription)", category: .general)
            }

            AppLogger.info("开始加载 LLM 模型...", category: .general)
            do {
                try await LLMService.shared.loadModel(modelId: llmModelId)
                AppLogger.info("LLM 模型加载完成", category: .general)
            } catch {
                AppLogger.error("LLM 模型加载失败: \(error.localizedDescription)", category: .general)
            }

            isModelsReady = ASRService.shared.isModelLoaded && LLMService.shared.isModelLoaded
            statusBar?.updateProcessingStatus(.idle)

            if isModelsReady {
                AppLogger.info("所有模型已就绪", category: .general)
                self.resetIdleTimer()
            } else {
                AppLogger.warning("部分模型加载失败，功能可能受限", category: .general)
            }
        }
    }

    // MARK: - 菜单栏

    private func setupMenuBar() {
        statusBar = LocalTypeMenuBar.shared
    }

    // MARK: - 引导流程

    private func showOnboarding() {
        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.dismissOnboarding()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Talk"
        window.contentViewController = NSHostingController(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
        AppLogger.info("显示引导流程窗口", category: .ui)
    }

    private func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        AppLogger.info("引导流程完成", category: .ui)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let window = notification.object as? NSWindow,
                  window === onboardingWindow else { return }
            // User closed the onboarding window directly; mark as completed
            AppSettings.shared.hasCompletedOnboarding = true
            onboardingWindow = nil
            AppLogger.info("用户关闭引导窗口，标记为已完成", category: .ui)
        }
    }

    // MARK: - 热键

    private func setupHotKey(settings: AppSettings) {
        let triggerMode: HotKeyManager.TriggerMode = settings.recordingTriggerMode == .pushToTalk ? .pushToTalk : .toggle
        HotKeyManager.shared.setTriggerMode(triggerMode)

        let combo = settings.recordingHotkey
        let hotKey = HotKeyManager.HotKeyConfiguration(modifiers: combo.carbonModifiers, keyCode: combo.carbonKeyCode)
        HotKeyManager.shared.registerHotKey(hotKey)

        Task { @MainActor in
            HotKeyManager.shared.onHotKeyPressed = { [weak self] in self?.handleHotKeyPressed() }
            HotKeyManager.shared.onHotKeyReleased = { [weak self] in self?.handleHotKeyReleased() }
        }

        AppLogger.info("热键设置完成: \(combo.displayString)", category: .general)
    }

    func reloadHotKeyFromSettings() {
        let settings = AppSettings.load()
        AppLogger.info("重新加载热键: \(settings.recordingHotkey.displayString)", category: .hotkey)
        setupHotKey(settings: settings)
    }

    /// 直接应用快捷键，不经过 UserDefaults 来回读取
    func applyHotKey(_ combo: HotKeyCombo, triggerMode: AppSettings.RecordingTriggerMode) {
        let mode: HotKeyManager.TriggerMode = triggerMode == .pushToTalk ? .pushToTalk : .toggle
        HotKeyManager.shared.setTriggerMode(mode)

        let hotKey = HotKeyManager.HotKeyConfiguration(modifiers: combo.carbonModifiers, keyCode: combo.carbonKeyCode)
        HotKeyManager.shared.registerHotKey(hotKey)

        Task { @MainActor in
            HotKeyManager.shared.onHotKeyPressed = { [weak self] in self?.handleHotKeyPressed() }
            HotKeyManager.shared.onHotKeyReleased = { [weak self] in self?.handleHotKeyReleased() }
        }

        AppLogger.info("直接应用热键: \(combo.displayString)", category: .hotkey)
    }

    // MARK: - 热键处理

    @MainActor
    private func handleHotKeyPressed() {
        Task {
            if await HotKeyManager.shared.triggerMode == .pushToTalk {
                _ = await startRecording(trigger: "热键")
            } else {
                if AudioRecorder.shared.isRecording {
                    _ = await stopRecordingAndProcess(trigger: "热键")
                } else {
                    _ = await startRecording(trigger: "热键")
                }
            }
        }
    }

    @MainActor
    private func handleHotKeyReleased() {
        Task { _ = await stopRecordingAndProcess(trigger: "热键") }
    }

    func startRecordingFromMenuBar() async -> Bool { await startRecording(trigger: "菜单栏") }
    func stopRecordingFromMenuBar() async -> Bool { await stopRecordingAndProcess(trigger: "菜单栏") }

    private func startRecording(trigger: String) async -> Bool {
        guard let statusBar = statusBar else { return false }

        // 麦克风权限检查
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                showMicrophonePermissionAlert()
                return false
            }
        case .denied, .restricted:
            showMicrophonePermissionAlert()
            return false
        case .authorized:
            break
        @unknown default:
            break
        }

        // 模型未就绪时，提示用户并拒绝录音
        if !isModelsReady && (ASRService.shared.isLoading || LLMService.shared.isLoading) {
            statusBar.updateProcessingStatus(.loadingModel)
            statusBar.showNotification(title: "模型加载中", message: "请等待模型加载完成后再试")
            AppLogger.info("\(trigger)触发：模型尚未就绪，拒绝录音", category: .ui)
            return false
        }

        if AudioRecorder.shared.isRecording {
            statusBar.updateProcessingStatus(.recording)
            return false
        }
        do {
            targetApp = NSWorkspace.shared.frontmostApplication
            // 只用 Accessibility API 捕获（不阻塞），不 fallback 到 Cmd+C
            selectedTextBeforeRecording = captureSelectedTextViaAccessibility()
            if let sel = selectedTextBeforeRecording {
                AppLogger.info("捕获到选中文本: \(sel.prefix(50))...", category: .ui)
            }
            let settings = AppSettings.load()
            AudioRecorder.shared.selectedDeviceUID = settings.selectedAudioDeviceUID
            AudioRecorder.shared.onAudioLevel = { [weak statusBar] level in
                statusBar?.updateFloatingAudioLevel(level)
            }
            try AudioRecorder.shared.startRecording(sampleRate: 16000)
            statusBar.updateProcessingStatus(.recording)
            AppLogger.info("\(trigger)触发：开始录音，目标应用: \(targetApp?.localizedName ?? "unknown")", category: .ui)
            return true
        } catch {
            AppLogger.error("\(trigger)开始录音失败: \(error.localizedDescription)", category: .ui)
            statusBar.showNotification(title: "录音失败", message: error.localizedDescription)
            statusBar.updateProcessingStatus(.idle)
            return false
        }
    }

    private func stopRecordingAndProcess(trigger: String) async -> Bool {
        guard let statusBar = statusBar else { return false }
        guard AudioRecorder.shared.isRecording else {
            statusBar.updateProcessingStatus(.idle)
            return false
        }

        AudioRecorder.shared.onAudioLevel = nil
        AudioRecorder.shared.stopRecording()
        statusBar.updateProcessingStatus(.asr)

        let audioData = AudioRecorder.shared.getCurrentAudioData()
        let duration = AudioRecorder.shared.getCurrentDuration()
        let sampleRate = AudioRecorder.shared.getCurrentSampleRate()

        guard !audioData.isEmpty else {
            statusBar.updateProcessingStatus(.idle)
            statusBar.showNotification(title: "录音为空", message: "没有采集到有效音频，请重试")
            return false
        }

        await processAudio(audio: audioData, duration: duration, sampleRate: sampleRate)
        return true
    }

    // MARK: - 音频处理

    @MainActor
    private func processAudio(audio: [Float], duration: TimeInterval, sampleRate: Int) {
        Task {
            guard let statusBar = statusBar else { return }
            let settings = AppSettings.load()
            let bundled = resolveBundledModelSources()
            let llmModelId = bundled.llmModelPath ?? settings.llmModelId

            do {
                if !ASRService.shared.isModelLoaded || !LLMService.shared.isModelLoaded {
                    statusBar.updateProcessingStatus(.loadingModel)
                }
                if !ASRService.shared.isModelLoaded {
                    try await ASRService.shared.loadModel(
                        modelId: settings.asrModelId,
                        bundleResourcesURL: bundled.asrBundleResourcesURL
                    )
                }
                if !LLMService.shared.isModelLoaded {
                    try await LLMService.shared.loadModel(modelId: llmModelId)
                }

                statusBar.updateProcessingStatus(.asr)
                let rawText = try await ASRService.shared.transcribe(audio: audio, sampleRate: sampleRate)
                AppLogger.info("ASR 识别完成: \(rawText)", category: .general)

                statusBar.updateProcessingStatus(.polishing)
                // Per-app prompt takes priority over global custom prompt
                let effectivePrompt: String?
                if let targetBundleId = self.targetApp?.bundleIdentifier,
                   let appPrompt = settings.appPrompts[targetBundleId],
                   !appPrompt.isEmpty {
                    effectivePrompt = appPrompt
                } else {
                    effectivePrompt = settings.customSystemPrompt.isEmpty ? nil : settings.customSystemPrompt
                }
                let polishedText = try await LLMService.shared.polish(
                    text: rawText,
                    intensity: settings.polishIntensity,
                    customPrompt: effectivePrompt,
                    selectedText: self.selectedTextBeforeRecording
                )
                AppLogger.info("LLM 润色完成: \(polishedText)", category: .general)

                statusBar.updateProcessingStatus(.outputting)
                if let target = self.targetApp {
                    target.activate(options: .activateIgnoringOtherApps)
                    try await Task.sleep(for: .milliseconds(400))
                }

                try await TextInjector.shared.inject(polishedText)

                let historyItem = HistoryItem(
                    duration: duration, rawText: rawText, polishedText: polishedText,
                    asrModel: settings.asrModelId, llmModel: llmModelId
                )
                HistoryManager.shared.add(historyItem)

                statusBar.showDoneAndDismiss()
                statusBar.showNotification(title: "完成", message: "文本已输出")
                self.resetIdleTimer()
            } catch {
                AppLogger.error("音频处理失败: \(error.localizedDescription)", category: .general)
                statusBar.updateProcessingStatus(.idle)
                statusBar.showNotification(title: "处理失败", message: error.localizedDescription)
            }
        }
    }

    // MARK: - 捕获选中文本

    private func captureSelectedText() -> String? {
        let settings = AppSettings.load()
        switch settings.selectionCaptureMethod {
        case .accessibility:
            // 先尝试 Accessibility API，失败则 fallback 到 Cmd+C
            if let text = captureSelectedTextViaAccessibility() {
                return text
            }
            AppLogger.debug("Accessibility API 未获取到选中文本，尝试 Cmd+C fallback", category: .ui)
            return captureSelectedTextViaClipboard()
        case .clipboard:
            return captureSelectedTextViaClipboard()
        }
    }

    /// Accessibility API 方式：通过 AXUIElement 读取选中文本，不影响剪贴板
    private func captureSelectedTextViaAccessibility() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        let element = focusedElement as! AXUIElement  // AnyObject from AXUIElementCopyAttributeValue is always AXUIElement

        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success else {
            return nil
        }

        guard let text = selectedText as? String, !text.isEmpty else {
            return nil
        }

        AppLogger.debug("通过 Accessibility API 捕获选中文本: \(text.prefix(50))...", category: .ui)
        return text
    }

    /// Cmd+C 方式：模拟复制，兼容性更好但会短暂占用剪贴板
    private func captureSelectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        cmdDown?.flags = CGEventFlags.maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cmdUp?.flags = CGEventFlags.maskCommand
        cmdDown?.post(tap: CGEventTapLocation.cghidEventTap)
        cmdUp?.post(tap: CGEventTapLocation.cghidEventTap)

        Thread.sleep(forTimeInterval: 0.1)

        guard pasteboard.changeCount != changeCount else {
            return nil
        }

        let selectedText = pasteboard.string(forType: .string)
        AppLogger.debug("通过 Cmd+C 捕获选中文本: \(selectedText?.prefix(50) ?? "nil")...", category: .ui)
        return selectedText?.isEmpty == true ? nil : selectedText
    }

    private func setupMicrophonePermission() {
        AppLogger.info("麦克风权限由 macOS 系统自动管理", category: .general)
    }

    private func showMicrophonePermissionAlert() {
        AppLogger.warning("麦克风权限未授予", category: .ui)
        let alert = NSAlert()
        alert.messageText = "需要麦克风权限"
        alert.informativeText = "Talk 需要麦克风权限才能录音。\n\n请前往：系统设置 → 隐私与安全性 → 麦克风，为 Talk 开启权限。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func resolveBundledModelSources() -> (asrBundleResourcesURL: URL?, llmModelPath: String?) {
        guard let resourcesURL = Bundle.main.resourceURL else {
            return (nil, nil)
        }

        let asrConfigPath = resourcesURL
            .appendingPathComponent("mlx-audio/mlx-community_Qwen3-ASR-0.6B-4bit/config.json")
            .path
        let hasBundledASR = FileManager.default.fileExists(atPath: asrConfigPath)

        let llmDirURL = resourcesURL.appendingPathComponent("Models/llm", isDirectory: true)
        let llmConfigPath = llmDirURL.appendingPathComponent("config.json").path
        let hasBundledLLM = FileManager.default.fileExists(atPath: llmConfigPath)

        if hasBundledASR {
            AppLogger.info("检测到 bundle 内 ASR 模型", category: .general)
        }

        if hasBundledLLM {
            AppLogger.info("检测到 bundle 内 LLM 模型: \(llmDirURL.path)", category: .general)
        }

        return (
            hasBundledASR ? resourcesURL : nil,
            hasBundledLLM ? llmDirURL.path : nil
        )
    }
}

// MARK: - ProcessInfo 扩展

extension ProcessInfo {
    var operatingSystemVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
