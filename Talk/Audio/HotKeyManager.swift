//
//  HotKeyManager.swift
//  Talk
//
//  全局热键管理器 — 使用 CGEventTap 监听全局按键
//

import Foundation
import Carbon
import AppKit

/// 热键管理器
@Observable
@MainActor
final class HotKeyManager {
    // MARK: - 单例

    @MainActor static let shared = HotKeyManager()

    // MARK: - 属性

    var onHotKeyPressed: (() -> Void)?
    var onHotKeyReleased: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private(set) var isRegistered = false

    // MARK: - 热键配置

    struct HotKeyConfiguration: Codable {
        var modifiers: UInt32
        var keyCode: UInt32

        init(modifiers: UInt32, keyCode: UInt32) {
            self.modifiers = modifiers
            self.keyCode = keyCode
        }
    }

    static let defaultHotKey = HotKeyConfiguration(
        modifiers: 0,
        keyCode: UInt32(kVK_Control)
    )

    private(set) var currentHotKey = defaultHotKey

    enum TriggerMode {
        case pushToTalk
        case toggle
    }

    private(set) var triggerMode: TriggerMode = .pushToTalk
    private var isKeyPressed = false

    // 缓存到 nonisolated 变量，供 CGEventTap 回调读取
    private nonisolated(unsafe) var _cachedKeyCode: UInt32 = defaultHotKey.keyCode
    private nonisolated(unsafe) var _cachedModifiers: UInt32 = defaultHotKey.modifiers
    private nonisolated(unsafe) var _cachedIsModifierOnly: Bool = true
    private nonisolated(unsafe) var _cachedWasPressed: Bool = false

    // MARK: - 初始化

    private init() {
        loadHotKeyConfiguration()
    }

    // MARK: - 热键注册

    func registerHotKey(_ hotKey: HotKeyConfiguration) {
        unregisterHotKey()

        currentHotKey = hotKey
        isKeyPressed = false

        // 如果 keyCode 本身是修饰键，则使用修饰键模式（无论是否有额外修饰键）
        let modOnly = modifierFlag(for: hotKey.keyCode) != nil
        _cachedKeyCode = hotKey.keyCode
        _cachedModifiers = hotKey.modifiers
        _cachedIsModifierOnly = modOnly
        _cachedWasPressed = false

        AppLogger.info("注册热键 - 修饰键: 0x\(String(hotKey.modifiers, radix: 16)), 键码: \(hotKey.keyCode), 修饰键模式: \(modOnly)", category: .hotkey)

        installCGEventTap()
    }

    func unregisterHotKey() {
        removeCGEventTap()
        isKeyPressed = false
        isRegistered = false
        AppLogger.info("热键已注销", category: .hotkey)
    }

    // MARK: - CGEventTap

    private func installCGEventTap() {
        // 只监听需要的事件类型
        let eventMask: CGEventMask
        if _cachedIsModifierOnly {
            // 修饰键模式：只需要 flagsChanged
            eventMask = 1 << CGEventType.flagsChanged.rawValue
        } else {
            // 普通按键模式：需要 keyDown/keyUp + flagsChanged（用于检查修饰键状态）
            eventMask =
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue)
        }

