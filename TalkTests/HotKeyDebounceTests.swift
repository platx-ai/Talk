//
//  HotKeyDebounceTests.swift
//  TalkTests
//
//  热键事件 debounce 测试
//

import Testing
import Foundation
@testable import Talk

@Suite("HotKey Debounce Tests")
struct HotKeyDebounceTests {

    @Test @MainActor
    func handleKeyStateGuardsAgainstDuplicatePress() {
        let hk = HotKeyManager.shared
        let origMode = hk.triggerMode

        // 设置 push-to-talk 模式
        hk.setTriggerMode(.pushToTalk)

        var pressCount = 0
        var releaseCount = 0
        let origPress = hk.onHotKeyPressed
        let origRelease = hk.onHotKeyReleased
        hk.onHotKeyPressed = { pressCount += 1 }
        hk.onHotKeyReleased = { releaseCount += 1 }

        // 模拟正常 press → release
        hk.testHandleKeyState(isDown: true)
        hk.testHandleKeyState(isDown: false)
        #expect(pressCount == 1)
        #expect(releaseCount == 1)

        // 模拟重复 press（应该被 isKeyPressed 守卫阻止）
        hk.testHandleKeyState(isDown: true)
        hk.testHandleKeyState(isDown: true)  // duplicate
        #expect(pressCount == 2)  // 只增加了一次

        hk.testHandleKeyState(isDown: false)
        #expect(releaseCount == 2)

        // 恢复
        hk.onHotKeyPressed = origPress
        hk.onHotKeyReleased = origRelease
        hk.setTriggerMode(origMode)
    }

    @Test @MainActor
    func releaseWithoutPressIsIgnored() {
        let hk = HotKeyManager.shared
        hk.setTriggerMode(.pushToTalk)

        var releaseCount = 0
        let origRelease = hk.onHotKeyReleased
        hk.onHotKeyReleased = { releaseCount += 1 }

        // 没有 press 直接 release，应被忽略
        hk.testHandleKeyState(isDown: false)
        #expect(releaseCount == 0)

        hk.onHotKeyReleased = origRelease
    }

    @Test
    func debounceThresholdIsReasonable() {
        // 50ms debounce — 足够过滤抖动，不影响正常操作
        #expect(HotKeyManager.debounceNanos == 50_000_000)
    }
}
