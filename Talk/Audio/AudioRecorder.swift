//
//  AudioRecorder.swift
//  Talk
//
//  音频录音器
//

import Foundation
import AVFoundation
import AudioToolbox

/// 音频录音器
final class AudioRecorder: NSObject, @unchecked Sendable {
    // MARK: - 单例

    static let shared = AudioRecorder()

    // MARK: - 属性

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioData: [Float] = []
    private var lastRecordedAudio: [Float] = []
    private var lastRecordingDuration: TimeInterval = 0
    private var recordingSampleRate: Double = 16000
    private var targetSampleRate: Double = 16000
    private var lastRecordingSampleRate: Double = 16000
    private(set) var isRecording = false
    private var recordingStartTime: Date?
    private var audioDataWatchdogTimer: DispatchSourceTimer?
    private var engineRetryCount = 0
    private var isRestartingEngine = false
    private let maxEngineRetries = 4

    var selectedDeviceUID: String? = nil

    var onAudioData: (([Float]) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onRecordingComplete: (([Float], TimeInterval) -> Void)?
    var onRecordingError: ((Error) -> Void)?

    private let stateLock = NSLock()

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    // MARK: - 初始化

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    // MARK: - 录音控制

    /// 创建新引擎并安装 tap，供 startRecording 和配置变更重启时复用
    private func setupAndStartEngine(sampleRate: Int) throws {
        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        inputNode = input

        // Apply selected audio device if specified
        // Set system default input device first (before creating AudioUnit)
        if let uid = selectedDeviceUID,
           let deviceID = AudioDeviceManager.deviceID(forUID: uid) {
            AudioDeviceManager.setDefaultInputDevice(deviceID: deviceID)
        }

        // Prepare the engine after setting device
        engine.prepare()

        // Get format AFTER setting device to ensure we use the correct device's format
        let inputFormat = input.outputFormat(forBus: 0)
        withStateLock {
            recordingSampleRate = inputFormat.sampleRate
        }

        // Capture rates once here — they are fixed for the duration of this engine session.
        // Avoid re-reading them inside the hot tap callback.
        let tapSrcRate = inputFormat.sampleRate
        let tapTgtRate: Double = withStateLock { targetSampleRate }
        let tapNeedsResample = abs(tapSrcRate - tapTgtRate) > 0.5
        // Closure-local flag: tap callbacks are serialized on the audio render thread,
        // so a plain Bool is safe without a lock.
        var tapHasLoggedResample = false

        input.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self = self else { return }

            guard let channels = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            var chunk: [Float] = []
            chunk.reserveCapacity(frameCount)

            if channelCount <= 1 {
                let mono = channels[0]
                for i in 0..<frameCount {
                    chunk.append(mono[i])
                }
            } else {
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for channel in 0..<channelCount {
                        sum += channels[channel][i]
                    }
                    chunk.append(sum / Float(channelCount))
                }
            }

            let shouldAppend = self.withStateLock { self.isRecording }
            guard shouldAppend else { return }

            self.withStateLock {
                self.audioData.append(contentsOf: chunk)
            }

            // Calculate RMS audio level for visual display
            if !chunk.isEmpty {
                let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
                let level = min(1.0, rms * 5.0)
                DispatchQueue.main.async {
                    self.onAudioLevel?(level)
                }
            }

            // Resample chunk to targetSampleRate before streaming to ASR.
            // The raw tap runs at the device's native hardware rate (e.g. 48 kHz),
            // but ASR expects 16 kHz.  Only the stopRecording() path resampled
            // previously; now we also resample here so onAudioData always emits
            // samples at targetSampleRate.
            let streamingChunk: [Float]
            if tapNeedsResample {
                streamingChunk = self.resampleLinear(chunk, from: tapSrcRate, to: tapTgtRate)
                // Log once per tap installation to confirm resampling is active.
                if !tapHasLoggedResample {
                    tapHasLoggedResample = true
                    AppLogger.debug(
                        "流式重采样已启动: \(Int(tapSrcRate))Hz -> \(Int(tapTgtRate))Hz，"
                        + "首块原始 \(chunk.count) 样点 -> 重采样后 \(streamingChunk.count) 样点",
                        category: .audio
                    )
                }
            } else {
                streamingChunk = chunk
            }

            DispatchQueue.main.async {
                self.onAudioData?(streamingChunk)
            }
        }

