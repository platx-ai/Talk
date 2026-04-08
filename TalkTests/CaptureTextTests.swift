//
//  CaptureTextTests.swift
//  TalkTests
//
//  Cmd+C 选中文本捕获逻辑测试
//

import Testing
import Foundation
@testable import Talk

@Suite("Capture Selected Text Tests")
struct CaptureTextTests {

    // MARK: - shouldTreatAsNoSelection

    @Test
    func singleLineWithNewline_treatedAsNoSelection() {
        #expect(AppDelegate.shouldTreatAsNoSelection("let x = 1\n") == true)
    }

    @Test
    func singleLineWithWindowsNewline_treatedAsNoSelection() {
        #expect(AppDelegate.shouldTreatAsNoSelection("let x = 1\r\n") == true)
    }

    @Test
    func multiLineSelection_notFiltered() {
        #expect(AppDelegate.shouldTreatAsNoSelection("line1\nline2\n") == false)
    }

    @Test
    func multiLineSelectionWindowsEndings_notFiltered() {
        #expect(AppDelegate.shouldTreatAsNoSelection("line1\r\nline2\r\n") == false)
    }

    @Test
    func singleLineNoNewline_notFiltered() {
        #expect(AppDelegate.shouldTreatAsNoSelection("hello world") == false)
    }

    @Test
    func emptyString_notFiltered() {
        #expect(AppDelegate.shouldTreatAsNoSelection("") == false)
    }

    @Test
    func onlyNewline_treatedAsNoSelection() {
        #expect(AppDelegate.shouldTreatAsNoSelection("\n") == true)
    }

    @Test
    func onlyWindowsNewline_treatedAsNoSelection() {
        #expect(AppDelegate.shouldTreatAsNoSelection("\r\n") == true)
    }

    // MARK: - isTerminalApp

    @Test
    func terminalAppsDetected() {
        #expect(AppDelegate.isTerminalApp("com.apple.Terminal") == true)
        #expect(AppDelegate.isTerminalApp("com.googlecode.iterm2") == true)
        #expect(AppDelegate.isTerminalApp("net.kovidgoyal.kitty") == true)
        #expect(AppDelegate.isTerminalApp("com.github.wez.wezterm") == true)
        #expect(AppDelegate.isTerminalApp("co.zeit.hyper") == true)
        #expect(AppDelegate.isTerminalApp("dev.warp.Warp-Stable") == true)
        #expect(AppDelegate.isTerminalApp("io.alacritty") == true)
    }

    @Test
    func nonTerminalAppsNotDetected() {
        #expect(AppDelegate.isTerminalApp("com.microsoft.VSCode") == false)
        #expect(AppDelegate.isTerminalApp("com.apple.Safari") == false)
        #expect(AppDelegate.isTerminalApp("com.apple.dt.Xcode") == false)
    }

    // MARK: - axUnsupportedApps persistence

    @Test
    func axUnsupportedAppsPersistence() {
        let key = "axUnsupportedApps"
        let original = UserDefaults.standard.stringArray(forKey: key)

        UserDefaults.standard.set(["com.test.app1", "com.test.app2"], forKey: key)

        let loaded = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        #expect(loaded.contains("com.test.app1"))
        #expect(loaded.contains("com.test.app2"))

        // Restore
        if let original {
            UserDefaults.standard.set(original, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
