//
//  SettingsView.swift
//  Talk
//
//  设置视图
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        TabView {
            RecordingSettingsTab(settings: settings)
                .tabItem { Label("录音", systemImage: "mic.circle") }

            ASRSettingsTab(settings: settings)
                .tabItem { Label("语音识别", systemImage: "waveform") }

            LLMSettingsTab(settings: settings)
                .tabItem { Label("文本润色", systemImage: "sparkles") }

            OutputSettingsTab(settings: settings)
                .tabItem { Label("输出", systemImage: "text.bubble") }

            AdvancedSettingsTab(settings: settings)
                .tabItem { Label("高级", systemImage: "gearshape.2") }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - 录音设置标签页

private struct RecordingSettingsTab: View {
    @Bindable var settings: AppSettings
    @State private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        Form {
            Section {
                Picker("输入设备", selection: $settings.selectedAudioDeviceUID) {
                    Text("内置麦克风（默认）").tag(nil as String?)
                    ForEach(deviceManager.inputDevices.filter { !$0.isBuiltIn }) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
            } header: {
                Text("音频输入")
            }

            Section {
                Picker("触发方式", selection: $settings.recordingTriggerMode) {
                    ForEach(AppSettings.RecordingTriggerMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                KeyRecorderView(hotkey: $settings.recordingHotkey) { newCombo in
                    settings.recordingHotkey = newCombo
                    settings.save()
                    AppDelegate.shared?.applyHotKey(newCombo, triggerMode: settings.recordingTriggerMode)
                }

                Text("全局快捷键依赖输入监控权限。若快捷键无反应，请在系统设置 → 隐私与安全性 → 输入监控中开启 Talk，并重启应用。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("录音时长限制")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.recordingMaxDuration > 0 },
                        set: { settings.recordingMaxDuration = $0 ? 0 : 60 }
                    ))
                    if settings.recordingMaxDuration > 0 {
                        Stepper("\(settings.recordingMaxDuration)秒",
                                value: $settings.recordingMaxDuration,
                                in: 1...300)
                    }
                }
            } header: {
                Text("录音设置")
            }

            Section {
                HStack {
                    Text("音频采样率")
                    Spacer()
                    Picker("", selection: $settings.sampleRate) {
                        Text("16 kHz").tag(16000)
                        Text("44.1 kHz").tag(44100)
                        Text("48 kHz").tag(48000)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            } header: {
                Text("音频参数")
            }

            Section {
                Toggle("录音时菜单栏图标变化", isOn: .constant(true))
                Toggle("播放提示音", isOn: .constant(false))
            } header: {
                Text("录音提示")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - ASR 设置标签页

private struct ASRSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("下载源", selection: $settings.modelSource) {
                    Text("HuggingFace（国际）").tag(AppSettings.ModelSource.huggingface)
                    Text("ModelScope（中国大陆）").tag(AppSettings.ModelSource.modelscope)
                }
                Text("中国大陆用户建议选择 ModelScope，可避免网络问题。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("模型下载源")
            }

            Section {
                Picker("模型选择", selection: $settings.asrModelId) {
                    Text("Qwen3-ASR-0.6B-4bit").tag("mlx-community/Qwen3-ASR-0.6B-4bit")
                }

                Picker("识别语言", selection: $settings.asrLanguage) {
                    ForEach(AppSettings.ASRLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }

                Toggle("实时显示识别结果", isOn: $settings.showRealtimeRecognition)
            } header: {
                Text("语音识别设置")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - LLM 设置标签页

private struct LLMSettingsTab: View {
    @Bindable var settings: AppSettings
    @State private var newAppBundleId = ""
    @State private var promptTab = 0

    var body: some View {
        Form {
            Section {
                Picker("模型选择", selection: $settings.llmModelId) {
                    Text("Qwen3-4B-Instruct (4-bit)").tag("mlx-community/Qwen3-4B-Instruct-2507-4bit")
                }

                Picker("润色强度", selection: $settings.polishIntensity) {
                    ForEach(AppSettings.PolishIntensity.allCases, id: \.self) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }

                HStack {
                    Text("对话历史轮数")
                    Spacer()
                    Stepper("\(settings.conversationHistoryRounds) 轮",
                            value: $settings.conversationHistoryRounds,
                            in: 0...10)
                }

                Toggle("启用对话历史", isOn: $settings.enableConversationHistory)
            } header: {
                Text("文本润色设置")
            }

            Section {
                // List existing app prompts
                ForEach(Array(settings.appPrompts.keys.sorted()), id: \.self) { bundleId in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(appDisplayName(for: bundleId))
                                .font(.headline)
                            Spacer()
                            Button(role: .destructive) {
                                settings.appPrompts.removeValue(forKey: bundleId)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        TextEditor(text: Binding(
                            get: { settings.appPrompts[bundleId] ?? "" },
                            set: { settings.appPrompts[bundleId] = $0 }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 60)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    }
                }

                // Add new app prompt — running apps + well-known presets, deduplicated
                HStack {
                    Picker("添加应用", selection: $newAppBundleId) {
                        Text("选择应用...").tag("")

                        let existingIds = Set(settings.appPrompts.keys)
                        let runningApps = NSWorkspace.shared.runningApplications
                            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                            .compactMap { app -> (String, String)? in
                                guard let bid = app.bundleIdentifier, !existingIds.contains(bid) else { return nil }
                                return (bid, app.localizedName ?? bid)
                            }
                            .sorted { $0.1 < $1.1 }

                        if !runningApps.isEmpty {
                            Section("正在运行") {
                                ForEach(runningApps, id: \.0) { bid, name in
                                    Text(name).tag(bid)
                                }
                            }
                        }

                        let wellKnownIds: [(String, String)] = [
                            ("com.apple.Terminal", "终端"),
                            ("com.googlecode.iterm2", "iTerm2"),
                            ("com.microsoft.VSCode", "VS Code"),
                            ("com.apple.dt.Xcode", "Xcode"),
                            ("com.tencent.xinWeChat", "微信"),
                            ("com.tinyspeck.slackmacgap", "Slack"),
                            ("com.apple.mail", "邮件"),
                            ("com.apple.Notes", "备忘录"),
                            ("com.bytedance.lark.mac", "飞书"),
                        ].filter { item in !existingIds.contains(item.0) && !runningApps.contains { r in r.0 == item.0 } }

                        if !wellKnownIds.isEmpty {
                            Section("常用应用") {
                                ForEach(wellKnownIds, id: \.0) { bid, name in
                                    Text(name).tag(bid)
                                }
                            }
                        }
                    }
                    Button("添加") {
                        guard !newAppBundleId.isEmpty else { return }
                        if settings.appPrompts[newAppBundleId] == nil {
                            settings.appPrompts[newAppBundleId] = defaultPromptForApp(newAppBundleId)
                        }
                        newAppBundleId = ""
                    }
                    .disabled(newAppBundleId.isEmpty)
                }

                Text("为不同应用设置专属提示词。录音时自动检测前台应用并使用对应提示词。未配置的应用使用全局提示词。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("应用专属提示词")
            }

            Section {
                Picker("提示词类型", selection: $promptTab) {
                    Text("听写润色").tag(0)
                    Text("编辑指令").tag(1)
                }
                .pickerStyle(.segmented)

                if promptTab == 0 {
                    // 听写润色提示词
                    HStack {
                        if settings.customSystemPrompt.isEmpty {
                            Label("使用默认", systemImage: "checkmark.circle")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Label("自定义", systemImage: "pencil.circle.fill")
                                .font(.caption).foregroundColor(.orange)
                        }
                        Spacer()
                        Menu("预设模板") {
                            Button("严格纠错") {
                                settings.customSystemPrompt = "你是一个严格的文本纠错助手。只修正明显的语音识别错误和错别字，不改变原文的表达方式、语气和结构。直接输出修正后的文本，不要添加任何解释。"
                            }
                            Button("轻度润色") {
                                settings.customSystemPrompt = "你是一个文本清理助手。去除口语填充词（嗯、啊、呃），添加标点符号，修正明显错误。保留原文的表达风格和语气，不做改写。直接输出清理后的文本，不要添加任何解释。"
                            }
                            Button("会议纪要") {
                                settings.customSystemPrompt = "你是一个会议纪要整理助手。将语音识别的会议内容整理为结构化的纪要格式：提取要点、决议和待办事项。直接输出纪要，不要添加任何解释。"
                            }
                            Button("技术文档") {
                                settings.customSystemPrompt = "你是一个技术文档整理助手。将语音输入整理为技术文档风格：保留代码标识符和技术术语的原文，使用 Markdown 格式。直接输出文档，不要添加任何解释。"
                            }
                        }
                        Button("填入默认") { settings.customSystemPrompt = LLMService.defaultSystemPrompt }
                    }

                    TextEditor(text: $settings.customSystemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                    Text("留空使用默认提示词。自定义后润色强度选项被忽略。")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    // 编辑指令提示词
                    HStack {
                        if settings.customEditPrompt.isEmpty {
                            Label("使用默认", systemImage: "checkmark.circle")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Label("自定义", systemImage: "pencil.circle.fill")
                                .font(.caption).foregroundColor(.orange)
                        }
                        Spacer()
                        Button("填入默认") { settings.customEditPrompt = LLMService.defaultEditPrompt }
                    }

                    TextEditor(text: $settings.customEditPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                    Text("选中文字后录音进入编辑模式。语音作为指令，可用于替换词语、风格改写、纠错、格式转换等。")
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Text("提示词")
            }
        }
        .formStyle(.grouped)
    }

    private func appDisplayName(for bundleId: String) -> String {
        let wellKnown: [String: String] = [
            "com.apple.Terminal": "终端",
            "com.googlecode.iterm2": "iTerm2",
            "com.microsoft.VSCode": "VS Code",
            "com.apple.dt.Xcode": "Xcode",
            "com.tencent.xinWeChat": "微信",
            "com.tinyspeck.slackmacgap": "Slack",
            "com.apple.mail": "邮件",
            "com.apple.Notes": "备忘录",
            "com.bytedance.lark.mac": "飞书",
        ]
        if let name = wellKnown[bundleId] { return name }
        // Try to get name from running apps or installed apps
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return app.localizedName ?? bundleId
        }
        // Try to get from bundle URL
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleId
    }

    private func defaultPromptForApp(_ bundleId: String) -> String {
        switch bundleId {
        case "com.apple.Terminal", "com.googlecode.iterm2":
            return "保留命令行语法和技术术语。代码标识符、文件路径、命令名不要修改。直接输出清理后的文本。"
        case "com.microsoft.VSCode", "com.apple.dt.Xcode":
            return "保留代码变量名、函数名和技术术语。使用技术文档风格，Markdown 格式。直接输出清理后的文本。"
        case "com.tencent.xinWeChat", "com.tinyspeck.slackmacgap", "com.bytedance.lark.mac":
            return "口语化，简洁，适合即时通讯。不要过度正式化。直接输出清理后的文本。"
        case "com.apple.mail":
            return "正式语气，添加适当的问候和结尾。直接输出清理后的文本。"
        case "com.apple.Notes":
            return "结构化笔记格式，使用标题和项目符号列表。直接输出清理后的文本。"
        default:
            return "直接输出清理后的文本，不要添加任何解释。"
        }
    }
}

// MARK: - 输出设置标签页

private struct OutputSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("输出方式", selection: $settings.outputMethod) {
                    ForEach(AppSettings.OutputMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }

                Picker("输出时机", selection: $settings.outputDelay) {
                    ForEach(AppSettings.OutputDelay.allCases, id: \.self) { delay in
                        Text(delay.displayName).tag(delay)
                    }
                }

                if settings.outputDelay == .custom {
                    HStack {
                        Text("延迟")
                        Stepper("\(settings.customOutputDelay)秒",
                                value: $settings.customOutputDelay,
                                in: 1...10)
                    }
                }

                Toggle("输出前预览", isOn: $settings.showPreviewBeforeOutput)
            } header: {
                Text("输出设置")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 高级设置标签页

private struct AdvancedSettingsTab: View {
    @Bindable var settings: AppSettings
    @State private var showVocabularyView = false
    @State private var permissions = PermissionsSnapshot.empty
    @State private var pollTimer: Timer?

    var body: some View {
        Form {
            Section {
                ForEach(AppPermission.allCases) { permission in
                    PermissionRowView(
                        permission: permission,
                        isGranted: permissions.isGranted(permission),
                        actionTitle: actionTitle(for: permission),
                        action: { handlePermissionAction(permission) }
                    )
                }
            } header: {
                Text("权限")
            }

            Section {
                Picker("选中文本捕获方式", selection: $settings.selectionCaptureMethod) {
                    Text("Accessibility API（低侵入）").tag(AppSettings.SelectionCaptureMethod.accessibility)
                    Text("Cmd+C 复制（兼容性好）").tag(AppSettings.SelectionCaptureMethod.clipboard)
                }
                Text("选中文字后录音可替换选中内容。Accessibility API 不影响剪贴板但部分应用不支持。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("选中修正")
            }

            Section {
                Toggle("启用命令词识别", isOn: $settings.enableVoiceCommands)
            } header: {
                Text("高级功能")
            }

            Section {
                Toggle("启用个人词库", isOn: $settings.enablePersonalVocabulary)

                if settings.enablePersonalVocabulary {
                    HStack {
                        Text("已学习 \(VocabularyManager.shared.items.count) 个词汇")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("管理词库") {
                            showVocabularyView = true
                        }
                    }
                    Text("词库通过编辑历史记录自动学习，也可手动添加。纠正词库会在润色时自动应用。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("个人词库")
            }

            Section {
                Picker("应用语言", selection: $settings.appLanguage) {
                    ForEach(AppSettings.AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } header: {
                Text("语言")
            }

            Section {
                Toggle("启用空闲卸载", isOn: Binding(
                    get: { settings.idleUnloadMinutes > 0 },
                    set: { settings.idleUnloadMinutes = $0 ? 10 : 0 }
                ))
                if settings.idleUnloadMinutes > 0 {
                    HStack {
                        Text("空闲卸载模型")
                        Spacer()
                        Stepper("\(settings.idleUnloadMinutes) 分钟", value: $settings.idleUnloadMinutes, in: 1...60)
                    }
                }
                Text("空闲一段时间后自动卸载模型以释放内存，下次使用时自动重新加载。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("内存管理")
            }

            Section {
                Picker("性能模式", selection: $settings.performanceMode) {
                    ForEach(AppSettings.PerformanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("内存模式", selection: $settings.memoryMode) {
                    ForEach(AppSettings.MemoryMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("性能优化")
            }

            Section {
                Picker("启动方式", selection: .constant(false)) {
                    Text("用户手动启动").tag(false)
                    Text("登录时自动启动").tag(true)
                }
                .disabled(true)

                Picker("退出行为", selection: $settings.quitBehavior) {
                    Text("完全退出").tag(true)
                    Text("最小化到菜单栏").tag(false)
                }
            } header: {
                Text("启动与退出")
            }

            Section {
                Toggle("启用详细日志", isOn: $settings.enableDetailedLogging)

                Picker("日志级别", selection: $settings.logLevel) {
                    ForEach(AppSettings.LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("日志")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshPermissions()
            startPermissionPolling()
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
        .sheet(isPresented: $showVocabularyView) {
            VocabularyView()
        }
    }

    private func actionTitle(for permission: AppPermission) -> String {
        guard permission == .microphone else { return "打开设置" }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined ? "授权麦克风" : "打开设置"
    }

    private func handlePermissionAction(_ permission: AppPermission) {
        switch permission {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                PermissionManager.requestMicrophoneAccess { _ in
                    refreshPermissions()
                }
            } else {
                PermissionManager.openSettings(for: .microphone)
            }
        case .inputMonitoring:
            _ = PermissionManager.requestInputMonitoringAccessIfNeeded()
            PermissionManager.openSettings(for: .inputMonitoring)
        case .accessibility:
            PermissionManager.openSettings(for: .accessibility)
        }
    }

    private func refreshPermissions() {
        permissions = PermissionManager.snapshot()
    }

    private func startPermissionPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                refreshPermissions()
            }
        }
    }
}

// MARK: - DisplayName 扩展

extension AppSettings.RecordingTriggerMode {
    var displayName: String {
        switch self {
        case .pushToTalk: return "按住录音"
        case .toggle: return "点击切换"
        }
    }
}

extension AppSettings.ASRLanguage {
    var displayName: String {
        switch self {
        case .auto: return "自动检测"
        case .chinese: return "中文"
        case .english: return "英文"
        case .mixed: return "中英混合"
        }
    }
}

extension AppSettings.PolishIntensity {
    var displayName: String {
        switch self {
        case .light: return "轻度"
        case .medium: return "中度"
        case .strong: return "强度"
        }
    }
}

extension AppSettings.OutputMethod {
    var displayName: String {
        switch self {
        case .autoPaste: return "自动粘贴"
        case .clipboardOnly: return "仅复制到剪贴板"
        case .previewWindow: return "预览窗口"
        }
    }
}

extension AppSettings.OutputDelay {
    var displayName: String {
        switch self {
        case .immediate: return "立即输出"
        case .afterPolish: return "润色完成后"
        case .custom: return "自定义延迟"
        }
    }
}

extension AppSettings.AppLanguage {
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

extension AppSettings.PerformanceMode {
    var displayName: String {
        switch self {
        case .speed: return "优先速度"
        case .accuracy: return "优先准确率"
        case .balanced: return "平衡模式"
        }
    }
}

extension AppSettings.MemoryMode {
    var displayName: String {
        switch self {
        case .low: return "8GB 内存"
        case .normal: return "16GB+ 内存"
        case .auto: return "自动适配"
        }
    }
}

extension AppSettings.LogLevel {
    var displayName: String {
        switch self {
        case .debug: return "调试"
        case .info: return "信息"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }
}

extension AppSettings.ModelSource {
    var displayName: String {
        switch self {
        case .huggingface: return "HuggingFace（国际）"
        case .modelscope: return "ModelScope（中国大陆）"
        }
    }
}
