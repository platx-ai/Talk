//
//  AppSettings.swift
//  Talk
//
//  应用设置模型
//

import Foundation

// MARK: - HotKeyCombo

/// 快捷键组合（Codable / Equatable）
struct HotKeyCombo: Codable, Equatable {
    var carbonModifiers: UInt32
    var carbonKeyCode: UInt32
    var isModifierOnly: Bool

    /// Control 键单独按下
    static let defaultCombo = HotKeyCombo(carbonModifiers: 0, carbonKeyCode: 59, isModifierOnly: true)

    // MARK: - 显示字符串

    var displayString: String {
        var parts: [String] = []

        // 修饰键符号
        if carbonModifiers & 0x1000 != 0 { parts.append("⌃") }
        if carbonModifiers & 0x0800 != 0 { parts.append("⌥") }
        if carbonModifiers & 0x0200 != 0 { parts.append("⇧") }
        if carbonModifiers & 0x0100 != 0 { parts.append("⌘") }

        if isModifierOnly {
            // 主键本身也是修饰键
            let modName = Self.modifierKeyName(for: carbonKeyCode)
            let modSymbol = Self.modifierKeySymbol(for: carbonKeyCode)
            // 如果修饰键符号还没包含，加上它
            if !parts.contains(modSymbol) {
                parts.insert(modSymbol, at: 0)
            }
            return parts.joined() + " " + modName
        } else {
            let keyName = Self.regularKeyName(for: carbonKeyCode)
            return parts.joined() + " " + keyName
        }
    }

    // MARK: - Legacy migration

    /// Convert old string format (e.g. "Control", "Option + Control", "Command + Space") to HotKeyCombo
    static func fromLegacyString(_ legacy: String) -> HotKeyCombo {
        let tokens = legacy.split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        func modifierMask(for token: String) -> UInt32 {
            switch token {
            case "command", "cmd": return 0x0100
            case "shift": return 0x0200
            case "option", "alt": return 0x0800
            case "control", "ctrl": return 0x1000
            default: return 0
            }
        }

        func keyCode(for token: String) -> UInt32? {
            switch token {
            case "space": return 49
            default: return nil
            }
        }

        // Find the primary (non-modifier) key
        let nonModifier = tokens.first { modifierMask(for: $0) == 0 && keyCode(for: $0) != nil }

        if let primary = nonModifier, let code = keyCode(for: primary) {
            // Regular key combo (e.g. "Command + Space")
            var mods: UInt32 = 0
            for t in tokens where modifierMask(for: t) != 0 {
                mods |= modifierMask(for: t)
            }
            return HotKeyCombo(carbonModifiers: mods, carbonKeyCode: code, isModifierOnly: false)
        } else {
            // Modifier-only combo: last modifier token is the primary key, rest are additional modifiers
            let modTokens = tokens.filter { modifierMask(for: $0) != 0 }
            guard let primaryToken = modTokens.last else {
                return .defaultCombo
            }
            let primaryKeyCode: UInt32
            switch primaryToken {
            case "control", "ctrl": primaryKeyCode = 59
            case "option", "alt": primaryKeyCode = 58
            case "shift": primaryKeyCode = 56
            case "command", "cmd": primaryKeyCode = 55
            default: return .defaultCombo
            }
            var mods: UInt32 = 0
            for t in modTokens.dropLast() {
                mods |= modifierMask(for: t)
            }
            return HotKeyCombo(carbonModifiers: mods, carbonKeyCode: primaryKeyCode, isModifierOnly: true)
        }
    }

    // MARK: - Key name helpers

    private static func modifierKeySymbol(for keyCode: UInt32) -> String {
        switch keyCode {
        case 59: return "⌃"  // Control
        case 58: return "⌥"  // Option
        case 56: return "⇧"  // Shift
        case 55: return "⌘"  // Command
        default: return ""
        }
    }

