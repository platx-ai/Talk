//
//  PermissionManager.swift
//  Talk
//
//  系统权限检测与设置跳转
//

import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

enum AppPermission: CaseIterable, Identifiable {
    case microphone
    case inputMonitoring
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone:
            return String(localized: "麦克风权限")
        case .inputMonitoring:
            return String(localized: "输入监控")
        case .accessibility:
            return String(localized: "辅助功能权限")
        }
    }

    var detail: String {
        switch self {
        case .microphone:
            return String(localized: "Talk 需要录制你的语音，音频仅在本地处理。")
        case .inputMonitoring:
            return String(localized: "Talk 需要输入监控权限来监听全局快捷键。")
        case .accessibility:
            return String(localized: "Talk 需要辅助功能权限来将文字自动粘贴到当前应用。")
        }
    }

    var iconName: String {
        switch self {
        case .microphone:
            return "mic.circle"
        case .inputMonitoring:
            return "keyboard"
        case .accessibility:
            return "hand.raised.circle"
        }
    }

    var settingsURL: URL {
        let path: String
        switch self {
        case .microphone:
            path = "Privacy_Microphone"
        case .inputMonitoring:
            path = "Privacy_ListenEvent"
        case .accessibility:
            path = "Privacy_Accessibility"
        }

        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)")!
    }

    var restartHint: String? {
        guard self == .inputMonitoring else { return nil }
        return String(localized: "开启后请退出并重新打开 Talk，全局快捷键才会生效。")
    }
}

protocol PermissionStatusProviding {
    func isMicrophoneGranted() -> Bool
    func isInputMonitoringGranted() -> Bool
    func isAccessibilityGranted() -> Bool
}

struct LivePermissionStatusProvider: PermissionStatusProviding {
    func isMicrophoneGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func isInputMonitoringGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}

struct PermissionsSnapshot: Equatable {
    var microphoneGranted: Bool
    var inputMonitoringGranted: Bool
    var accessibilityGranted: Bool

    static let empty = PermissionsSnapshot(
        microphoneGranted: false,
        inputMonitoringGranted: false,
        accessibilityGranted: false
    )

    func isGranted(_ permission: AppPermission) -> Bool {
        switch permission {
        case .microphone:
            return microphoneGranted
        case .inputMonitoring:
            return inputMonitoringGranted
        case .accessibility:
            return accessibilityGranted
        }
    }

    var allRequiredGranted: Bool {
        microphoneGranted && inputMonitoringGranted && accessibilityGranted
    }
}

enum PermissionManager {
    static func snapshot(statusProvider: PermissionStatusProviding = LivePermissionStatusProvider()) -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphoneGranted: statusProvider.isMicrophoneGranted(),
            inputMonitoringGranted: statusProvider.isInputMonitoringGranted(),
            accessibilityGranted: statusProvider.isAccessibilityGranted()
        )
    }

    static func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    static func requestInputMonitoringAccessIfNeeded() -> Bool {
        guard !CGPreflightListenEventAccess() else { return true }
        return CGRequestListenEventAccess()
    }

    static func openSettings(for permission: AppPermission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
