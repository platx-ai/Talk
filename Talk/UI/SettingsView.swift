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
                .tabItem { Image(systemName: "mic.circle") }

            ASRSettingsTab(settings: settings)
                .tabItem { Image(systemName: "waveform") }

            LLMSettingsTab(settings: settings)
                .tabItem { Image(systemName: "sparkles") }

            OutputSettingsTab(settings: settings)
                .tabItem { Image(systemName: "text.bubble") }

            AdvancedSettingsTab(settings: settings)
                .tabItem { Image(systemName: "gearshape.2") }
        }
        .frame(width: 600, height: 520)
        .toast()
    }
}

// MARK: - 录音设置标签页

private struct RecordingSettingsTab: View {
    @Bindable var settings: AppSettings
    @State private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "输入设备"), selection: $settings.selectedAudioDeviceUID) {
                    Text(String(localized: "内置麦克风（默认）")).tag(nil as String?)
                    ForEach(deviceManager.inputDevices.filter { !$0.isBuiltIn }) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
            } header: {
                Text(String(localized: "音频输入"))
            }

            Section {
                Picker(String(localized: "触发方式"), selection: $settings.recordingTriggerMode) {
                    ForEach(AppSettings.RecordingTriggerMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: settings.recordingTriggerMode) {
                    AppDelegate.shared?.applyHotKey(settings.recordingHotkey, triggerMode: settings.recordingTriggerMode)
                    ToastManager.shared.show(String(localized: "已保存"))
                }

                KeyRecorderView(hotkey: $settings.recordingHotkey) { newCombo in
                    settings.recordingHotkey = newCombo
                    settings.save()
                    AppDelegate.shared?.applyHotKey(newCombo, triggerMode: settings.recordingTriggerMode)
                    ToastManager.shared.show(String(localized: "已保存"))
                }

                Text(String(localized: "全局快捷键依赖输入监控权限。若快捷键无反应，请在系统设置 → 隐私与安全性 → 输入监控中开启 Talk，并重启应用。"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text(String(localized: "录音时长限制"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.recordingMaxDuration > 0 },
                        set: { settings.recordingMaxDuration = $0 ? 0 : 60 }
                    ))
                    .onChange(of: settings.recordingMaxDuration) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                    if settings.recordingMaxDuration > 0 {
                        Stepper("\(settings.recordingMaxDuration)s",
                                value: $settings.recordingMaxDuration,
                                in: 1...300)
                    }
                }
            } header: {
                Text(String(localized: "录音设置"))
            }

            Section {
                HStack {
                    Text(String(localized: "音频采样率"))
                    Spacer()
                    Picker("", selection: $settings.sampleRate) {
                        Text("16 kHz").tag(16000)
                        Text("44.1 kHz").tag(44100)
                        Text("48 kHz").tag(48000)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    .onChange(of: settings.sampleRate) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                }
            } header: {
                Text(String(localized: "音频参数"))
            }

            Section {
                Toggle(String(localized: "录音时菜单栏图标变化"), isOn: .constant(true))
                Toggle(String(localized: "播放提示音"), isOn: .constant(false))
            } header: {
                Text(String(localized: "录音提示"))
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
            // 引擎选择
            Section {
                Picker(String(localized: "识别引擎"), selection: $settings.asrEngine) {
                    ForEach(AppSettings.ASREngine.allCases, id: \.self) { engine in
                        VStack(alignment: .leading) {
                            Text(engine.displayName)
                        }.tag(engine)
                    }
                }
                .onChange(of: settings.asrEngine) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                Text(settings.asrEngine.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(String(localized: "语音识别引擎"))
            }

            // 引擎专属设置
            switch settings.asrEngine {
            case .mlxLocal:
                mlxLocalSettings
            case .appleSpeech:
                appleSpeechSettings
            case .gemma4:
                gemma4Settings
            }

            // 一段式模式提示
            if settings.isOnePassMode {
                Section {
                    Label(String(localized: "一段式模式：Gemma 4 直接输出润色文本，跳过独立的 LLM 润色步骤。"), systemImage: "bolt.fill")
                        .font(.callout)
                        .foregroundStyle(.blue)
                } header: {
                    Text(String(localized: "一段式模式"))
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - MLX 本地模型设置

    @ViewBuilder
    private var mlxLocalSettings: some View {
        Section {
            Picker(String(localized: "下载源"), selection: $settings.modelSource) {
                Text(String(localized: "HuggingFace（国际）")).tag(AppSettings.ModelSource.huggingface)
                Text(String(localized: "ModelScope（中国大陆）")).tag(AppSettings.ModelSource.modelscope)
            }
            .onChange(of: settings.modelSource) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            Text(String(localized: "中国大陆用户建议选择 ModelScope，可避免网络问题。"))
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(String(localized: "模型下载源"))
        }

        Section {
            Picker(String(localized: "模型选择"), selection: $settings.asrModelId) {
                Text("Qwen3-ASR-0.6B-4bit").tag("mlx-community/Qwen3-ASR-0.6B-4bit")
            }
            .onChange(of: settings.asrModelId) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Picker(String(localized: "识别语言"), selection: $settings.asrLanguage) {
                ForEach(AppSettings.ASRLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .onChange(of: settings.asrLanguage) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Toggle(String(localized: "启用流式识别（边录边出字）"), isOn: $settings.enableStreamingInference)
                .onChange(of: settings.enableStreamingInference) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Toggle(String(localized: "显示实时识别文字（仅流式模式）"), isOn: $settings.showRealtimeRecognition)
                .disabled(!settings.enableStreamingInference)
                .onChange(of: settings.showRealtimeRecognition) { _ in ToastManager.shared.show(String(localized: "已保存")) }
        } header: {
            Text(String(localized: "语音识别设置"))
        }

        Section {
            Toggle(String(localized: "启用静音过滤（Silero VAD）"), isOn: $settings.enableVADFilter)
                .onChange(of: settings.enableVADFilter) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            if settings.enableVADFilter {
                HStack {
                    Text(String(localized: "语音阈值"))
                    Spacer()
                    Text(String(format: "%.2f", settings.vadThreshold))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.vadThreshold, in: 0.1...0.9, step: 0.05)
                    .onChange(of: settings.vadThreshold) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                HStack {
                    Text(String(localized: "前后补偿帧"))
                    Spacer()
                    Stepper("\(settings.vadPaddingChunks)",
                            value: $settings.vadPaddingChunks,
                            in: 0...8)
                }
                .onChange(of: settings.vadPaddingChunks) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                HStack {
                    Text(String(localized: "最少语音帧"))
                    Spacer()
                    Stepper("\(settings.vadMinSpeechChunks)",
                            value: $settings.vadMinSpeechChunks,
                            in: 1...16)
                }
                .onChange(of: settings.vadMinSpeechChunks) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            }

            Text(String(localized: "开启后会在批量识别前过滤静音，减少空白输入。阈值越高越严格。"))
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(String(localized: "静音检测（VAD）"))
        }
    }

    // MARK: - Apple Speech 设置

    @ViewBuilder
    private var appleSpeechSettings: some View {
        Section {
            Picker(String(localized: "识别语言"), selection: $settings.appleSpeechLocale) {
                ForEach(AppSettings.AppleSpeechLocale.allCases, id: \.self) { locale in
                    Text(locale.displayName).tag(locale)
                }
            }
            .onChange(of: settings.appleSpeechLocale) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Toggle(String(localized: "仅设备端识别（离线）"), isOn: $settings.appleSpeechOnDevice)
                .onChange(of: settings.appleSpeechOnDevice) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Toggle(String(localized: "显示实时识别文字"), isOn: $settings.appleSpeechShowRealtime)
                .onChange(of: settings.appleSpeechShowRealtime) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Text(String(localized: "Apple 语音识别天然支持流式输出，无需额外配置。设备端识别可离线使用，但精度可能略低。"))
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(String(localized: "Apple 语音识别设置"))
        }
    }

    // MARK: - Gemma 4 设置

    @ViewBuilder
    private var gemma4Settings: some View {
        Section {
            Picker(String(localized: "模型大小"), selection: $settings.gemma4ModelSize) {
                ForEach(AppSettings.Gemma4ModelSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .onChange(of: settings.gemma4ModelSize) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Toggle(String(localized: "繁→简转换"), isOn: $settings.gemma4EnableT2S)
                .onChange(of: settings.gemma4EnableT2S) { _ in ToastManager.shared.show(String(localized: "已保存")) }

            Text(String(localized: "Gemma 4 多模态模型，支持音频直接转文字。4B 精度更高，2B 更快更轻量。实验性功能。"))
                .font(.caption)
                .foregroundColor(.secondary)

            if settings.asrEngine == .gemma4 && settings.llmEngine != .gemma4 {
                Label(String(localized: "Gemma 4 单独做 ASR 效果不如 Qwen3-ASR，建议搭配 Gemma 4 润色使用（LLM 引擎也选 Gemma 4）。音频上限 30 秒。"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Gemma 4")
        }
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
                Picker(String(localized: "LLM 引擎"), selection: $settings.llmEngine) {
                    ForEach(AppSettings.LLMEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .onChange(of: settings.llmEngine) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                if settings.isOnePassMode {
                    Label(String(localized: "一段式模式：ASR 和 LLM 共用 Gemma 4，润色强度和自定义提示词仍然生效。"), systemImage: "bolt.fill")
                        .font(.callout)
                        .foregroundStyle(.blue)
                } else if settings.llmEngine == .gemma4 {
                    Label(String(localized: "Gemma 4 润色模式：能听原始音频修正 ASR 错误，效果更好。"), systemImage: "waveform.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            } header: {
                Text(String(localized: "引擎"))
            }

            Section {
                Picker(String(localized: "模型选择"), selection: $settings.llmModelId) {
                    Text("Qwen3-4B (2.1GB)").tag("mlx-community/Qwen3-4B-Instruct-2507-4bit")
                    Text("⭐ Qwen3.5-4B (2.8GB)").tag("mlx-community/Qwen3.5-4B-OptiQ-4bit")
                    Text("Qwen3.5-2B (1.6GB)").tag("mlx-community/Qwen3.5-2B-4bit")
                }
                .onChange(of: settings.llmModelId) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                .disabled(settings.llmEngine == .gemma4)

                Picker(String(localized: "润色强度"), selection: $settings.polishIntensity) {
                    ForEach(AppSettings.PolishIntensity.allCases, id: \.self) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                .onChange(of: settings.polishIntensity) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                HStack {
                    Text(String(localized: "对话历史轮数"))
                    Spacer()
                    Stepper("\(settings.conversationHistoryRounds)",
                            value: $settings.conversationHistoryRounds,
                            in: 0...10)
                }
                .onChange(of: settings.conversationHistoryRounds) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                Toggle(String(localized: "启用对话历史"), isOn: $settings.enableConversationHistory)
                    .onChange(of: settings.enableConversationHistory) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            } header: {
                Text(String(localized: "文本润色设置"))
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
                    Picker(String(localized: "添加应用"), selection: $newAppBundleId) {
                        Text(String(localized: "选择应用...")).tag("")

                        let existingIds = Set(settings.appPrompts.keys)
                        let runningApps = NSWorkspace.shared.runningApplications
                            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                            .compactMap { app -> (String, String)? in
                                guard let bid = app.bundleIdentifier, !existingIds.contains(bid) else { return nil }
                                return (bid, app.localizedName ?? bid)
                            }
                            .sorted { $0.1 < $1.1 }

                        if !runningApps.isEmpty {
                            Section(String(localized: "正在运行")) {
                                ForEach(runningApps, id: \.0) { bid, name in
                                    Text(name).tag(bid)
                                }
                            }
                        }

                        let wellKnownIds: [(String, String)] = [
                            ("com.apple.Terminal", String(localized: "终端")),
                            ("com.googlecode.iterm2", "iTerm2"),
                            ("com.microsoft.VSCode", "VS Code"),
                            ("com.apple.dt.Xcode", "Xcode"),
                            ("com.tencent.xinWeChat", String(localized: "微信")),
                            ("com.tinyspeck.slackmacgap", "Slack"),
                            ("com.apple.mail", String(localized: "邮件")),
                            ("com.apple.Notes", String(localized: "备忘录")),
                            ("com.bytedance.lark.mac", String(localized: "飞书")),
                        ].filter { item in !existingIds.contains(item.0) && !runningApps.contains { r in r.0 == item.0 } }

                        if !wellKnownIds.isEmpty {
                            Section(String(localized: "常用应用")) {
                                ForEach(wellKnownIds, id: \.0) { bid, name in
                                    Text(name).tag(bid)
                                }
                            }
                        }
                    }
                    Button(String(localized: "添加")) {
                        guard !newAppBundleId.isEmpty else { return }
                        if settings.appPrompts[newAppBundleId] == nil {
                            settings.appPrompts[newAppBundleId] = defaultPromptForApp(newAppBundleId)
                        }
                        newAppBundleId = ""
                    }
                    .disabled(newAppBundleId.isEmpty)
                }

                Text(String(localized: "为不同应用设置专属提示词。录音时自动检测前台应用并使用对应提示词。未配置的应用使用全局提示词。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(String(localized: "应用专属提示词"))
            }

            Section {
                Picker(String(localized: "提示词类型"), selection: $promptTab) {
                    Text(String(localized: "听写润色")).tag(0)
                    Text(String(localized: "编辑指令")).tag(1)
                }
                .pickerStyle(.segmented)

                if promptTab == 0 {
                    // 听写润色提示词
                    HStack {
                        if settings.customSystemPrompt.isEmpty {
                            Label(String(localized: "使用默认"), systemImage: "checkmark.circle")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Label(String(localized: "自定义"), systemImage: "pencil.circle.fill")
                                .font(.caption).foregroundColor(.orange)
                        }
                        Spacer()
                        Menu(String(localized: "预设模板")) {
                            Button(String(localized: "严格纠错")) {
                                settings.customSystemPrompt = String(localized: "你是一个严格的文本纠错助手。只修正明显的语音识别错误和错别字，不改变原文的表达方式、语气和结构。直接输出修正后的文本，不要添加任何解释。")
                            }
                            Button(String(localized: "轻度润色")) {
                                settings.customSystemPrompt = String(localized: "你是一个文本清理助手。去除口语填充词（嗯、啊、呃），添加标点符号，修正明显错误。保留原文的表达风格和语气，不做改写。直接输出清理后的文本，不要添加任何解释。")
                            }
                            Button(String(localized: "会议纪要")) {
                                settings.customSystemPrompt = String(localized: "你是一个会议纪要整理助手。将语音识别的会议内容整理为结构化的纪要格式：提取要点、决议和待办事项。直接输出纪要，不要添加任何解释。")
                            }
                            Button(String(localized: "技术文档")) {
                                settings.customSystemPrompt = String(localized: "你是一个技术文档整理助手。将语音输入整理为技术文档风格：保留代码标识符和技术术语的原文，使用 Markdown 格式。直接输出文档，不要添加任何解释。")
                            }
                        }
                        Button(String(localized: "填入默认")) { settings.customSystemPrompt = LLMService.defaultSystemPrompt }
                    }

                    TextEditor(text: $settings.customSystemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                    Text(String(localized: "留空使用默认提示词。自定义后润色强度选项被忽略。"))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    // 编辑指令提示词
                    HStack {
                        if settings.customEditPrompt.isEmpty {
                            Label(String(localized: "使用默认"), systemImage: "checkmark.circle")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Label(String(localized: "自定义"), systemImage: "pencil.circle.fill")
                                .font(.caption).foregroundColor(.orange)
                        }
                        Spacer()
                        Button(String(localized: "填入默认")) { settings.customEditPrompt = LLMService.defaultEditPrompt }
                    }

                    TextEditor(text: $settings.customEditPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                    Text(String(localized: "选中文字后录音进入编辑模式。语音作为指令，可用于替换词语、风格改写、纠错、格式转换等。"))
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Text(String(localized: "提示词"))
            }
        }
        .formStyle(.grouped)
    }

    private func appDisplayName(for bundleId: String) -> String {
        let wellKnown: [String: String] = [
            "com.apple.Terminal": String(localized: "终端"),
            "com.googlecode.iterm2": "iTerm2",
            "com.microsoft.VSCode": "VS Code",
            "com.apple.dt.Xcode": "Xcode",
            "com.tencent.xinWeChat": String(localized: "微信"),
            "com.tinyspeck.slackmacgap": "Slack",
            "com.apple.mail": String(localized: "邮件"),
            "com.apple.Notes": String(localized: "备忘录"),
            "com.bytedance.lark.mac": String(localized: "飞书"),
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
            return String(localized: "保留命令行语法和技术术语。代码标识符、文件路径、命令名不要修改。直接输出清理后的文本。")
        case "com.microsoft.VSCode", "com.apple.dt.Xcode":
            return String(localized: "保留代码变量名、函数名和技术术语。使用技术文档风格，Markdown 格式。直接输出清理后的文本。")
        case "com.tencent.xinWeChat", "com.tinyspeck.slackmacgap", "com.bytedance.lark.mac":
            return String(localized: "口语化，简洁，适合即时通讯。不要过度正式化。直接输出清理后的文本。")
        case "com.apple.mail":
            return String(localized: "正式语气，添加适当的问候和结尾。直接输出清理后的文本。")
        case "com.apple.Notes":
            return String(localized: "结构化笔记格式，使用标题和项目符号列表。直接输出清理后的文本。")
        default:
            return String(localized: "直接输出清理后的文本，不要添加任何解释。")
        }
    }
}

// MARK: - 输出设置标签页

private struct OutputSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "输出方式"), selection: $settings.outputMethod) {
                    Text(String(localized: "自动粘贴到当前应用")).tag(AppSettings.OutputMethod.autoPaste)
                    Text(String(localized: "仅复制到剪贴板")).tag(AppSettings.OutputMethod.clipboardOnly)
                }
                .onChange(of: settings.outputMethod) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                Text(String(localized: "自动粘贴：润色完成后模拟 Cmd+V 粘贴到前台应用。仅剪贴板：结果只放入剪贴板，需手动粘贴。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(String(localized: "输出设置"))
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
                Text(String(localized: "权限"))
            }

            Section {
                Picker(String(localized: "选中文本捕获方式"), selection: $settings.selectionCaptureMethod) {
                    Text(String(localized: "Accessibility API（低侵入）")).tag(AppSettings.SelectionCaptureMethod.accessibility)
                    Text(String(localized: "Cmd+C 复制（兼容性好）")).tag(AppSettings.SelectionCaptureMethod.clipboard)
                }
                .onChange(of: settings.selectionCaptureMethod) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                Text(String(localized: "选中文字后录音可替换选中内容。Accessibility API 不影响剪贴板但部分应用不支持。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(String(localized: "选中修正"))
            }

            Section {
                Toggle(String(localized: "启用命令词识别"), isOn: $settings.enableVoiceCommands)
                    .onChange(of: settings.enableVoiceCommands) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            } header: {
                Text(String(localized: "高级功能"))
            }

            Section {
                Toggle(String(localized: "启用个人词库"), isOn: $settings.enablePersonalVocabulary)
                    .onChange(of: settings.enablePersonalVocabulary) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                if settings.enablePersonalVocabulary {
                    HStack {
                        Text("\(VocabularyManager.shared.items.count) \(String(localized: "词汇"))")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(String(localized: "管理词库")) {
                            showVocabularyView = true
                        }
                    }
                    Text(String(localized: "词库通过编辑历史记录自动学习，也可手动添加。纠正词库会在润色时自动应用。"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(String(localized: "自动热词学习"), isOn: $settings.enableAutoHotwordLearning)
                        .onChange(of: settings.enableAutoHotwordLearning) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                    Text(String(localized: "注入文本后自动观察编辑，学习 ASR 常错的词汇。"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(String(localized: "保存录音历史"), isOn: $settings.enableAudioHistory)
                        .onChange(of: settings.enableAudioHistory) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                    Text(String(localized: "保存每次录音的音频和上下文，用于复盘调试和优化。"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(String(localized: "个人词库"))
            }

            Section {
                Picker(String(localized: "应用语言"), selection: $settings.appLanguage) {
                    ForEach(AppSettings.AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: settings.appLanguage) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            } header: {
                Text(String(localized: "语言"))
            }

            Section {
                Toggle(String(localized: "启用空闲卸载"), isOn: Binding(
                    get: { settings.idleUnloadMinutes > 0 },
                    set: { settings.idleUnloadMinutes = $0 ? 10 : 0 }
                ))
                .onChange(of: settings.idleUnloadMinutes) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                if settings.idleUnloadMinutes > 0 {
                    Picker(String(localized: "空闲卸载模型"), selection: $settings.idleUnloadMinutes) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    .onChange(of: settings.idleUnloadMinutes) { _ in ToastManager.shared.show(String(localized: "已保存")) }
                }
                Text(String(localized: "空闲一段时间后自动卸载模型以释放内存，下次使用时自动重新加载。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(String(localized: "内存管理"))
            }

            Section {
                Picker(String(localized: "性能模式"), selection: $settings.performanceMode) {
                    ForEach(AppSettings.PerformanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: settings.performanceMode) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                Picker(String(localized: "内存模式"), selection: $settings.memoryMode) {
                    ForEach(AppSettings.MemoryMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: settings.memoryMode) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            } header: {
                Text(String(localized: "性能优化"))
            }

            Section {
                Picker(String(localized: "启动方式"), selection: .constant(false)) {
                    Text(String(localized: "用户手动启动")).tag(false)
                    Text(String(localized: "登录时自动启动")).tag(true)
                }
                .disabled(true)

                Picker(String(localized: "退出行为"), selection: $settings.quitBehavior) {
                    Text(String(localized: "完全退出")).tag(true)
                    Text(String(localized: "最小化到菜单栏")).tag(false)
                }
                .onChange(of: settings.quitBehavior) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            } header: {
                Text(String(localized: "启动与退出"))
            }

            Section {
                Toggle(String(localized: "启用详细日志"), isOn: $settings.enableDetailedLogging)
                    .onChange(of: settings.enableDetailedLogging) { _ in ToastManager.shared.show(String(localized: "已保存")) }

                Picker(String(localized: "日志级别"), selection: $settings.logLevel) {
                    ForEach(AppSettings.LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.logLevel) { _ in ToastManager.shared.show(String(localized: "已保存")) }
            } header: {
                Text(String(localized: "日志"))
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
        guard permission == .microphone else { return String(localized: "打开设置") }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined ? String(localized: "授权麦克风") : String(localized: "打开设置")
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
        case .pushToTalk: return String(localized: "按住录音")
        case .toggle: return String(localized: "点击切换")
        }
    }
}

extension AppSettings.ASRLanguage {
    var displayName: String {
        switch self {
        case .auto: return String(localized: "自动检测")
        case .chinese: return String(localized: "中文")
        case .english: return String(localized: "英文")
        case .mixed: return String(localized: "中英混合")
        }
    }
}

extension AppSettings.PolishIntensity {
    var displayName: String {
        switch self {
        case .light: return String(localized: "轻度")
        case .medium: return String(localized: "中度")
        case .strong: return String(localized: "强度")
        }
    }
}

extension AppSettings.OutputMethod {
    var displayName: String {
        switch self {
        case .autoPaste: return String(localized: "自动粘贴")
        case .clipboardOnly: return String(localized: "仅复制到剪贴板")
        case .previewWindow: return String(localized: "预览窗口")
        }
    }
}

extension AppSettings.OutputDelay {
    var displayName: String {
        switch self {
        case .immediate: return String(localized: "立即输出")
        case .afterPolish: return String(localized: "润色完成后")
        case .custom: return String(localized: "自定义延迟")
        }
    }
}

extension AppSettings.AppLanguage {
    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .chinese: return String(localized: "简体中文")
        case .english: return "English"
        }
    }
}

extension AppSettings.PerformanceMode {
    var displayName: String {
        switch self {
        case .speed: return String(localized: "优先速度")
        case .accuracy: return String(localized: "优先准确率")
        case .balanced: return String(localized: "平衡模式")
        }
    }
}

extension AppSettings.MemoryMode {
    var displayName: String {
        switch self {
        case .low: return String(localized: "8GB 内存")
        case .normal: return String(localized: "16GB+ 内存")
        case .auto: return String(localized: "自动适配")
        }
    }
}

extension AppSettings.LogLevel {
    var displayName: String {
        switch self {
        case .debug: return String(localized: "调试")
        case .info: return String(localized: "信息")
        case .warning: return String(localized: "警告")
        case .error: return String(localized: "错误")
        }
    }
}

extension AppSettings.ModelSource {
    var displayName: String {
        switch self {
        case .huggingface: return String(localized: "HuggingFace（国际）")
        case .modelscope: return String(localized: "ModelScope（中国大陆）")
        }
    }
}

extension AppSettings.ASREngine {
    var displayName: String {
        switch self {
        case .mlxLocal: return String(localized: "本地模型 (Qwen3-ASR)")
        case .appleSpeech: return String(localized: "Apple 语音识别")
        case .gemma4: return "Gemma 4"
        }
    }

    var subtitle: String {
        switch self {
        case .mlxLocal: return String(localized: "离线 · 高精度 · 需下载模型")
        case .appleSpeech: return String(localized: "零配置 · 流式输出 · 系统内置")
        case .gemma4: return String(localized: "多模态 · 端到端 · 实验性")
        }
    }
}

extension AppSettings.LLMEngine {
    var displayName: String {
        switch self {
        case .qwen3: return "Qwen 3.5"
        case .gemma4: return "Gemma 4"
        }
    }
}

extension AppSettings.Gemma4ModelSize {
    var displayName: String {
        switch self {
        case .e2b: return "2B (1.5 GB, 0.3s)"
        case .e4b: return "4B (5.2 GB, 0.5s)"
        }
    }
}

extension AppSettings.AppleSpeechLocale {
    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .zhCN: return String(localized: "中文（简体）")
        case .zhTW: return String(localized: "中文（繁体）")
        case .enUS: return "English (US)"
        case .enGB: return "English (UK)"
        case .ja: return String(localized: "日语")
        case .ko: return String(localized: "韩语")
        }
    }

    /// Convert to Locale for SFSpeechRecognizer
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .zhCN: return Locale(identifier: "zh-CN")
        case .zhTW: return Locale(identifier: "zh-TW")
        case .enUS: return Locale(identifier: "en-US")
        case .enGB: return Locale(identifier: "en-GB")
        case .ja: return Locale(identifier: "ja-JP")
        case .ko: return Locale(identifier: "ko-KR")
        }
    }
}