    private static func modifierKeyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 59: return "Control"
        case 58: return "Option"
        case 56: return "Shift"
        case 55: return "Command"
        default: return "Key(\(keyCode))"
        }
    }

    private static func regularKeyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            // Letter keys
            let letterMap: [UInt32: String] = [
                0:"A",11:"B",8:"C",2:"D",14:"E",3:"F",5:"G",4:"H",34:"I",
                38:"J",40:"K",37:"L",46:"M",45:"N",31:"O",35:"P",12:"Q",
                15:"R",1:"S",17:"T",32:"U",9:"V",13:"W",7:"X",16:"Y",6:"Z"
            ]
            return letterMap[keyCode] ?? "Key(\(keyCode))"
        }
    }
}

/// 应用设置（全局单例，修改后自动持久化）
@Observable
final class AppSettings {
    // MARK: - 单例

    static let shared: AppSettings = {
        let settings = AppSettings()
        settings.loadFromDefaults()
        return settings
    }()

    /// 标记是否正在从 UserDefaults 加载（加载期间不触发 save）
    private var isLoading = false

    /// 每次属性变化后自动保存到 UserDefaults
    private func autoSave() {
        guard !isLoading else { return }
        save()
    }

    // MARK: - 录音设置

    enum RecordingTriggerMode: String, Codable, CaseIterable {
        case pushToTalk = "push_to_talk"
        case toggle = "toggle"
    }

    var recordingTriggerMode: RecordingTriggerMode = .pushToTalk { didSet { autoSave() } }
    var recordingHotkey: HotKeyCombo = .defaultCombo { didSet { autoSave() } }
    var recordingMaxDuration: Int = 0 { didSet { autoSave() } }
    var silenceTimeout: Int = 0 { didSet { autoSave() } }
    var sampleRate: Int = 16000 { didSet { autoSave() } }

    // MARK: - 模型下载源

    enum ModelSource: String, Codable, CaseIterable {
        case huggingface = "huggingface"
        case modelscope = "modelscope"
    }

    var modelSource: ModelSource = .huggingface { didSet { autoSave() } }

    // MARK: - ASR 引擎选择

    enum ASREngine: String, Codable, CaseIterable {
        case mlxLocal = "mlx_local"
        case appleSpeech = "apple_speech"
        case gemma4 = "gemma4"
    }

    var asrEngine: ASREngine = .mlxLocal { didSet { autoSave() } }

    // MARK: - ASR 设置（MLX 本地模型）

    var asrModelId: String = "mlx-community/Qwen3-ASR-0.6B-4bit"

    enum ASRLanguage: String, Codable, CaseIterable {
        case auto = "auto"
        case chinese = "zh"
        case english = "en"
        case mixed = "mixed"
    }

    var asrLanguage: ASRLanguage = .auto { didSet { autoSave() } }
    var enableStreamingInference: Bool = false { didSet { autoSave() } }
    var showRealtimeRecognition: Bool = false { didSet { autoSave() } }
    var enableVADFilter: Bool = true { didSet { autoSave() } }
    var vadThreshold: Double = 0.5 { didSet { autoSave() } }
    var vadPaddingChunks: Int = 1 { didSet { autoSave() } }
    var vadMinSpeechChunks: Int = 2 { didSet { autoSave() } }

    // MARK: - ASR 设置（Apple Speech）

    enum AppleSpeechLocale: String, Codable, CaseIterable {
        case system = "system"
        case zhCN = "zh-CN"
        case zhTW = "zh-TW"
        case enUS = "en-US"
        case enGB = "en-GB"
        case ja = "ja-JP"
        case ko = "ko-KR"
    }

    var appleSpeechLocale: AppleSpeechLocale = .zhCN { didSet { autoSave() } }
    var appleSpeechOnDevice: Bool = false { didSet { autoSave() } }
    var appleSpeechShowRealtime: Bool = true { didSet { autoSave() } }

    // MARK: - Gemma4 设置

    enum Gemma4ModelSize: String, Codable, CaseIterable {
        case e2b = "2B"
        case e4b = "4B"
    }

    var gemma4ModelSize: Gemma4ModelSize = .e4b { didSet { autoSave() } }
    var gemma4EnableT2S: Bool = true { didSet { autoSave() } }  // 繁→简转换

    var gemma4ModelId: String {
        switch gemma4ModelSize {
        case .e2b: return "mlx-community/gemma-4-e2b-it-4bit"
        case .e4b: return "mlx-community/gemma-4-e4b-it-4bit"
        }
    }

    // MARK: - LLM 引擎选择

