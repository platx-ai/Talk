//
//  AppleSpeechService.swift
//  Talk
//
//  Apple Speech Recognition 服务 — 基于 SFSpeechRecognizer 的流式语音识别
//

import Foundation
import Speech
import AVFoundation

/// Apple Speech Recognition 服务
@Observable
@MainActor
final class AppleSpeechService {
    // MARK: - 单例

    @MainActor static let shared = AppleSpeechService()

    // MARK: - 状态

    private(set) var isAvailable = false
    private(set) var isRecognizing = false

    // MARK: - 回调

    var onTranscriptionUpdate: ((_ confirmed: String, _ provisional: String) -> Void)?
    var onTranscriptionComplete: ((_ fullText: String) -> Void)?

    // MARK: - 内部状态

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// 累积的所有已完成段的文本（多段拼接，解决 ~60s 超时自动断开问题）
    private var confirmedSegments = ""

    /// 当前 task 的最新临时文本（用于 UI 显示）
    private var currentProvisional = ""

    /// 保存启动参数以便自动续接
    private var savedOnDevice = false

    /// 是否由用户主动停止（区分 Apple 超时自动断开）
    private var userStopped = false

    private init() {}

    // MARK: - 权限

    static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// 检查并请求语音识别权限，返回是否已授权
    static func ensurePermission() async -> Bool {
        let status = authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await requestPermission()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - 流式识别

    /// 开始流式识别
    func startStreaming(locale: Locale?, onDevice: Bool) throws {
        // 取消之前的任务
        cancelStreaming()

        // 创建 recognizer
        if let locale {
            recognizer = SFSpeechRecognizer(locale: locale)
        } else {
            recognizer = SFSpeechRecognizer() // 系统默认 locale
        }

        guard let recognizer, recognizer.isAvailable else {
            AppLogger.error("SFSpeechRecognizer 不可用", category: .asr)
            throw AppleSpeechError.recognizerUnavailable
        }

        isAvailable = true
        savedOnDevice = onDevice
        confirmedSegments = ""
        currentProvisional = ""
        userStopped = false
        isRecognizing = true

        startNewTask()

        AppLogger.info("Apple Speech: 流式识别已启动", category: .asr)
    }

    /// 启动一个新的 recognition task（首次或超时续接）
    private func startNewTask() {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if savedOnDevice {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                AppLogger.info("Apple Speech: 使用设备端识别", category: .asr)
            } else {
                AppLogger.warning("Apple Speech: 设备端识别不可用，回退到在线模式", category: .asr)
            }
        }

        request.contextualStrings = ["Talk", "MLX", "ASR", "LLM"]

        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
    }

    /// 送入音频 buffer（从 AVAudioEngine tap 来的 PCM buffer）
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    /// 送入原始 Float 采样（从 AudioRecorder.onAudioData 来的）
    func feedAudioSamples(_ samples: [Float], sampleRate: Int) {
        guard let request = recognitionRequest else { return }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { ptr in
                channelData[0].update(from: ptr.baseAddress!, count: samples.count)
            }
        }

        request.append(buffer)
    }

    /// 停止流式识别（结束音频输入，等待最终结果）
    func stopStreaming() {
        userStopped = true
        recognitionRequest?.endAudio()
        // 任务会在回调中自然结束（handleRecognitionResult 检测到 userStopped）
        // 如果还没开始过，直接完成
        if recognitionTask == nil {
            finishAndNotify()
        }
    }

    /// 取消识别（不等最终结果）
    func cancelStreaming() {
        userStopped = true
        recognitionTask?.cancel()
        cleanup()
    }

    // MARK: - 内部

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: (any Error)?) {
        if let result {
            let bestTranscription = result.bestTranscription.formattedString

            if result.isFinal {
                // 段结束 — 累积文本
                confirmedSegments += bestTranscription
                currentProvisional = ""

                if userStopped {
                    // 用户主动停止 — 返回完整结果
                    finishAndNotify()
                } else {
                    // Apple 超时自动断开 — 累积并续接新 task
                    AppLogger.info("Apple Speech: 段结束（超时续接），已累积 \(confirmedSegments.count) 字", category: .asr)
                    // 更新 UI 显示累积文本
                    onTranscriptionUpdate?(confirmedSegments, "")
                    // 清理当前 task 并启动新 task
                    recognitionRequest = nil
                    recognitionTask = nil
                    startNewTask()
                }
            } else {
                // 部分结果（provisional）— 显示累积文本 + 当前临时文本
                currentProvisional = bestTranscription
                onTranscriptionUpdate?(confirmedSegments, bestTranscription)
            }
        }

        if let error {
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // "No speech detected"
                AppLogger.debug("Apple Speech: 未检测到语音", category: .asr)
                if userStopped {
                    finishAndNotify()
                } else {
                    // 超时但没语音 — 续接
                    recognitionRequest = nil
                    recognitionTask = nil
                    startNewTask()
                }
            } else if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                // Cancelled by user
                AppLogger.debug("Apple Speech: 识别已取消", category: .asr)
                cleanup()
            } else {
                AppLogger.error("Apple Speech: 识别错误 — \(error.localizedDescription)", category: .asr)
                if userStopped {
                    finishAndNotify()
                } else {
                    // 尝试续接
                    recognitionRequest = nil
                    recognitionTask = nil
                    startNewTask()
                }
            }
        }
    }

    /// 结束识别并通知完整结果
    private func finishAndNotify() {
        let fullText = confirmedSegments + currentProvisional
        AppLogger.info("Apple Speech: 识别完成 — \(fullText.prefix(80))...", category: .asr)
        onTranscriptionComplete?(fullText)
        cleanup()
    }

    private func cleanup() {
        recognitionRequest = nil
        recognitionTask = nil
        isRecognizing = false
    }
}

// MARK: - ASREngineProtocol 适配

extension AppleSpeechService: ASREngineProtocol {
    var isReady: Bool { true }  // Apple Speech 无需加载模型

    func prepare() async throws {
        let granted = await Self.ensurePermission()
        if !granted {
            throw AppleSpeechError.permissionDenied
        }
    }

    func release() {
        cancelStreaming()
    }

    func startStreaming(config: ASREngineConfig) async throws {
        let settings = AppSettings.shared
        let locale: Locale?
        if settings.appleSpeechLocale == .system {
            locale = nil
        } else {
            locale = Locale(identifier: settings.appleSpeechLocale.rawValue)
        }
        try startStreaming(locale: locale, onDevice: settings.appleSpeechOnDevice)
    }

    func feedAudio(samples: [Float], sampleRate: Int) {
        feedAudioSamples(samples, sampleRate: sampleRate)
    }

    func transcribe(audio: [Float], sampleRate: Int) async throws -> String {
        throw ASREngineError.batchNotSupported
    }
}

// MARK: - 错误类型

enum AppleSpeechError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied
    case recognitionFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return String(localized: "Apple 语音识别不可用")
        case .permissionDenied:
            return String(localized: "语音识别权限被拒绝")
        case .recognitionFailed(let error):
            return String(localized: "语音识别失败: \(error.localizedDescription)")
        }
    }
}
