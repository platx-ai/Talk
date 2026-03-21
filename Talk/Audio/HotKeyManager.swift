//
//  HotKeyManager.swift
//  Talk
//
//  全局热键管理器
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

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
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

    // MARK: - 初始化

    private init() {
        loadHotKeyConfiguration()
    }

    // MARK: - 热键注册

    func registerHotKey(_ hotKey: HotKeyConfiguration) {
        unregisterHotKey()

        currentHotKey = hotKey

        if isModifierOnlyHotKey(hotKey) {
            installModifierOnlyMonitors()
            isRegistered = true
            AppLogger.info("热键注册成功（修饰键监听模式）", category: .hotkey)
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4C544B54),  // "LTKT"
            id: 1
        )

        AppLogger.info("注册热键 - 修饰键: 0x\(String(hotKey.modifiers, radix: 16)), 键码: \(hotKey.keyCode)", category: .hotkey)

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            isRegistered = true
            AppLogger.info("热键注册成功", category: .hotkey)
            installEventHandler()
        } else {
            AppLogger.error("热键注册失败，错误码: \(status)", category: .hotkey)
        }
    }

    func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        removeModifierOnlyMonitors()

        isKeyPressed = false

        isRegistered = false
        AppLogger.info("热键已注销", category: .hotkey)
    }

    // MARK: - 事件处理

    private func installEventHandler() {
        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyReleased)
            )
        ]

        AppLogger.info("安装热键事件处理器", category: .hotkey)

        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else {
                return noErr
            }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKeyEvent(theEvent)

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            eventTypes.count,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        AppLogger.info("事件处理器已安装", category: .hotkey)
    }

    private func handleHotKeyEvent(_ event: EventRef?) {
        guard let event = event else { return }

        let eventKind = GetEventKind(event)
        let isKeyDown = eventKind == OSType(kEventHotKeyPressed)

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            AppLogger.debug("热键事件 - 类型: \(isKeyDown ? "按下" : "释放")", category: .hotkey)

            if self.triggerMode == .pushToTalk {
                if isKeyDown && !self.isKeyPressed {
                    self.isKeyPressed = true
                    AppLogger.info("热键按下 → 开始录音", category: .hotkey)
                    self.onHotKeyPressed?()
                } else if !isKeyDown && self.isKeyPressed {
                    self.isKeyPressed = false
                    AppLogger.info("热键释放 → 停止录音", category: .hotkey)
                    self.onHotKeyReleased?()
                }
            } else {
                if isKeyDown && !self.isKeyPressed {
                    self.isKeyPressed = true
                    AppLogger.info("热键按下 → 切换录音状态", category: .hotkey)
                    self.onHotKeyPressed?()
                } else if !isKeyDown && self.isKeyPressed {
                    self.isKeyPressed = false
                    AppLogger.info("热键释放 → 重置状态", category: .hotkey)
                }
            }
        }
    }

    private func isModifierOnlyHotKey(_ hotKey: HotKeyConfiguration) -> Bool {
        hotKey.modifiers == 0 && modifierFlag(for: hotKey.keyCode) != nil
    }

    private func modifierFlag(for keyCode: UInt32) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case UInt32(kVK_Control): return .control
        case UInt32(kVK_Option): return .option
        case UInt32(kVK_Command): return .command
        case UInt32(kVK_Shift): return .shift
        default: return nil
        }
    }

    private func installModifierOnlyMonitors() {
        removeModifierOnlyMonitors()

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleModifierFlagsChanged(event)
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleModifierFlagsChanged(event)
            }
            return event
        }

        AppLogger.info("已安装修饰键监听器", category: .hotkey)
    }

    private func removeModifierOnlyMonitors() {
        if let globalFlagsMonitor = globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }

        if let localFlagsMonitor = localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
    }

    private func handleModifierFlagsChanged(_ event: NSEvent) {
        guard let flag = modifierFlag(for: currentHotKey.keyCode) else { return }

        let isDown = event.modifierFlags.contains(flag)
        AppLogger.debug("修饰键事件 - 类型: \(isDown ? "按下" : "释放")", category: .hotkey)

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
                AppLogger.info("热键释放 → 重置状态", category: .hotkey)
            }
        }
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