    enum LLMEngine: String, Codable, CaseIterable {
        case qwen3 = "qwen3"
        case gemma4 = "gemma4"
    }

    var llmEngine: LLMEngine = .qwen3 { didSet { autoSave() } }

    /// ASR+LLM 都是 Gemma4 → 一段式模式（自动检测，无需开关）
    var isOnePassMode: Bool {
        asrEngine == .gemma4 && llmEngine == .gemma4
    }

    // MARK: - LLM 设置

    var llmModelId: String = "mlx-community/Qwen3.5-4B-MLX-4bit" { didSet { autoSave() } }

    enum PolishIntensity: String, Codable, CaseIterable {
        case light = "light"
        case medium = "medium"
        case strong = "strong"
    }

    var polishIntensity: PolishIntensity = .medium { didSet { autoSave() } }
    var conversationHistoryRounds: Int = 5 { didSet { autoSave() } }
    var enableConversationHistory: Bool = true { didSet { autoSave() } }
    var customSystemPrompt: String = "" { didSet { autoSave() } }  // empty means use default
    var customEditPrompt: String = "" { didSet { autoSave() } }    // empty means use default edit prompt

    /// Per-app prompt profiles: [Bundle ID → custom prompt]
    var appPrompts: [String: String] = [:] { didSet { autoSave() } }

    // MARK: - 选中修正

    enum SelectionCaptureMethod: String, Codable, CaseIterable {
        case accessibility = "accessibility"  // AXUIElement API, low intrusion
        case clipboard = "clipboard"          // Cmd+C, broader compatibility
    }

    var selectionCaptureMethod: SelectionCaptureMethod = .accessibility { didSet { autoSave() } }

    // MARK: - 输出设置

    enum OutputMethod: String, Codable, CaseIterable {
        case autoPaste = "auto_paste"
        case clipboardOnly = "clipboard_only"
        case previewWindow = "preview_window"
    }

    var outputMethod: OutputMethod = .autoPaste { didSet { autoSave() } }

    enum OutputDelay: String, Codable, CaseIterable {
        case immediate = "immediate"
        case afterPolish = "after_polish"
        case custom = "custom"
    }

    var outputDelay: OutputDelay = .afterPolish { didSet { autoSave() } }
    var customOutputDelay: Int = 1 { didSet { autoSave() } }
    var showPreviewBeforeOutput: Bool = false { didSet { autoSave() } }

    // MARK: - 高级功能

    var enableVoiceCommands: Bool = true { didSet { autoSave() } }
    var enablePersonalVocabulary: Bool = true { didSet { autoSave() } }
    var enableAutoHotwordLearning: Bool = true { didSet { autoSave() } }
    var enableAudioHistory: Bool = true { didSet { autoSave() } }

    enum AppLanguage: String, Codable, CaseIterable {
        case system = "system"
        case chinese = "zh-CN"
        case english = "en-US"
    }

    var appLanguage: AppLanguage = .system { didSet { autoSave() } }

    enum PerformanceMode: String, Codable, CaseIterable {
        case speed = "speed"
        case accuracy = "accuracy"
        case balanced = "balanced"
    }

    var performanceMode: PerformanceMode = .speed { didSet { autoSave() } }

    enum MemoryMode: String, Codable, CaseIterable {
        case low = "low"
        case normal = "normal"
        case auto = "auto"
    }

    var memoryMode: MemoryMode = .normal { didSet { autoSave() } }

    // MARK: - 空闲卸载

    var idleUnloadMinutes: Int = 10 { didSet { autoSave() } }  // 0 = disabled

    // MARK: - 启动与退出

    var launchAtLogin: Bool = false { didSet { autoSave() } }
    var quitBehavior: Bool = true { didSet { autoSave() } }

    // MARK: - 日志

    var enableDetailedLogging: Bool = true { didSet { autoSave() } }

    // MARK: - 音频设备

    var selectedAudioDeviceUID: String? = nil { didSet { autoSave() } }

    // MARK: - 引导流程

    var hasCompletedOnboarding: Bool = false { didSet { autoSave() } }

    enum LogLevel: String, Codable, CaseIterable {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
    }

    var logLevel: LogLevel = .debug { didSet { autoSave() } }

    init() {}

