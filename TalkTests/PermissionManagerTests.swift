//
//  PermissionManagerTests.swift
//  TalkTests
//
//  Permission manager unit tests using Swift Testing framework
//

import Testing
import Foundation
@testable import Talk

struct PermissionManagerTests {
    private struct MockPermissionStatusProvider: PermissionStatusProviding {
        let microphoneGranted: Bool
        let inputMonitoringGranted: Bool
        let accessibilityGranted: Bool

        func isMicrophoneGranted() -> Bool { microphoneGranted }
        func isInputMonitoringGranted() -> Bool { inputMonitoringGranted }
        func isAccessibilityGranted() -> Bool { accessibilityGranted }
    }

    @Test func snapshotRequiresInputMonitoringForFullReadiness() {
        let snapshot = PermissionManager.snapshot(statusProvider: MockPermissionStatusProvider(
            microphoneGranted: true,
            inputMonitoringGranted: false,
            accessibilityGranted: true
        ))

        #expect(snapshot.microphoneGranted == true)
        #expect(snapshot.inputMonitoringGranted == false)
        #expect(snapshot.accessibilityGranted == true)
        #expect(snapshot.allRequiredGranted == false)
    }

    @Test func snapshotIsReadyWhenAllPermissionsGranted() {
        let snapshot = PermissionManager.snapshot(statusProvider: MockPermissionStatusProvider(
            microphoneGranted: true,
            inputMonitoringGranted: true,
            accessibilityGranted: true
        ))

        #expect(snapshot.allRequiredGranted == true)
        #expect(snapshot.isGranted(.microphone) == true)
        #expect(snapshot.isGranted(.inputMonitoring) == true)
        #expect(snapshot.isGranted(.accessibility) == true)
    }

    @Test func inputMonitoringMetadataIncludesRestartGuidance() {
        #expect(AppPermission.inputMonitoring.title == "输入监控")
        #expect(AppPermission.inputMonitoring.settingsURL.absoluteString.contains("Privacy_ListenEvent"))
        #expect(AppPermission.inputMonitoring.restartHint == "开启后请退出并重新打开 Talk，全局快捷键才会生效。")
    }
}
