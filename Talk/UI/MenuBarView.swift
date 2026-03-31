//
//  MenuBarView.swift
//  Talk
//
//  菜单栏视图
//

import SwiftUI
import Combine

struct MenuBarView: View {
    @ObservedObject var viewModel: MenuViewModel

    var onOpenSettings: () -> Void = {}
    var onOpenHistory: () -> Void = {}

    var body: some View {
        Menu {
            Section {
                Button(action: startRecording) {
                    Label(String(localized: "开始录音"), systemImage: "mic.fill")
                }
                .disabled(viewModel.isRecording)

                Button(action: stopRecording) {
                    Label(String(localized: "停止录音"), systemImage: "stop.circle.fill")
                }
                .disabled(!viewModel.isRecording)

                Divider()

                Label(viewModel.processingStatus.localizedName, systemImage: getStatusIcon())
                    .foregroundColor(viewModel.processingStatus == .idle ? .primary : .accentColor)
            }

            Section {
                Button(action: onOpenHistory) {
                    Label(String(localized: "历史记录"), systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                Button(action: onOpenSettings) {
                    Label(String(localized: "设置..."), systemImage: "gearshape.fill")
                }

                Button(action: clearHistory) {
                    Label(String(localized: "清空历史"), systemImage: "trash.fill")
                }
            }

            Divider()

            Button(action: quitApp) {
                Label(String(localized: "退出 Talk"), systemImage: "power")
            }
        } label: {
            if viewModel.isRecording {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .foregroundStyle(.red)
            } else {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 30, height: 20)
    }

    private func getStatusIcon() -> String {
        switch viewModel.processingStatus {
        case .idle: return "circle.fill"
        case .loadingModel: return "arrow.down.circle"
        case .recording: return "record.circle.fill"
        case .asr: return "waveform"
        case .polishing: return "sparkles"
        case .outputting: return "paperplane.fill"
        }
    }

    private func startRecording() { viewModel.startRecording() }
    private func stopRecording() { viewModel.stopRecording() }
    private func clearHistory() { viewModel.clearHistory() }
    private func quitApp() { viewModel.quitApp() }
}

extension MenuBarView {
    func onOpenSettings(_ action: @escaping () -> Void) -> Self {
        var view = self
        view.onOpenSettings = action
        return view
    }

    func onOpenHistory(_ action: @escaping () -> Void) -> Self {
        var view = self
        view.onOpenHistory = action
        return view
    }
}

// MARK: - View Model

@MainActor
class MenuViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var processingStatus: ProcessingStatus = .idle

    enum ProcessingStatus: String {
        case idle = "空闲"
        case loadingModel = "加载模型中..."
        case recording = "录音中..."
        case asr = "识别中..."
        case polishing = "润色中..."
        case outputting = "输出中..."

        var localizedName: String {
            String(localized: String.LocalizationValue(rawValue))
        }
    }

    var onOpenSettings: () -> Void = {}
    var onOpenHistory: () -> Void = {}

    func startRecording() {
        AppLogger.info("菜单栏：请求开始录音", category: .ui)

        Task {
            let didStart = await AppDelegate.shared?.startRecordingFromMenuBar() ?? false
            if !didStart {
                processingStatus = .idle
            }
        }
    }

    func stopRecording() {
        AppLogger.info("菜单栏：请求停止录音", category: .ui)

        Task {
            let didStop = await AppDelegate.shared?.stopRecordingFromMenuBar() ?? false
            if !didStop {
                processingStatus = .idle
            }
        }
    }

    func clearHistory() {
        HistoryManager.shared.clearAll()
        AppLogger.info("菜单栏：清空历史", category: .ui)
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
        AppLogger.info("菜单栏：退出应用", category: .ui)
    }
}