    /// 检测本地已缓存的最佳 LLM 模型
    static func detectBestAvailableLLM() -> String {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")

        // 优先用已有的（兼容老用户），没有再推荐新的
        // NOTE: Qwen3.5-4B-OptiQ-4bit 在 mlx-swift 0.31.3+ 上 weight loading
        //       会失败（mlx-swift#363 vs OptiQ 蒸馏权重结构的交互）——所以不
        //       能作为默认。标准 MLX-4bit 打包是最稳的。
        let candidates = [
            "mlx-community/Qwen3-4B-Instruct-2507-4bit",   // 老用户最可能有
            "mlx-community/Qwen3.5-4B-MLX-4bit",           // 推荐：标准 MLX 打包
            "mlx-community/Qwen3.5-2B-4bit",               // 轻量
            "mlx-community/Qwen3.5-4B-OptiQ-4bit",         // 备选：OptiQ 蒸馏（有兼容性问题）
        ]

        for modelId in candidates {
            let dirName = "models--" + modelId.replacingOccurrences(of: "/", with: "--")
            let modelDir = cacheDir.appendingPathComponent(dirName)
            if FileManager.default.fileExists(atPath: modelDir.path) {
                return modelId
            }
        }

        // 没有缓存的模型，用推荐默认
        return "mlx-community/Qwen3.5-4B-MLX-4bit"
    }
}

// MARK: - 加载和保存

extension AppSettings {
    private static let userDefaultsKey = "AppSettings"

    /// 返回全局单例（已从 UserDefaults 加载）
    static func load() -> AppSettings {
        return shared
    }

