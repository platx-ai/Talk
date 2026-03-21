//
//  SettingsView.swift
//  Talk
//
//  设置视图
//

import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.load()
    @State private var showHotKeyPicker = false

    var body: some View {
        TabView {
            RecordingSettingsTab(settings: $settings)
                .tabItem { Label("录音", systemImage: "mic.circle") }

            ASRSettingsTab(settings: $settings)
                .tabItem { Label("语音识别", systemImage: "waveform") }

            LLMSettingsTab(settings: $settings)
                .tabItem { Label("文本润色", systemImage: "sparkles") }

            OutputSettingsTab(settings: $settings)
                .tabItem { Label("输出", systemImage: "text.bubble") }

            AdvancedSettingsTab(settings: $settings)
                .tabItem { Label("高级", systemImage: "gearshape.2") }
        }
        .frame(width: 600, height: 500)
        .onDisappear {
            settings.save()
            AppDelegate.shared?.reloadHotKeyFromSettings()
        }
    }
}

// MARK: - 录音设置标签页

private struct RecordingSettingsTab: View {
    @Binding var settings: AppSettings
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

                KeyRecorderView(hotkey: $settings.recordingHotkey)
                    .onChange(of: settings.recordingHotkey) {
                        settings.save()
                        AppDelegate.shared?.reloadHotKeyFromSettings()
                    }

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
    @Binding var settings: AppSettings

    var body: some View {
        Form {
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
    @Binding var settings: AppSettings

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
                Text("润色功能说明：").font(.caption)
                Text("• 去除口语填充词（嗯、啊、呃等）").font(.caption)
                Text("• 添加合适的标点符号").font(.caption)
                Text("• 理解拼写说明（C-L-A-U-D-E → Claude）").font(.caption)
                Text("• 自我修正识别（不对，其实是...）").font(.caption)
                Text("• 智能排版（分段、列表）").font(.caption)
            } header: {
                Text("润色功能")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 输出设置标签页

private struct OutputSettingsTab: View {
    @Binding var settings: AppSettings

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
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("启用命令词识别", isOn: $settings.enableVoiceCommands)
                Toggle("启用个人词库", isOn: $settings.enablePersonalVocabulary)
            } header: {
                Text("高级功能")
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
