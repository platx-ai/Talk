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
import MLXAudioSTT

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
    private var streamingFullText: String? = nil  // 流式识别的完整结果
    private var cumulativeConfirmedText: String = ""  // 累积的确认文本
    private var recordingStartTime: Date? = nil  // 录音开始时间

    // MARK: - 引擎状态追踪（用于热切换 diff）
    var loadedASREngine: AppSettings.ASREngine?
    var loadedLLMEngine: AppSettings.LLMEngine?
    var loadedLLMModelId: String?
    var loadedGemma4ModelSize: AppSettings.Gemma4ModelSize?
    var pendingEngineReload: Bool = false

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
        EditObserver.shared.startProcessingLoop()

        AppLogger.info("应用初始化完成", category: .general)
        AppLogger.info("========================================", category: .general)

        UpdateChecker.shared.checkForUpdates()
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
        let hasAnyModel = ASRService.shared.isModelLoaded
            || LLMService.shared.isModelLoaded
            || Gemma4ASREngine.shared.isModelLoaded
        guard hasAnyModel else { return }

        AppLogger.info("空闲超时，卸载模型以释放内存", category: .general)
        ASRService.shared.unloadModel()
        LLMService.shared.unloadModel()
        Gemma4ASREngine.shared.unloadModel()
        isModelsReady = false
    }

    /// 引擎热切换：比较当前加载状态 vs 期望设置，卸载变化的引擎，重新加载
    func reloadEngines() {
        // 录音中不切换，排队到录音结束
        if AudioRecorder.shared.isRecording {
            pendingEngineReload = true
            AppLogger.info("引擎切换已排队，等待录音结束", category: .general)
            return
        }

        let settings = AppSettings.load()
        let bundled = resolveBundledModelSources()
        let llmModelId = bundled.llmModelPath ?? settings.llmModelId

        let asrChanged = settings.asrEngine != loadedASREngine
        let llmEngineChanged = settings.llmEngine != loadedLLMEngine
        let llmModelChanged = llmModelId != loadedLLMModelId
        let gemma4SizeChanged = settings.gemma4ModelSize != loadedGemma4ModelSize

        guard asrChanged || llmEngineChanged || llmModelChanged || gemma4SizeChanged else {
            AppLogger.debug("引擎设置未变化，无需重载", category: .general)
            return
        }

        AppLogger.info("引擎设置变化，开始热切换", category: .general)

        // 卸载变化的引擎
        if asrChanged || gemma4SizeChanged {
            ASRService.shared.unloadModel()
            Gemma4ASREngine.shared.unloadModel()
            AppLogger.info("已卸载 ASR 引擎", category: .general)
        }
        if llmEngineChanged || llmModelChanged || gemma4SizeChanged {
            LLMService.shared.unloadModel()
            if llmEngineChanged || gemma4SizeChanged {
                Gemma4ASREngine.shared.unloadModel()
            }
            AppLogger.info("已卸载 LLM 引擎", category: .general)
        }

        isModelsReady = false
        initializeServices(settings: settings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("应用即将退出", category: .general)
        HotKeyManager.shared.unregisterHotKey()
        ASRService.shared.unloadModel()
        LLMService.shared.unloadModel()
        Gemma4ASREngine.shared.unloadModel()
        AudioRecorder.shared.cancelRecording()
    }

    // MARK: - 初始化服务

    private(set) var isModelsReady = false

    func initializeServices(settings: AppSettings) {
        if let reason = MLXRuntimeValidator.missingMetalLibraryReason() {
            AppLogger.error("启动预加载已跳过: \(reason)", category: .model)
            return
        }

        let bundled = resolveBundledModelSources()
        let llmModelId = bundled.llmModelPath ?? settings.llmModelId
        Task {
            statusBar?.updateProcessingStatus(.loadingModel)

            switch settings.asrEngine {
            case .mlxLocal:
                AppLogger.info("开始加载 ASR 模型...", category: .general)
                statusBar?.updateDownloadProgress(modelName: "ASR", progress: -1)
                do {
                    try await ASRService.shared.loadModel(modelId: settings.asrModelId, bundleResourcesURL: bundled.asrBundleResourcesURL)
                    AppLogger.info("ASR 模型加载完成", category: .general)
                } catch {
                    AppLogger.error("ASR 模型加载失败: \(error.localizedDescription)", category: .general)
                }
            case .gemma4:
                AppLogger.info("开始加载 Gemma4 模型...", category: .general)
                statusBar?.updateDownloadProgress(modelName: "Gemma4", progress: -1)
                do {
                    try await Gemma4ASREngine.shared.loadModel(modelId: settings.gemma4ModelId)
                    AppLogger.info("Gemma4 模型加载完成", category: .general)
                } catch {
                    AppLogger.error("Gemma4 模型加载失败: \(error.localizedDescription)", category: .general)
                }
            case .appleSpeech:
                AppLogger.info("ASR 引擎为 Apple Speech，跳过模型加载", category: .general)
            }

            // 一段式模式不需要单独的 LLM
            if settings.isOnePassMode {
                AppLogger.info("一段式模式：跳过 LLM 模型加载", category: .general)
            } else {
                AppLogger.info("开始加载 LLM 模型...", category: .general)
                statusBar?.updateDownloadProgress(modelName: "LLM", progress: -1)
                // 监控 LLM 下载进度并更新浮动指示器
                let progressTask = Task { @MainActor in
                    var lastProgress = -1.0
                    while LLMService.shared.isLoading {
                        let p = LLMService.shared.loadingProgress
                        if p != lastProgress {
                            lastProgress = p
                            statusBar?.updateDownloadProgress(modelName: "LLM", progress: p)
                        }
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                do {
                    try await LLMService.shared.loadModel(modelId: llmModelId)
                    AppLogger.info("LLM 模型加载完成", category: .general)
                } catch {
                    AppLogger.error("LLM 模型加载失败: \(error.localizedDescription)", category: .general)
                }
                progressTask.cancel()
            }

            let asrReady: Bool
            switch settings.asrEngine {
            case .mlxLocal: asrReady = ASRService.shared.isModelLoaded
            case .gemma4: asrReady = Gemma4ASREngine.shared.isModelLoaded
            case .appleSpeech: asrReady = true
            }
            isModelsReady = asrReady && (settings.isOnePassMode || LLMService.shared.isModelLoaded)
            statusBar?.updateProcessingStatus(.idle)

            // 记录已加载的引擎状态（用于热切换 diff）
            self.loadedASREngine = settings.asrEngine
            self.loadedLLMEngine = settings.llmEngine
            self.loadedLLMModelId = llmModelId
            self.loadedGemma4ModelSize = settings.gemma4ModelSize

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
                _ = await startRecording(trigger: String(localized: "热键"))
            } else {
                if AudioRecorder.shared.isRecording {
                    _ = await stopRecordingAndProcess(trigger: String(localized: "热键"))
                } else {
                    _ = await startRecording(trigger: String(localized: "热键"))
                }
            }
        }
    }

    @MainActor
    private func handleHotKeyReleased() {
        Task { _ = await stopRecordingAndProcess(trigger: String(localized: "热键")) }
    }

    func startRecordingFromMenuBar() async -> Bool { await startRecording(trigger: String(localized: "菜单栏")) }
    func stopRecordingFromMenuBar() async -> Bool { await stopRecordingAndProcess(trigger: String(localized: "菜单栏")) }

    // MARK: - 流式识别

    /// 处理音频数据块（直接喂入流式识别，内部由 MLX 管理缓冲）
    private func handleAudioChunk(_ chunk: [Float]) {
        let settings = AppSettings.load()

        guard settings.enableVADFilter else {
            ASRService.shared.feedAudio(samples: chunk, sampleRate: 16000)
            return
        }

        let threshold = Float(settings.vadThreshold)
        let paddingChunks = settings.vadPaddingChunks
        Task(priority: .userInitiated) {
            let streamResult = await VADService.shared.filterStreamingSpeechAsync(
                samples: chunk,
                sampleRate: 16000,
                threshold: threshold,
                paddingChunks: paddingChunks
            )

            await MainActor.run {
                if !streamResult.filteredSamples.isEmpty {
                    ASRService.shared.feedAudio(samples: streamResult.filteredSamples, sampleRate: 16000)
                }

                if streamResult.processedFrames > 0 {
                    AppLogger.debug(
                        "流式 VAD: in=\(chunk.count), out=\(streamResult.filteredSamples.count), frames=\(streamResult.processedFrames), speechFrames=\(streamResult.speechFrames), peakProb=\(String(format: "%.3f", streamResult.maxProbability))",
                        category: .audio
                    )
                }
            }
        }
    }

    private func startRecording(trigger: String) async -> Bool {
        guard let statusBar = statusBar else { return false }

        // 停止上一次编辑观察
        EditObserver.shared.stopObserving()

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

        // Apple Speech 权限检查
        let settings = AppSettings.load()
        if settings.asrEngine == .appleSpeech {
            let granted = await AppleSpeechService.ensurePermission()
            if !granted {
                AppLogger.warning("语音识别权限被拒绝，需要到系统设置中开启", category: .ui)
                return false
            }
        }

        // 模型未就绪时，边录音边加载（不拒绝录音）
        // Apple Speech 不需要加载 ASR 模型，但仍需 LLM 模型用于润色
        if !isModelsReady {
            let needASRModel = settings.asrEngine == .mlxLocal && !ASRService.shared.isModelLoaded
            let needLLMModel = !LLMService.shared.isModelLoaded
            if needASRModel || needLLMModel {
                AppLogger.info("\(trigger)触发：模型未加载，启动并行加载", category: .ui)
                let bundled = resolveBundledModelSources()
                let llmModelId = bundled.llmModelPath ?? settings.llmModelId
                Task {
                    do {
                        if needASRModel {
                            try await ASRService.shared.loadModel(modelId: settings.asrModelId, bundleResourcesURL: bundled.asrBundleResourcesURL)
                        }
                        if needLLMModel {
                            try await LLMService.shared.loadModel(modelId: llmModelId)
                        }
                        isModelsReady = true
                        AppLogger.info("并行模型加载完成", category: .general)
                    } catch {
                        AppLogger.error("并行模型加载失败: \(error.localizedDescription)", category: .general)
                    }
                }
            }
        }

        if AudioRecorder.shared.isRecording {
            statusBar.updateProcessingStatus(.recording)
            return false
        }
        do {
            targetApp = NSWorkspace.shared.frontmostApplication
            VADService.shared.reset()
            // 先用 Accessibility API（不阻塞），失败则用 Cmd+C fallback
            selectedTextBeforeRecording = captureSelectedText()
            if let sel = selectedTextBeforeRecording {
                AppLogger.info("捕获到选中文本: \(sel.prefix(50))...", category: .ui)
            }
            AudioRecorder.shared.selectedDeviceUID = settings.selectedAudioDeviceUID
            AudioRecorder.shared.onAudioLevel = { [weak statusBar] level in
                statusBar?.updateFloatingAudioLevel(level)
            }
            // 启动流式识别（如果启用）
            streamingFullText = nil
            cumulativeConfirmedText = ""  // 重置累积文本
            recordingStartTime = Date()  // 记录录音开始时间

            if settings.asrEngine == .appleSpeech {
                // Apple Speech：天然流式，始终启用
                // 跳过 3 秒延迟（Apple Speech 自己处理填充词）
                AudioRecorder.shared.skipStreamingDelay = true
                do {
                    try AppleSpeechService.shared.startStreaming(
                        locale: settings.appleSpeechLocale.locale,
                        onDevice: settings.appleSpeechOnDevice
                    )
                    AppleSpeechService.shared.onTranscriptionUpdate = { [weak self, weak statusBar] (confirmed, provisional) in
                        Task { @MainActor in
                            guard let self, settings.appleSpeechShowRealtime else { return }
                            let displayText = confirmed + provisional
                            statusBar?.updateFloatingRealtimeText(displayText)
                        }
                    }
                    AppleSpeechService.shared.onTranscriptionComplete = { [weak self] fullText in
                        Task { @MainActor in
                            self?.streamingFullText = fullText
                        }
                    }
                    AudioRecorder.shared.onAudioData = { chunk in
                        AppleSpeechService.shared.feedAudioSamples(chunk, sampleRate: 16000)
                    }
                    AppLogger.info("Apple Speech 流式识别已启动", category: .ui)
                } catch {
                    AppLogger.warning("Apple Speech 启动失败: \(error.localizedDescription)，降级为 MLX 批量识别", category: .ui)
                    AppleSpeechService.shared.cancelStreaming()
                    AudioRecorder.shared.onAudioData = nil
                }
            } else if settings.asrEngine == .gemma4 {
                // Gemma4: 不支持流式，batch only
                AudioRecorder.shared.skipStreamingDelay = false
                AppLogger.info("Gemma4 引擎不支持流式识别，将在录音结束后批量处理", category: .ui)
            } else if settings.enableStreamingInference {
                AudioRecorder.shared.skipStreamingDelay = false
                do {
                    if !ASRService.shared.isModelLoaded {
                        let bundled = resolveBundledModelSources()
                        try await ASRService.shared.loadModel(
                            modelId: settings.asrModelId,
                            bundleResourcesURL: bundled.asrBundleResourcesURL
                        )
                    }
                    try await ASRService.shared.startStreaming(delayPreset: .realtime)
                    ASRService.shared.onTranscriptionUpdate = { [weak self, weak statusBar] (confirmed, provisional) in
                        guard let self = self else { return }
                        Task { @MainActor in
                            guard settings.showRealtimeRecognition else { return }
                            // 维护累积的确认文本
                            if confirmed.hasPrefix(self.cumulativeConfirmedText) {
                                // 新的 confirmed 是旧的扩展，追加增量部分
                                let newText = String(confirmed.dropFirst(self.cumulativeConfirmedText.count))
                                self.cumulativeConfirmedText += newText
                            } else {
                                // 新的 confirmed 不是扩展，可能是重新识别，直接替换
                                self.cumulativeConfirmedText = confirmed
                            }

                            // 显示累积文本 + 临时文本
                            let displayText = self.cumulativeConfirmedText + provisional
                            statusBar?.updateFloatingRealtimeText(displayText)
                        }
                    }
                    ASRService.shared.onTranscriptionComplete = { [weak self] fullText in
                        Task { @MainActor in
                            self?.streamingFullText = fullText
                        }
                    }
                    // 连接 onAudioData 回调以喂入音频
                    AudioRecorder.shared.onAudioData = { [weak self] chunk in
                        self?.handleAudioChunk(chunk)
                    }
                    AppLogger.info("MLX 流式识别已启动", category: .ui)
                } catch {
                    AppLogger.warning("流式识别启动失败: \(error.localizedDescription)，降级为批量识别", category: .ui)
                    ASRService.shared.stopStreaming()
                    AudioRecorder.shared.onAudioData = nil
                }
            } else {
                AudioRecorder.shared.skipStreamingDelay = false
                ASRService.shared.stopStreaming()
                AudioRecorder.shared.onAudioData = nil
            }
            try AudioRecorder.shared.startRecording(sampleRate: 16000)
            statusBar.updateProcessingStatus(.recording, isEditMode: selectedTextBeforeRecording != nil)
            statusBar.updateFloatingRealtimeText("")  // 清空之前的实时文本
            AppLogger.info("\(trigger)触发：开始录音，目标应用: \(targetApp?.localizedName ?? "unknown")", category: .ui)
            return true
        } catch {
            AppLogger.error("\(trigger)开始录音失败: \(error.localizedDescription)", category: .ui)
            statusBar.showNotification(title: String(localized: "录音失败"), message: error.localizedDescription)
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
        AudioRecorder.shared.onAudioData = nil
        AudioRecorder.shared.stopRecording()
        statusBar.updateProcessingStatus(.asr)

        // 清理流式识别相关状态
        recordingStartTime = nil

        let audioData = AudioRecorder.shared.getCurrentAudioData()
        let duration = AudioRecorder.shared.getCurrentDuration()
        let sampleRate = AudioRecorder.shared.getCurrentSampleRate()

        guard !audioData.isEmpty else {
            statusBar.updateProcessingStatus(.idle)
            AppLogger.warning("录音为空，没有采集到有效音频", category: .audio)
            ASRService.shared.stopStreaming()
            AppleSpeechService.shared.cancelStreaming()
            return false
        }

        let settings = AppSettings.load()

        // Apple Speech：停止输入并等待最终结果
        if settings.asrEngine == .appleSpeech && AppleSpeechService.shared.isRecognizing {
            AppleSpeechService.shared.stopStreaming()
            // 等待最终结果到达（最多 3 秒）
            for _ in 0..<30 {
                if streamingFullText != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // 音频保存推迟到各路径中（streaming 保存原始音频，batch 保存 VAD 过滤后的音频）
        let audioItemId = UUID()

        // 构建 ASR 上下文快照
        let hotwords = VocabularyManager.shared.getHighFrequencyItems(limit: 10)
        let hotwordList = Array(Set(hotwords.compactMap { $0.correctedForm })).joined(separator: ", ")
        let asrCtx = ASRContext(
            language: settings.asrLanguage.rawValue,
            hotwordPrompt: hotwordList.isEmpty ? nil : hotwordList,
            systemPrompt: settings.customSystemPrompt.isEmpty ? nil : settings.customSystemPrompt,
            polishIntensity: settings.polishIntensity.rawValue,
            targetApp: self.targetApp?.bundleIdentifier
        )

        // Gemma4 不支持流式 — 忽略流式结果，直接走 batch
        // 其他引擎：如果流式识别已完成，使用流式结果；否则降级为批量识别
        if settings.asrEngine == .gemma4 {
            // Gemma4: 停止任何正在运行的流式识别，直接走 batch
            ASRService.shared.stopStreaming()
            let vadResult: VADFilterResult
            if settings.enableVADFilter {
                vadResult = VADService.shared.filterSpeech(
                    audio: audioData, sampleRate: sampleRate,
                    threshold: Float(settings.vadThreshold),
                    paddingChunks: settings.vadPaddingChunks,
                    minSpeechChunks: settings.vadMinSpeechChunks
                )
            } else {
                vadResult = VADFilterResult(speechAudio: audioData, speechDetected: true, maxProbability: 1)
            }
            guard vadResult.speechDetected else {
                statusBar.updateProcessingStatus(.idle)
                statusBar.showNotification(title: String(localized: "未检测到语音"), message: String(localized: "请重试并靠近麦克风"))
                return false
            }

            var savedAudioFilename: String?
            if settings.enableAudioHistory {
                savedAudioFilename = HistoryManager.shared.saveAudio(
                    vadResult.speechAudio, sampleRate: sampleRate, itemId: audioItemId
                )
            }

            await processAudio(
                audio: vadResult.speechAudio, duration: duration, sampleRate: sampleRate,
                audioFilePath: savedAudioFilename, asrContext: asrCtx, itemId: audioItemId
            )
        } else if let fullText = streamingFullText {
            let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                // 流式识别返回空结果（未检测到语音）
                statusBar.updateProcessingStatus(.idle)
                statusBar.showNotification(title: String(localized: "未检测到语音"), message: String(localized: "请重试并靠近麦克风"))
                AppLogger.info("流式识别结果为空，跳过润色", category: .ui)
                return false
            }
            let engineName = settings.asrEngine == .appleSpeech ? "Apple Speech" : "MLX"
            AppLogger.info("使用\(engineName)流式识别结果: \(trimmed)", category: .ui)
            // 等待一小段时间确保流式识别完全结束
            try? await Task.sleep(for: .milliseconds(100))
            if settings.asrEngine != .appleSpeech {
                ASRService.shared.stopStreaming()
            }
            // 流式路径：保存原始音频
            var savedAudioFilename: String?
            if settings.enableAudioHistory {
                savedAudioFilename = HistoryManager.shared.saveAudio(
                    audioData, sampleRate: sampleRate, itemId: audioItemId
                )
            }
            await processTranscription(
                text: trimmed, duration: duration,
                audioFilePath: savedAudioFilename, asrContext: asrCtx, itemId: audioItemId
            )
        } else if settings.asrEngine == .appleSpeech {
            // Apple Speech 没返回结果 — 不回退到 MLX，直接提示
            AppleSpeechService.shared.cancelStreaming()
            statusBar.updateProcessingStatus(.idle)
            statusBar.showNotification(title: String(localized: "未检测到语音"), message: String(localized: "请重试并靠近麦克风"))
            AppLogger.warning("Apple Speech 未返回识别结果", category: .asr)
            return false
        } else {
            // MLX ASR 回退路径：停止流式 → VAD 过滤 → 批量识别
            ASRService.shared.stopStreaming()
            let vadResult: VADFilterResult
            if settings.enableVADFilter {
                AppLogger.info(
                    "开始 VAD 过滤: samples=\(audioData.count), sampleRate=\(sampleRate), threshold=\(String(format: "%.2f", settings.vadThreshold)), padding=\(settings.vadPaddingChunks), minSpeech=\(settings.vadMinSpeechChunks)",
                    category: .audio
                )
                vadResult = VADService.shared.filterSpeech(
                    audio: audioData,
                    sampleRate: sampleRate,
                    threshold: Float(settings.vadThreshold),
                    paddingChunks: settings.vadPaddingChunks,
                    minSpeechChunks: settings.vadMinSpeechChunks
                )
                AppLogger.info(
                    "VAD 过滤完成: speechDetected=\(vadResult.speechDetected), outputSamples=\(vadResult.speechAudio.count), peakProb=\(String(format: "%.3f", vadResult.maxProbability))",
                    category: .audio
                )
            } else {
                AppLogger.info("VAD 已关闭，直接使用原始音频", category: .audio)
                vadResult = VADFilterResult(
                    speechAudio: audioData,
                    speechDetected: true,
                    maxProbability: 1
                )
            }
            guard vadResult.speechDetected else {
                statusBar.updateProcessingStatus(.idle)
                statusBar.showNotification(title: String(localized: "未检测到语音"), message: String(localized: "请重试并靠近麦克风"))
                AppLogger.info("VAD 判定为无语音，跳过 ASR", category: .audio)
                return false
            }

            if vadResult.speechAudio.count != audioData.count {
                AppLogger.info(
                    "VAD 过滤完成: \(audioData.count) -> \(vadResult.speechAudio.count) 样点, 峰值概率=\(String(format: "%.3f", vadResult.maxProbability))",
                    category: .audio
                )
            }

            // Batch 路径：保存 VAD 过滤后的音频（ASR 实际处理的）
            var savedAudioFilename: String?
            if settings.enableAudioHistory {
                savedAudioFilename = HistoryManager.shared.saveAudio(
                    vadResult.speechAudio, sampleRate: sampleRate, itemId: audioItemId
                )
            }

            // 使用 MLX 批量识别
            await processAudio(
                audio: vadResult.speechAudio, duration: duration, sampleRate: sampleRate,
                audioFilePath: savedAudioFilename, asrContext: asrCtx, itemId: audioItemId
            )
        }

        return true
    }

    // MARK: - 音频处理

    @MainActor
    private func processTranscription(text: String, duration: TimeInterval, audioFilePath: String? = nil, asrContext: ASRContext? = nil, itemId: UUID = UUID()) {
        Task {
            guard let statusBar = statusBar else { return }
            let settings = AppSettings.load()
            let bundled = resolveBundledModelSources()
            let llmModelId = bundled.llmModelPath ?? settings.llmModelId

            do {
                if !LLMService.shared.isModelLoaded {
                    statusBar.updateDownloadProgress(modelName: "LLM", progress: -1)
                    // 监控下载进度
                    let progressTask = Task { @MainActor in
                        while LLMService.shared.isLoading {
                            statusBar.updateDownloadProgress(modelName: "LLM", progress: LLMService.shared.loadingProgress)
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                    }
                    try await LLMService.shared.loadModel(modelId: llmModelId)
                    progressTask.cancel()
                }

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

                // Apple Speech 模式：每次清除会话历史，避免 LLM 把上一轮输出混入当前结果
                // （Apple Speech 每次给出完整独立的句子，不需要上下文关联）
                if settings.asrEngine == .appleSpeech, let bid = self.targetApp?.bundleIdentifier {
                    LLMService.shared.clearHistory(forApp: bid)
                }

                let polishedText = try await LLMService.shared.polish(
                    text: text,
                    intensity: settings.polishIntensity,
                    customPrompt: effectivePrompt,
                    selectedText: self.selectedTextBeforeRecording,
                    appBundleId: self.targetApp?.bundleIdentifier
                )
                AppLogger.info("LLM 润色完成: \(polishedText)", category: .general)

                statusBar.updateProcessingStatus(.outputting)

                if settings.outputMethod == .clipboardOnly {
                    // 仅复制到剪贴板
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(polishedText, forType: .string)
                    AppLogger.info("结果已复制到剪贴板", category: .ui)
                } else {
                    // 自动粘贴
                    if let target = self.targetApp {
                        target.activate(options: .activateIgnoringOtherApps)
                        try await Task.sleep(for: .milliseconds(400))
                    }
                    try await TextInjector.shared.inject(polishedText)

                    // 启动编辑观察（启发式热词学习）
                    if settings.enableAutoHotwordLearning, let target = self.targetApp {
                        EditObserver.shared.startObserving(
                            injectedText: polishedText,
                            targetApp: target,
                            prefixContext: nil
                        )
                    }
                }

                let asrLabel = settings.asrEngine == .appleSpeech ? "Apple Speech" : settings.asrModelId
                let historyItem = HistoryItem(
                    id: itemId, duration: duration, rawText: text, polishedText: polishedText,
                    asrModel: asrLabel, llmModel: llmModelId,
                    audioFilePath: audioFilePath, asrContext: asrContext
                )
                HistoryManager.shared.add(historyItem)

                statusBar.showDoneAndDismiss()
                self.resetIdleTimer()
                if self.pendingEngineReload {
                    self.pendingEngineReload = false
                    self.reloadEngines()
                }
            } catch {
                AppLogger.error("转录处理失败: \(error.localizedDescription)", category: .general)
                statusBar.updateProcessingStatus(.idle)
                statusBar.showNotification(title: String(localized: "处理失败"), message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func processAudio(audio: [Float], duration: TimeInterval, sampleRate: Int, audioFilePath: String? = nil, asrContext: ASRContext? = nil, itemId: UUID = UUID()) {
        Task {
            guard let statusBar = statusBar else { return }
            let settings = AppSettings.load()
            let bundled = resolveBundledModelSources()
            let llmModelId = bundled.llmModelPath ?? settings.llmModelId

            do {
                let rawText: String
                let polishedText: String

                if settings.isOnePassMode {
                    // 一段式：Gemma4 直接输出润色文本（ASR + LLM 合一）
                    if !Gemma4ASREngine.shared.isModelLoaded {
                        statusBar.updateProcessingStatus(.loadingModel)
                        try await Gemma4ASREngine.shared.loadModel(modelId: settings.gemma4ModelId)
                    }

                    // Build prompt with user settings (intensity, custom/per-app prompt)
                    let effectiveAppPrompt: String? = {
                        if let bid = self.targetApp?.bundleIdentifier,
                           let p = settings.appPrompts[bid], !p.isEmpty { return p }
                        return nil
                    }()
                    let prompt = Gemma4ASREngine.buildPrompt(
                        intensity: settings.polishIntensity,
                        customPrompt: settings.customSystemPrompt.isEmpty ? nil : settings.customSystemPrompt,
                        appPrompt: effectiveAppPrompt
                    )

                    statusBar.updateProcessingStatus(.asr)
                    let result = try await Gemma4ASREngine.shared.transcribe(
                        audio: audio, sampleRate: sampleRate, prompt: prompt)
                    rawText = result
                    polishedText = result  // 一段式：ASR 输出即最终结果
                    AppLogger.info("Gemma4 一段式完成: \(polishedText)", category: .general)
                } else {
                    // 两段式：ASR → LLM

                    // 1. Load models
                    statusBar.updateProcessingStatus(.loadingModel)
                    if settings.asrEngine == .gemma4 {
                        if !Gemma4ASREngine.shared.isModelLoaded {
                            try await Gemma4ASREngine.shared.loadModel(modelId: settings.gemma4ModelId)
                        }
                    } else if !ASRService.shared.isModelLoaded {
                        try await ASRService.shared.loadModel(
                            modelId: settings.asrModelId,
                            bundleResourcesURL: bundled.asrBundleResourcesURL
                        )
                    }
                    if settings.llmEngine == .gemma4 {
                        if !Gemma4ASREngine.shared.isModelLoaded {
                            try await Gemma4ASREngine.shared.loadModel(modelId: settings.gemma4ModelId)
                        }
                    } else if !LLMService.shared.isModelLoaded {
                        try await LLMService.shared.loadModel(modelId: llmModelId)
                    }

                    // 2. ASR
                    statusBar.updateProcessingStatus(.asr)
                    if settings.asrEngine == .gemma4 {
                        rawText = try await Gemma4ASREngine.shared.transcribe(
                            audio: audio, sampleRate: sampleRate)
                    } else {
                        rawText = try await ASRService.shared.transcribe(
                            audio: audio, sampleRate: sampleRate)
                    }
                    AppLogger.info("ASR 识别完成: \(rawText)", category: .general)

                    // 3. LLM Polish
                    statusBar.updateProcessingStatus(.polishing)
                    if settings.llmEngine == .gemma4 {
                        // Gemma4 音频感知润色：能听原始音频修正 ASR 错误
                        polishedText = try await Gemma4ASREngine.shared.polish(
                            audio: audio, sampleRate: sampleRate, asrText: rawText)
                        AppLogger.info("Gemma4 润色完成: \(polishedText)", category: .general)
                    } else {
                        // Qwen3 LLM 纯文本润色
                        let effectivePrompt: String?
                        if let targetBundleId = self.targetApp?.bundleIdentifier,
                           let appPrompt = settings.appPrompts[targetBundleId],
                           !appPrompt.isEmpty {
                            effectivePrompt = appPrompt
                        } else {
                            effectivePrompt = settings.customSystemPrompt.isEmpty ? nil : settings.customSystemPrompt
                        }
                        let editPrompt = settings.customEditPrompt.isEmpty ? nil : settings.customEditPrompt
                        polishedText = try await LLMService.shared.polish(
                            text: rawText,
                            intensity: settings.polishIntensity,
                            customPrompt: effectivePrompt,
                            customEditPrompt: editPrompt,
                            selectedText: self.selectedTextBeforeRecording,
                            appBundleId: self.targetApp?.bundleIdentifier
                        )
                        AppLogger.info("LLM 润色完成: \(polishedText)", category: .general)
                    }
                }

                statusBar.updateProcessingStatus(.outputting)

                if settings.outputMethod == .clipboardOnly {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(polishedText, forType: .string)
                    AppLogger.info("结果已复制到剪贴板（流式模式）", category: .ui)
                } else {
                    if let target = self.targetApp {
                        target.activate(options: .activateIgnoringOtherApps)
                        try await Task.sleep(for: .milliseconds(400))
                    }
                    try await TextInjector.shared.inject(polishedText)

                    // 启动编辑观察（启发式热词学习）
                    if settings.enableAutoHotwordLearning, let target = self.targetApp {
                        EditObserver.shared.startObserving(
                            injectedText: polishedText,
                            targetApp: target,
                            prefixContext: nil
                        )
                    }
                }

                let asrLabel: String
                let llmLabel: String
                if settings.isOnePassMode {
                    asrLabel = "Gemma4 (one-pass)"
                    llmLabel = settings.gemma4ModelId
                } else if settings.asrEngine == .gemma4 {
                    asrLabel = settings.gemma4ModelId
                    llmLabel = llmModelId
                } else {
                    asrLabel = settings.asrEngine == .appleSpeech ? "Apple Speech" : settings.asrModelId
                    llmLabel = llmModelId
                }
                let historyItem = HistoryItem(
                    id: itemId, duration: duration, rawText: rawText, polishedText: polishedText,
                    asrModel: asrLabel, llmModel: llmLabel,
                    audioFilePath: audioFilePath, asrContext: asrContext
                )
                HistoryManager.shared.add(historyItem)

                statusBar.showDoneAndDismiss()
                self.resetIdleTimer()
                if self.pendingEngineReload {
                    self.pendingEngineReload = false
                    self.reloadEngines()
                }
            } catch {
                AppLogger.error("音频处理失败: \(error.localizedDescription)", category: .general)
                statusBar.updateProcessingStatus(.idle)
                statusBar.showNotification(title: String(localized: "处理失败"), message: error.localizedDescription)
            }
        }
    }

    // MARK: - 捕获选中文本

    /// 已知不支持 Accessibility 选中文本的 app（运行时学习，持久化到 UserDefaults）
    private static let axUnsupportedAppsKey = "axUnsupportedApps"
    private var axUnsupportedApps: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: AppDelegate.axUnsupportedAppsKey) ?? []
    ) {
        didSet {
            UserDefaults.standard.set(Array(axUnsupportedApps), forKey: Self.axUnsupportedAppsKey)
        }
    }

    /// 终端类 app — Cmd+C 发 SIGINT，绝不能用
    static func isTerminalApp(_ bundleId: String) -> Bool {
        let keywords = ["terminal", "iterm", "kitty", "wezterm", "hyper", "warp", "alacritty"]
        let lower = bundleId.lowercased()
        return keywords.contains { lower.contains($0) }
    }

    /// 检测 Cmd+C 结果是否为无选区的整行复制（VSCode/Cursor 等编辑器行为）
    /// 单行 + 以换行结尾 = 疑似无选区复制；多行选中不过滤
    static func shouldTreatAsNoSelection(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .newlines)
        return normalized.hasSuffix("\n") && !trimmed.contains("\n")
    }

    private func captureSelectedText() -> String? {
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }

        // 已知不支持 AX 的应用，直接走 Cmd+C（除非是终端）
        if axUnsupportedApps.contains(bundleId) {
            if Self.isTerminalApp(bundleId) { return nil }
            AppLogger.debug("选中捕获：\(bundleId) 已知不支持 AX，使用 Cmd+C", category: .ui)
            return captureSelectedTextViaClipboard()
        }

        // 尝试 Accessibility API
        if let text = captureSelectedTextViaAccessibility() {
            return text
        }

        // AX 失败 — 记住这个 app，下次直接用 Cmd+C
        axUnsupportedApps.insert(bundleId)
        AppLogger.debug("选中捕获：\(bundleId) 不支持 AX，已记录。尝试 Cmd+C fallback", category: .ui)

        // 终端不用 Cmd+C
        if Self.isTerminalApp(bundleId) { return nil }
        return captureSelectedTextViaClipboard()
    }

    /// Accessibility API 方式：通过 AXUIElement 读取选中文本，不影响剪贴板
    private func captureSelectedTextViaAccessibility() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            AppLogger.debug("选中捕获：无前台应用", category: .ui)
            return nil
        }
        AppLogger.debug("选中捕获：前台应用 = \(app.localizedName ?? "unknown") (\(app.bundleIdentifier ?? "?"))", category: .ui)

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusResult == .success else {
            AppLogger.debug("选中捕获：无法获取焦点元素 (error: \(focusResult.rawValue))", category: .ui)
            return nil
        }

        let element = focusedElement as! AXUIElement

        var selectedText: AnyObject?
        let selectResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        guard selectResult == .success else {
            AppLogger.debug("选中捕获：无法读取选中文本 (error: \(selectResult.rawValue))", category: .ui)
            return nil
        }

        guard let text = selectedText as? String, !text.isEmpty else {
            AppLogger.debug("选中捕获：选中文本为空", category: .ui)
            return nil
        }

        AppLogger.debug("选中捕获成功: \(text.prefix(50))...", category: .ui)
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

        guard let text = selectedText, !text.isEmpty else { return nil }

        if Self.shouldTreatAsNoSelection(text) {
            AppLogger.debug("Cmd+C 结果为单行+换行，疑似无选区整行复制，忽略", category: .ui)
            return nil
        }

        return text
    }

    private func setupMicrophonePermission() {
        // 主动请求麦克风权限，确保 Talk 出现在系统设置的麦克风列表中
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    AppLogger.info("麦克风权限已授予", category: .general)
                } else {
                    AppLogger.warning("麦克风权限被拒绝", category: .general)
                }
            }
        } else if status == .authorized {
            AppLogger.info("麦克风权限已授予", category: .general)
        } else {
            AppLogger.warning("麦克风权限未授予 (status: \(status.rawValue))", category: .general)
        }
    }

    private func showMicrophonePermissionAlert() {
        AppLogger.warning("麦克风权限未授予", category: .ui)

        // 先触发一次系统权限请求，确保 Talk 出现在系统设置的麦克风列表中
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        let alert = NSAlert()
        alert.messageText = String(localized: "需要麦克风权限")
        alert.informativeText = String(localized: "Talk 需要麦克风权限才能录音。\n\n如果没有弹出系统授权窗口，请手动前往：\n系统设置 → 隐私与安全性 → 麦克风，为 Talk 开启权限。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "打开系统设置"))
        alert.addButton(withTitle: String(localized: "稍后"))
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