    /// 从 UserDefaults 加载所有字段（仅在初始化时调用）
    func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }

        let defaults = UserDefaults.standard

        func boolValue(_ key: String, default defaultValue: Bool) -> Bool {
            guard defaults.object(forKey: key) != nil else { return defaultValue }
            return defaults.bool(forKey: key)
        }

        if let mode = defaults.string(forKey: "recordingTriggerMode"),
           let triggerMode = RecordingTriggerMode(rawValue: mode) {
            recordingTriggerMode = triggerMode
        }
        // Load recordingHotkey: try new JSON format first, then fall back to legacy string
        if let hotkeyData = defaults.data(forKey: "recordingHotkey"),
           let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: hotkeyData) {
            self.recordingHotkey = combo
        } else if let legacyString = defaults.string(forKey: "recordingHotkey") {
            self.recordingHotkey = HotKeyCombo.fromLegacyString(legacyString)
        }
        self.recordingMaxDuration = defaults.integer(forKey: "recordingMaxDuration")
        self.silenceTimeout = defaults.integer(forKey: "silenceTimeout")
        self.sampleRate = defaults.integer(forKey: "sampleRate") != 0 ? defaults.integer(forKey: "sampleRate") : 16000
        self.selectedAudioDeviceUID = defaults.string(forKey: "selectedAudioDeviceUID")

        if let source = defaults.string(forKey: "modelSource"),
           let modelSource = ModelSource(rawValue: source) {
            self.modelSource = modelSource
        }

        if let engine = defaults.string(forKey: "asrEngine"),
           let asrEngine = ASREngine(rawValue: engine) {
            self.asrEngine = asrEngine
        }
        self.asrModelId = defaults.string(forKey: "asrModelId") ?? "mlx-community/Qwen3-ASR-0.6B-4bit"
        if let lang = defaults.string(forKey: "asrLanguage"),
           let language = ASRLanguage(rawValue: lang) {
            self.asrLanguage = language
        }
        if defaults.object(forKey: "enableStreamingInference") != nil {
            self.enableStreamingInference = boolValue("enableStreamingInference", default: false)
        } else {
            // 兼容旧版本：未配置新开关时沿用原"实时显示识别结果"的值
            self.enableStreamingInference = boolValue("showRealtimeRecognition", default: false)
        }
        self.showRealtimeRecognition = boolValue("showRealtimeRecognition", default: false)
        self.enableVADFilter = boolValue("enableVADFilter", default: true)
        if defaults.object(forKey: "vadThreshold") != nil {
            self.vadThreshold = defaults.double(forKey: "vadThreshold")
        }
        self.vadPaddingChunks = defaults.integer(forKey: "vadPaddingChunks") != 0 ? defaults.integer(forKey: "vadPaddingChunks") : 1
        self.vadMinSpeechChunks = defaults.integer(forKey: "vadMinSpeechChunks") != 0 ? defaults.integer(forKey: "vadMinSpeechChunks") : 2

        // Apple Speech settings
        if let locale = defaults.string(forKey: "appleSpeechLocale"),
           let speechLocale = AppleSpeechLocale(rawValue: locale) {
            self.appleSpeechLocale = speechLocale
        }
        self.appleSpeechOnDevice = boolValue("appleSpeechOnDevice", default: false)
        self.appleSpeechShowRealtime = boolValue("appleSpeechShowRealtime", default: true)

        // Gemma4 settings
        if let size = defaults.string(forKey: "gemma4ModelSize"),
           let modelSize = Gemma4ModelSize(rawValue: size) {
            self.gemma4ModelSize = modelSize
        }
        self.gemma4EnableT2S = boolValue("gemma4EnableT2S", default: true)

        // LLM engine
        if let engine = defaults.string(forKey: "llmEngine"),
           let llmEngine = LLMEngine(rawValue: engine) {
            self.llmEngine = llmEngine
        }

        // 智能默认：如果用户没有手动设置过 LLM 模型，检测本地已有哪个，用已有的
        if let savedModel = defaults.string(forKey: "llmModelId") {
            self.llmModelId = savedModel
        } else {
            self.llmModelId = Self.detectBestAvailableLLM()
        }
        if let intensity = defaults.string(forKey: "polishIntensity"),
           let polishIntensity = PolishIntensity(rawValue: intensity) {
            self.polishIntensity = polishIntensity
        }
        self.conversationHistoryRounds = defaults.integer(forKey: "conversationHistoryRounds") != 0 ? defaults.integer(forKey: "conversationHistoryRounds") : 5
        self.enableConversationHistory = boolValue("enableConversationHistory", default: true)
        self.customSystemPrompt = defaults.string(forKey: "customSystemPrompt") ?? ""
        self.customEditPrompt = defaults.string(forKey: "customEditPrompt") ?? ""
        if let data = defaults.data(forKey: "appPrompts"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.appPrompts = decoded
        }
        if let method = defaults.string(forKey: "selectionCaptureMethod"),
           let captureMethod = SelectionCaptureMethod(rawValue: method) {
            self.selectionCaptureMethod = captureMethod
        }

        if let method = defaults.string(forKey: "outputMethod"),
           let outputMethod = OutputMethod(rawValue: method) {
            self.outputMethod = outputMethod
        }
        if let delay = defaults.string(forKey: "outputDelay"),
           let outputDelay = OutputDelay(rawValue: delay) {
            self.outputDelay = outputDelay
        }
        self.customOutputDelay = defaults.integer(forKey: "customOutputDelay")
        self.showPreviewBeforeOutput = boolValue("showPreviewBeforeOutput", default: false)

        self.enableVoiceCommands = boolValue("enableVoiceCommands", default: true)
        self.enablePersonalVocabulary = boolValue("enablePersonalVocabulary", default: true)
        self.enableAutoHotwordLearning = boolValue("enableAutoHotwordLearning", default: true)
        self.enableAudioHistory = boolValue("enableAudioHistory", default: true)

        if let lang = defaults.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: lang) {
            self.appLanguage = language
        }

        if let mode = defaults.string(forKey: "performanceMode"),
           let perfMode = PerformanceMode(rawValue: mode) {
            self.performanceMode = perfMode
        }
        if let mode = defaults.string(forKey: "memoryMode"),
           let memMode = MemoryMode(rawValue: mode) {
            self.memoryMode = memMode
        }

        // 0 = disabled, 需要区分"未设置"和"用户设为0"
        if defaults.object(forKey: "idleUnloadMinutes") != nil {
            self.idleUnloadMinutes = defaults.integer(forKey: "idleUnloadMinutes")
        }

        self.launchAtLogin = boolValue("launchAtLogin", default: false)
        self.quitBehavior = boolValue("quitBehavior", default: true)
        self.enableDetailedLogging = boolValue("enableDetailedLogging", default: true)
        if let level = defaults.string(forKey: "logLevel"),
           let logLevel = LogLevel(rawValue: level) {
            self.logLevel = logLevel
        }

        self.hasCompletedOnboarding = boolValue("hasCompletedOnboarding", default: false)
    }

    func save() {
        let defaults = UserDefaults.standard

        defaults.set(recordingTriggerMode.rawValue, forKey: "recordingTriggerMode")
        if let hotkeyData = try? JSONEncoder().encode(recordingHotkey) {
            defaults.set(hotkeyData, forKey: "recordingHotkey")
        }
        defaults.set(recordingMaxDuration, forKey: "recordingMaxDuration")
        defaults.set(silenceTimeout, forKey: "silenceTimeout")
        defaults.set(sampleRate, forKey: "sampleRate")
        defaults.set(selectedAudioDeviceUID, forKey: "selectedAudioDeviceUID")

        defaults.set(modelSource.rawValue, forKey: "modelSource")

        defaults.set(asrEngine.rawValue, forKey: "asrEngine")
        defaults.set(asrModelId, forKey: "asrModelId")
        defaults.set(asrLanguage.rawValue, forKey: "asrLanguage")
        defaults.set(enableStreamingInference, forKey: "enableStreamingInference")
        defaults.set(showRealtimeRecognition, forKey: "showRealtimeRecognition")
        defaults.set(enableVADFilter, forKey: "enableVADFilter")
        defaults.set(vadThreshold, forKey: "vadThreshold")
        defaults.set(vadPaddingChunks, forKey: "vadPaddingChunks")
        defaults.set(vadMinSpeechChunks, forKey: "vadMinSpeechChunks")

        defaults.set(appleSpeechLocale.rawValue, forKey: "appleSpeechLocale")
        defaults.set(appleSpeechOnDevice, forKey: "appleSpeechOnDevice")
        defaults.set(appleSpeechShowRealtime, forKey: "appleSpeechShowRealtime")

        defaults.set(gemma4ModelSize.rawValue, forKey: "gemma4ModelSize")
        defaults.set(gemma4EnableT2S, forKey: "gemma4EnableT2S")

        defaults.set(llmEngine.rawValue, forKey: "llmEngine")
        defaults.set(llmModelId, forKey: "llmModelId")
        defaults.set(polishIntensity.rawValue, forKey: "polishIntensity")
        defaults.set(conversationHistoryRounds, forKey: "conversationHistoryRounds")
        defaults.set(enableConversationHistory, forKey: "enableConversationHistory")
        defaults.set(customSystemPrompt, forKey: "customSystemPrompt")
        defaults.set(customEditPrompt, forKey: "customEditPrompt")
        if let data = try? JSONEncoder().encode(appPrompts) {
            defaults.set(data, forKey: "appPrompts")
        }
        defaults.set(selectionCaptureMethod.rawValue, forKey: "selectionCaptureMethod")

        defaults.set(outputMethod.rawValue, forKey: "outputMethod")
        defaults.set(outputDelay.rawValue, forKey: "outputDelay")
        defaults.set(customOutputDelay, forKey: "customOutputDelay")
        defaults.set(showPreviewBeforeOutput, forKey: "showPreviewBeforeOutput")

        defaults.set(enableVoiceCommands, forKey: "enableVoiceCommands")
        defaults.set(enablePersonalVocabulary, forKey: "enablePersonalVocabulary")
        defaults.set(enableAutoHotwordLearning, forKey: "enableAutoHotwordLearning")
        defaults.set(enableAudioHistory, forKey: "enableAudioHistory")

        defaults.set(appLanguage.rawValue, forKey: "appLanguage")

        defaults.set(performanceMode.rawValue, forKey: "performanceMode")
        defaults.set(memoryMode.rawValue, forKey: "memoryMode")

        defaults.set(idleUnloadMinutes, forKey: "idleUnloadMinutes")

        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(quitBehavior, forKey: "quitBehavior")
        defaults.set(enableDetailedLogging, forKey: "enableDetailedLogging")
        defaults.set(logLevel.rawValue, forKey: "logLevel")

        defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
    }

    static func resetToDefaults() -> AppSettings {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        return AppSettings()
    }
}