        // 使用 nonisolated 的全局 C 回调，通过 userInfo 传递 context
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.handleCGEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: context
        ) else {
            AppLogger.error("无法创建 CGEventTap — 请确认已授予辅助功能权限", category: .hotkey)
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        // CGEventTap 在独立后台线程的 RunLoop 上运行，不阻塞主线程
        let thread = Thread {
            let rl = CFRunLoopGetCurrent()!
            self.tapRunLoop = rl
            CFRunLoopAddSource(rl, self.runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "HotKeyManager.CGEventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread

        isRegistered = true
        AppLogger.info("热键注册成功（CGEventTap 后台线程模式）", category: .hotkey)
    }

    private func removeCGEventTap() {
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
            tapRunLoop = nil
        }
        tapThread = nil
        if let source = runLoopSource {
            runLoopSource = nil
            _ = source  // prevent premature release
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    // MARK: - 事件匹配

    private nonisolated func handleCGEvent(type: CGEventType, event: CGEvent) {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // 读取 nonisolated 缓存
        let cachedKeyCode = _cachedKeyCode
        let cachedModifiers = _cachedModifiers
        let cachedIsModifierOnly = _cachedIsModifierOnly

        if cachedIsModifierOnly {
            // 修饰键单独模式：只关心 flagsChanged 事件
            guard type == .flagsChanged else { return }

            let primaryFlag = nsCGEventFlag(for: cachedKeyCode)
            guard primaryFlag != [] else { return }

            let primaryDown = flags.contains(primaryFlag)

            let isDown: Bool
            if cachedModifiers != 0 {
                let currentMods = carbonModifiers(from: flags)
                isDown = primaryDown && (currentMods & cachedModifiers) == cachedModifiers
            } else {
                isDown = primaryDown
            }

            // 只在状态真正变化时才 dispatch 到主线程
            let wasPressed = _cachedWasPressed
            if isDown != wasPressed {
                _cachedWasPressed = isDown
                Task { @MainActor [weak self] in
                    self?.handleKeyState(isDown: isDown)
                }
            }
        } else {
            // 常规按键模式：匹配 keyCode + modifiers
            guard type == .keyDown || type == .keyUp else { return }
            guard keyCode == cachedKeyCode else { return }

            // 检查修饰键是否匹配
            let currentMods = carbonModifiers(from: flags)
            let mask: UInt32 = cmdKey | shiftKey | optionKey | controlKey
            guard (currentMods & mask) == (cachedModifiers & mask) else { return }

            let isDown = type == .keyDown

            Task { @MainActor [weak self] in
                self?.handleKeyState(isDown: isDown)
            }
        }
    }

    @MainActor
    private func handleKeyState(isDown: Bool) {
        if triggerMode == .pushToTalk {
            if isDown && !isKeyPressed {
                isKeyPressed = true
                AppLogger.info("热键按下 → 开始录音", category: .hotkey)
                onHotKeyPressed?()
            } else if !isDown && isKeyPressed {
                isKeyPressed = false
                AppLogger.info("热键释放 → 停止录音", category: .hotkey)
                onHotKeyReleased?()
            }
        } else {
            if isDown && !isKeyPressed {
                isKeyPressed = true
                AppLogger.info("热键按下 → 切换录音状态", category: .hotkey)
                onHotKeyPressed?()
            } else if !isDown && isKeyPressed {
                isKeyPressed = false
            }
        }
    }

    // MARK: - 辅助方法

    private nonisolated func modifierFlag(for keyCode: UInt32) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case UInt32(kVK_Control): return .control
        case UInt32(kVK_Option): return .option
        case UInt32(kVK_Command): return .command
        case UInt32(kVK_Shift): return .shift
        default: return nil
        }
    }

    private nonisolated func nsCGEventFlag(for keyCode: UInt32) -> CGEventFlags {
        switch keyCode {
        case UInt32(kVK_Control): return .maskControl
        case UInt32(kVK_Option): return .maskAlternate
        case UInt32(kVK_Command): return .maskCommand
        case UInt32(kVK_Shift): return .maskShift
        default: return []
        }
    }

    private nonisolated func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskControl)   { result |= controlKey }
        if flags.contains(.maskAlternate) { result |= optionKey }
        if flags.contains(.maskShift)     { result |= shiftKey }
        if flags.contains(.maskCommand)   { result |= cmdKey }
        return result
    }

    // MARK: - 触发模式

    func setTriggerMode(_ mode: TriggerMode) {
        triggerMode = mode
        AppLogger.info("设置热键触发模式: \(mode)", category: .hotkey)
    }

    // MARK: - 配置持久化

    private func loadHotKeyConfiguration() {
        if let data = UserDefaults.standard.data(forKey: "HotKeyConfiguration"),
           let config = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) {
            currentHotKey = config
        }
    }

    private func saveHotKeyConfiguration() {
        if let data = try? JSONEncoder().encode(currentHotKey) {
            UserDefaults.standard.set(data, forKey: "HotKeyConfiguration")
        }
    }
}

// MARK: - Carbon 修饰键常量

let cmdKey: UInt32 = 0x0100
let shiftKey: UInt32 = 0x0200
let optionKey: UInt32 = 0x0800
let controlKey: UInt32 = 0x1000

// MARK: - 虚拟键码

let kVK_Control: UInt32 = 59
let kVK_Shift: UInt32 = 56
let kVK_Option: UInt32 = 58
let kVK_Command: UInt32 = 55
let kVK_Space: UInt32 = 49
let kVK_F1: UInt32 = 122
