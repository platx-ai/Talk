//
//  TextInjector.swift
//  Talk
//
//  文本注入器 - 将文本注入到光标位置
//

import Foundation
import AppKit
import Carbon
import ApplicationServices

/// 文本注入器
@Observable
@MainActor
final class TextInjector {
    // MARK: - 单例

    @MainActor static let shared = TextInjector()

    enum InjectionMethod {
        case clipboard
        case accessibility
    }

    private(set) var method = InjectionMethod.clipboard

    private init() {}

    // MARK: - 辅助功能权限

    static func requestAccessibilityPermissionIfNeeded() {
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            AppLogger.warning(
                String(localized: "Accessibility 权限未授予！已弹出授权请求。"),
                category: .ui
            )
        } else {
            AppLogger.info("Accessibility 权限已授予", category: .ui)
        }
    }

    static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "需要辅助功能权限")
        alert.informativeText = String(localized: "自动粘贴功能需要系统辅助功能权限。\n\n请手动到：\n系统设置 → 隐私与安全性 → 辅助功能，点击 + 添加 Talk.app，然后重启本应用。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "打开辅助功能设置"))
        alert.addButton(withTitle: String(localized: "稍后"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    // MARK: - 文本注入

    func inject(_ text: String) async throws {
        AppLogger.info("开始注入文本: \(text)", category: .ui)

        switch method {
        case .clipboard:
            try await injectViaClipboard(text)
        case .accessibility:
            try await injectViaAccessibility(text)
        }
    }

    private func injectViaClipboard(_ text: String) async throws {
        let pasteboard = NSPasteboard.general

        // 备份当前剪贴板内容
        let backup = backupPasteboard(pasteboard)

        // 检测并临时切换输入法（CJK 输入法可能拦截 Cmd+V）
        let savedInputSource = switchToASCIIIfCJK()

        // 写入要注入的文本
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try await Task.sleep(for: .milliseconds(100))

        simulatePaste()

        // 等粘贴完成后恢复剪贴板和输入法
        try await Task.sleep(for: .milliseconds(300))
        restorePasteboard(pasteboard, from: backup)

        if let saved = savedInputSource {
            restoreInputSource(saved)
        }
    }

    // MARK: - 剪贴板备份/恢复

    private func backupPasteboard(_ pasteboard: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
        var backup: [(NSPasteboard.PasteboardType, Data)] = []
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    backup.append((type, data))
                }
            }
        }
        return backup
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, from backup: [(NSPasteboard.PasteboardType, Data)]) {
        guard !backup.isEmpty else { return }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in backup {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
        AppLogger.debug("剪贴板已恢复", category: .ui)
    }

    private func injectViaAccessibility(_ text: String) async throws {
        guard NSWorkspace.shared.frontmostApplication != nil else {
            throw InjectionError.noFocusedApp
        }

        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application id "com.apple.automation.eventmonitor"
            keystroke "\(escaped)"
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if error != nil {
            AppLogger.warning("AppleScript 执行失败，回退到剪贴板方法", category: .ui)
            try await injectViaClipboard(text)
        }
    }

    // MARK: - 输入法切换

    /// 检测当前输入法是否为 CJK，如果是则切换到 ASCII 输入源，返回原输入源以便恢复
    private func switchToASCIIIfCJK() -> TISInputSource? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        // 检查是否 CJK 输入法
        guard isCJKInputSource(current) else {
            return nil
        }

        // 获取系统最近使用的 ASCII 输入源（通常是 ABC 或 US 键盘）
        guard let asciiSource = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else {
            AppLogger.warning("找不到 ASCII 输入源，跳过输入法切换", category: .ui)
            return nil
        }

        let status = TISSelectInputSource(asciiSource)
        if status == noErr {
            AppLogger.debug("已临时切换到 ASCII 输入源", category: .ui)
            return current
        } else {
            AppLogger.warning("切换 ASCII 输入源失败: \(status)", category: .ui)
            return nil
        }
    }

    /// 恢复之前保存的输入法
    private func restoreInputSource(_ source: TISInputSource) {
        let status = TISSelectInputSource(source)
        if status == noErr {
            AppLogger.debug("已恢复原输入法", category: .ui)
        } else {
            AppLogger.warning("恢复输入法失败: \(status)", category: .ui)
        }
    }

    /// 判断输入源是否为 CJK 输入法
    private func isCJKInputSource(_ source: TISInputSource) -> Bool {
        guard let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return false
        }
        let langs = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue() as? [String] ?? []
        guard let firstLang = langs.first else { return false }
        return firstLang.hasPrefix("zh") || ["ja", "ko", "vi"].contains(firstLang)
    }

    // MARK: - 按键模拟

    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            AppLogger.error(
                String(localized: "Accessibility 权限未授予，CGEvent 无法发送到其他应用。"),
                category: .ui
            )
            DispatchQueue.main.async {
                TextInjector.showAccessibilityAlert()
            }
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cgSessionEventTap)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cgSessionEventTap)

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cgSessionEventTap)

        AppLogger.info("已模拟 Cmd+V", category: .ui)
    }
}

// MARK: - 注入错误

enum InjectionError: LocalizedError {
    case noFocusedApp
    case clipboardCopyFailed
    case accessibilityFailed
    case simulationFailed

    var errorDescription: String? {
        switch self {
        case .noFocusedApp:
            return String(localized: "没有找到焦点应用")
        case .clipboardCopyFailed:
            return String(localized: "复制到剪贴板失败")
        case .accessibilityFailed:
            return String(localized: "Accessibility API 调用失败")
        case .simulationFailed:
            return String(localized: "按键模拟失败")
        }
    }
}

typealias CGKeyCode = UInt16