        try engine.start()
    }

    func startRecording(sampleRate: Int = 16000) throws {
        let alreadyRecording = withStateLock { isRecording }
        guard !alreadyRecording else {
            AppLogger.warning("已经在录音中", category: .audio)
            return
        }

        withStateLock {
            targetSampleRate = Double(sampleRate)
            lastRecordingSampleRate = Double(sampleRate)
            audioData = []
            lastRecordedAudio = []
            lastRecordingDuration = 0
            recordingStartTime = Date()
            isRecording = true
        }

        do {
            try setupAndStartEngine(sampleRate: sampleRate)
        } catch {
            withStateLock { isRecording = false }
            throw error
        }

        let actualRate = withStateLock { recordingSampleRate }
        AppLogger.info(
            "开始录音，硬件采样率: \(Int(actualRate))Hz，目标采样率: \(sampleRate)Hz",
            category: .audio
        )
        withStateLock { engineRetryCount = 0 }
        startAudioWatchdog(sampleRate: sampleRate)
    }

    /// 处理音频硬件配置变更（如蓝牙耳机连接/断开），重启引擎以使用新设备
    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        cancelAudioWatchdog()

        let shouldProceed: Bool = withStateLock {
            guard isRecording, !isRestartingEngine else { return false }
            isRestartingEngine = true
            return true
        }
        guard shouldProceed else { return }

        // Check if current system default device is the one we want
        // This prevents unnecessary restarts during Bluetooth device negotiation
        if let selectedUID = selectedDeviceUID,
           let currentDefaultID = AudioDeviceManager.getDefaultInputDeviceID(),
           let selectedID = AudioDeviceManager.deviceID(forUID: selectedUID) {
            // If current default is what we want, this is likely just a sample rate negotiation
            // We can skip the restart
            if currentDefaultID == selectedID {
                AppLogger.info("音频硬件配置变更，但设备未变（可能是采样率协商），跳过重启", category: .audio)
                withStateLock { isRestartingEngine = false }
                startAudioWatchdog(sampleRate: Int(targetSampleRate))
                return
            }
        }

        AppLogger.warning("音频硬件配置变更（设备切换），重启录音引擎", category: .audio)

        // Check if selected device is still available
        if let uid = selectedDeviceUID,
           AudioDeviceManager.deviceID(forUID: uid) == nil {
            AppLogger.warning("已选择的音频设备不再可用，回退到默认设备", category: .audio)
            selectedDeviceUID = nil
        }

        // 先清理回调，避免 tap 继续喂入数据
        onAudioData = nil
        onAudioLevel = nil

        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let (stillRecording, sampleRate) = self.withStateLock {
                (self.isRecording, Int(self.targetSampleRate))
            }
            guard stillRecording else {
                self.withStateLock { self.isRestartingEngine = false }
                return
            }

            do {
                try self.setupAndStartEngine(sampleRate: sampleRate)
                self.withStateLock { self.isRestartingEngine = false }
                self.startAudioWatchdog(sampleRate: sampleRate)
                let actualRate = self.withStateLock { self.recordingSampleRate }
                AppLogger.info(
                    "录音引擎重启成功，硬件采样率: \(Int(actualRate))Hz",
                    category: .audio
                )
            } catch {
                self.withStateLock { self.isRestartingEngine = false }
                AppLogger.error("录音引擎重启失败: \(error.localizedDescription)", category: .audio)
                self.withStateLock { self.isRecording = false }
                DispatchQueue.main.async {
                    self.onRecordingError?(error)
                }
            }
        }
    }

    // MARK: - 看门狗：检测无音频数据时自动重启引擎

    private func startAudioWatchdog(sampleRate: Int) {
        cancelAudioWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now() + .milliseconds(1500))
        timer.setEventHandler { [weak self] in
            self?.checkAndRetryAudioEngine(sampleRate: sampleRate)
        }
        withStateLock { audioDataWatchdogTimer = timer }
        timer.resume()
    }

    private func cancelAudioWatchdog() {
        let old: DispatchSourceTimer? = withStateLock {
            let t = audioDataWatchdogTimer
            audioDataWatchdogTimer = nil
            return t
        }
        old?.cancel()
    }

    /// 看门狗触发：如果 1.5s 内没有采集到任何音频样点，带退避地重启引擎
    private func checkAndRetryAudioEngine(sampleRate: Int) {
        let shouldProceed: Bool = withStateLock {
            audioDataWatchdogTimer = nil
            guard isRecording, audioData.isEmpty, !isRestartingEngine else { return false }
            isRestartingEngine = true
            return true
        }
        guard shouldProceed else { return }

        let retryCount = withStateLock { engineRetryCount }
        guard retryCount < maxEngineRetries else {
            AppLogger.error("录音引擎无法采集音频，已达最大重试次数 (\(maxEngineRetries))", category: .audio)
            withStateLock { isRestartingEngine = false }
            return
        }

        let newCount = retryCount + 1
        withStateLock { engineRetryCount = newCount }
        let waitMs = newCount * 500  // 500 / 1000 / 1500 / 2000 ms

        AppLogger.warning(
            "未收到音频数据，重启引擎（第 \(newCount)/\(maxEngineRetries) 次，等待 \(waitMs)ms）",
            category: .audio
        )

        // 先清理回调，避免 tap 继续喂入数据
        onAudioData = nil
        onAudioLevel = nil

        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + .milliseconds(waitMs)) { [weak self] in
            guard let self = self else { return }
            let stillRecording = self.withStateLock { self.isRecording }
            guard stillRecording else {
                self.withStateLock { self.isRestartingEngine = false }
                return
            }
            do {
                try self.setupAndStartEngine(sampleRate: sampleRate)
                self.withStateLock { self.isRestartingEngine = false }
                self.startAudioWatchdog(sampleRate: sampleRate)
                let actualRate = self.withStateLock { self.recordingSampleRate }
                AppLogger.info(
                    "引擎重启完成（尝试 \(newCount)），硬件采样率: \(Int(actualRate))Hz",
                    category: .audio
                )
            } catch {
                self.withStateLock { self.isRestartingEngine = false }
                AppLogger.error("引擎重启失败（尝试 \(newCount)）: \(error.localizedDescription)", category: .audio)
            }
        }
    }

    func stopRecording() {
        let currentlyRecording = withStateLock { isRecording }
        guard currentlyRecording else {
            AppLogger.warning("未在录音中", category: .audio)
            return
        }

        cancelAudioWatchdog()
        withStateLock {
            engineRetryCount = 0
            isRestartingEngine = false
        }

        // 先清理回调，避免 tap 继续喂入数据
        onAudioData = nil
        onAudioLevel = nil

        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)

        let duration: TimeInterval = withStateLock {
            if let startTime = recordingStartTime {
                return Date().timeIntervalSince(startTime)
            }
            return 0
        }

        let (rawAudio, sourceSampleRate, targetRate): ([Float], Double, Double) = withStateLock {
            (audioData, recordingSampleRate, targetSampleRate)
        }
        let processedAudio: [Float]
        let processedSampleRate: Double

        if abs(sourceSampleRate - targetRate) > 0.5 {
            processedAudio = resampleLinear(rawAudio, from: sourceSampleRate, to: targetRate)
            processedSampleRate = targetRate
            AppLogger.info(
                "音频重采样完成: \(Int(sourceSampleRate))Hz -> \(Int(targetRate))Hz，样点 \(rawAudio.count) -> \(processedAudio.count)",
                category: .audio
            )
        } else {
            processedAudio = rawAudio
            processedSampleRate = sourceSampleRate
        }

        withStateLock {
            lastRecordedAudio = processedAudio
            lastRecordingDuration = duration
            lastRecordingSampleRate = processedSampleRate
            audioData = []
            isRecording = false
        }

        audioEngine = nil
        inputNode = nil

        AppLogger.info(
            "停止录音，时长: \(String(format: "%.2f", duration))秒，音频长度: \(processedAudio.count) 样点，采样率: \(Int(processedSampleRate))Hz",
            category: .audio
        )

        DispatchQueue.main.async {
            self.onRecordingComplete?(processedAudio, duration)
        }
    }

    func cancelRecording() {
        let currentlyRecording = withStateLock { isRecording }
        guard currentlyRecording else { return }

        cancelAudioWatchdog()
        withStateLock {
            engineRetryCount = 0
            isRestartingEngine = false
        }

        // 先清理回调，避免 tap 继续喂入数据
        onAudioData = nil
        onAudioLevel = nil

        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)

        withStateLock {
            audioData = []
            lastRecordedAudio = []
            lastRecordingDuration = 0
            lastRecordingSampleRate = targetSampleRate
            isRecording = false
        }

        audioEngine = nil
        inputNode = nil

        AppLogger.info("取消录音", category: .audio)
    }

    func getCurrentAudioData() -> [Float] {
        withStateLock {
            isRecording ? audioData : lastRecordedAudio
        }
    }

    func getCurrentDuration() -> TimeInterval {
        withStateLock {
            if isRecording, let startTime = recordingStartTime {
                return Date().timeIntervalSince(startTime)
            }
            return lastRecordingDuration
        }
    }

    func getCurrentSampleRate() -> Int {
        withStateLock {
            if isRecording {
                return Int(recordingSampleRate.rounded())
            }
            return Int(lastRecordingSampleRate.rounded())
        }
    }

    private func resampleLinear(_ input: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !input.isEmpty else { return [] }
        guard sourceRate > 0, targetRate > 0 else { return input }
        guard abs(sourceRate - targetRate) > 0.5 else { return input }

        let ratio = targetRate / sourceRate
        let outputCount = max(1, Int((Double(input.count) * ratio).rounded()))

        var output = [Float](repeating: 0, count: outputCount)
        let inverseRatio = sourceRate / targetRate

        for i in 0..<outputCount {
            let sourceIndex = Double(i) * inverseRatio
            let left = Int(sourceIndex)
            let right = min(left + 1, input.count - 1)
            let fraction = Float(sourceIndex - Double(left))

            let leftValue = input[left]
            let rightValue = input[right]
            output[i] = leftValue + (rightValue - leftValue) * fraction
        }

        return output
    }
}

// MARK: - 录音错误

enum RecordingError: LocalizedError {
    case microphonePermissionDenied
    case engineCreationFailed
    case inputNodeUnavailable
    case invalidAudioFormat
    case recordingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝，请在系统设置中允许访问麦克风"
        case .engineCreationFailed:
            return "无法创建音频引擎"
        case .inputNodeUnavailable:
            return "无法获取音频输入节点"
        case .invalidAudioFormat:
            return "无效的音频格式"
        case .recordingFailed(let error):
            return "录音失败: \(error.localizedDescription)"
        }
    }
}
