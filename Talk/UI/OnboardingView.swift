//
//  OnboardingView.swift
//  Talk
//
//  首次启动引导视图
//

import SwiftUI
import AVFoundation

// MARK: - OnboardingView

struct OnboardingView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var currentStep = 0
    @Environment(\.dismiss) private var dismiss

    /// Callback invoked when onboarding completes (user taps "开始使用" or window closes)
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep(onNext: { currentStep = 1 })
                case 1:
                    PermissionsStep(onNext: { currentStep = 2 })
                case 2:
                    ModelDownloadStep(settings: settings, onNext: { currentStep = 3 })
                case 3:
                    HotkeyStep(settings: settings, onNext: { currentStep = 4 })
                case 4:
                    ReadyStep(settings: settings, onComplete: {
                        settings.hasCompletedOnboarding = true
                        onComplete?()
                    })
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Step indicator
            if currentStep < 5 {
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Talk")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("按住说话，自动输入")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Talk 是 macOS 语音输入工具。按下快捷键说话，AI 自动识别、润色并输入到光标位置。全部在本地运行，无需联网。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button(action: onNext) {
                Text("开始设置")
                    .frame(maxWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Step 2: Permissions

private struct PermissionsStep: View {
    var onNext: () -> Void

    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("权限设置")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Talk 需要以下权限才能正常工作")
                .font(.body)
                .foregroundColor(.secondary)

            // Microphone permission
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "mic.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("麦克风权限")
                            .font(.headline)
                        Text("Talk 需要录制你的语音，音频仅在本地处理，不会上传任何服务器。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if micGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                    } else {
                        Button("授权麦克风") {
                            requestMicrophoneAccess()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }
            .padding(.horizontal, 24)

            // Accessibility permission
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("辅助功能权限")
                            .font(.headline)
                        Text("Talk 需要辅助功能权限来将文字自动粘贴到当前应用。请在系统设置中手动授予。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                    } else {
                        Button("打开设置") {
                            openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }
            .padding(.horizontal, 24)

            if !accessibilityGranted {
                Text("在「系统设置 → 隐私与安全性 → 辅助功能」中添加 Talk 并打开开关。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
            }

            Spacer()

            HStack(spacing: 16) {
                Button("稍后设置") {
                    onNext()
                }
                .controlSize(.large)

                Button(action: onNext) {
                    Text("继续")
                        .frame(maxWidth: 120)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!micGranted)
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            checkMicrophoneStatus()
            checkAccessibilityStatus()
            startAccessibilityPolling()
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micGranted = granted
            }
        }
    }

    private func checkMicrophoneStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        micGranted = status == .authorized
    }

    private func checkAccessibilityStatus() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                accessibilityGranted = AXIsProcessTrusted()
            }
        }
    }
}

// MARK: - Step 3: Model Download

private struct ModelDownloadStep: View {
    @Bindable var settings: AppSettings
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("下载 AI 模型")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Talk 使用本地 AI 模型进行语音识别和文本润色，首次使用需下载约 3GB 模型文件。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Model source picker
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择下载源")
                        .font(.headline)

                    Picker("", selection: $settings.modelSource) {
                        Text("HuggingFace（国际）").tag(AppSettings.ModelSource.huggingface)
                        Text("ModelScope（中国大陆）").tag(AppSettings.ModelSource.modelscope)
                    }
                    .pickerStyle(.radioGroup)

                    Text("中国大陆用户建议选择 ModelScope，可避免网络问题。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(4)
            }
            .padding(.horizontal, 24)

            // Model sizes info
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.blue)
                        Text("语音识别模型 (ASR)")
                        Spacer()
                        Text("~400 MB")
                            .foregroundColor(.secondary)
                    }
                    .font(.callout)

                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        Text("文本润色模型 (LLM)")
                        Spacer()
                        Text("~2.5 GB")
                            .foregroundColor(.secondary)
                    }
                    .font(.callout)
                }
                .padding(4)
            }
            .padding(.horizontal, 24)

            Text("模型将在首次使用时自动下载。也可在终端中运行 make download-models 手动下载。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Spacer()

            HStack(spacing: 16) {
                Button("跳过，稍后下载") {
                    onNext()
                }
                .controlSize(.large)

                Button(action: onNext) {
                    Text("继续")
                        .frame(maxWidth: 120)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Step 4: Hotkey Setup

private struct HotkeyStep: View {
    @Bindable var settings: AppSettings
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("设置快捷键")
                .font(.title2)
                .fontWeight(.semibold)

            Text("选择触发录音的快捷键和触发方式。")
                .font(.body)
                .foregroundColor(.secondary)

            // Key recorder
            GroupBox {
                KeyRecorderView(hotkey: $settings.recordingHotkey) { newCombo in
                    settings.recordingHotkey = newCombo
                    settings.save()
                }
                .padding(4)
            }
            .padding(.horizontal, 24)

            // Trigger mode picker
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("触发方式")
                        .font(.headline)

                    Picker("", selection: $settings.recordingTriggerMode) {
                        VStack(alignment: .leading) {
                            Text("按住说话 (Push-to-Talk)")
                        }
                        .tag(AppSettings.RecordingTriggerMode.pushToTalk)

                        VStack(alignment: .leading) {
                            Text("切换模式 (Toggle)")
                        }
                        .tag(AppSettings.RecordingTriggerMode.toggle)
                    }
                    .pickerStyle(.radioGroup)

                    Text(settings.recordingTriggerMode == .pushToTalk
                         ? "按住快捷键开始录音，松开后自动处理。推荐新用户使用。"
                         : "按一次开始录音，再按一次停止并处理。适合较长的口述场景。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(4)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onNext) {
                Text("完成设置")
                    .frame(maxWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Step 5: Ready

private struct ReadyStep: View {
    @Bindable var settings: AppSettings
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Talk 已就绪！")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(settings.recordingTriggerMode == .pushToTalk ? "按住" : "按下")
                    Text(settings.recordingHotkey.displayString)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    Text("开始说话")
                }
                .font(.title3)

                Text(settings.recordingTriggerMode == .pushToTalk
                     ? "松开后 AI 自动识别、润色并输入到光标位置"
                     : "再次按下停止录音，AI 自动识别、润色并输入到光标位置")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onComplete) {
                Text("开始使用")
                    .frame(maxWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Button("打开设置可以调整更多选项") {
                // Open settings window via the menu bar
                LocalTypeMenuBar.shared.openSettingsFromOnboarding()
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.bottom, 24)
        }
    }
}
