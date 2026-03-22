//
//  AppSettingsTests.swift
//  TalkTests
//
//  AppSettings unit tests using Swift Testing framework
//

import Testing
import Foundation
@testable import Talk

struct AppSettingsTests {

    // MARK: - Default values

    @Test func defaultSettingsHaveExpectedValues() {
        let settings = AppSettings()
        #expect(settings.recordingTriggerMode == .pushToTalk)
        #expect(settings.recordingHotkey == .defaultCombo)
        #expect(settings.recordingMaxDuration == 0)
        #expect(settings.silenceTimeout == 0)
        #expect(settings.sampleRate == 16000)
        #expect(settings.asrLanguage == .auto)
        #expect(settings.showRealtimeRecognition == true)
        #expect(settings.polishIntensity == .medium)
        #expect(settings.conversationHistoryRounds == 5)
        #expect(settings.enableConversationHistory == true)
        #expect(settings.outputMethod == .autoPaste)
        #expect(settings.outputDelay == .afterPolish)
        #expect(settings.performanceMode == .speed)
        #expect(settings.memoryMode == .normal)
        #expect(settings.launchAtLogin == false)
        #expect(settings.enableDetailedLogging == true)
        #expect(settings.logLevel == .debug)
    }

    // MARK: - Save / Load round-trip

    @Test func saveAndLoadRoundTrip() {
        let shared = AppSettings.shared

        // Save original values
        let origTrigger = shared.recordingTriggerMode
        let origIntensity = shared.polishIntensity
        let origSampleRate = shared.sampleRate

        // Modify and save (autoSave via didSet)
        shared.recordingTriggerMode = .toggle
        shared.polishIntensity = .strong
        shared.sampleRate = 44100

        // Reload from UserDefaults to verify persistence
        shared.loadFromDefaults()
        #expect(shared.recordingTriggerMode == .toggle)
        #expect(shared.polishIntensity == .strong)
        #expect(shared.sampleRate == 44100)

        // Restore
        shared.recordingTriggerMode = origTrigger
        shared.polishIntensity = origIntensity
        shared.sampleRate = origSampleRate
    }

    // MARK: - Reset

    @Test func resetReturnsDefaultSettings() {
        let reset = AppSettings.resetToDefaults()
        #expect(reset.recordingTriggerMode == .pushToTalk)
        #expect(reset.recordingHotkey == .defaultCombo)
    }

    // MARK: - HotKeyCombo persistence

    @Test func hotKeyComboPersistence() throws {
        let combo = HotKeyCombo(carbonModifiers: 0x0100, carbonKeyCode: 49, isModifierOnly: false)
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(HotKeyCombo.self, from: data)
        #expect(decoded == combo)
        #expect(decoded.carbonModifiers == 0x0100)
        #expect(decoded.carbonKeyCode == 49)
        #expect(decoded.isModifierOnly == false)
    }

    // MARK: - selectedAudioDeviceUID default

    @Test func selectedAudioDeviceUIDDefaultsToNil() {
        let settings = AppSettings()
        #expect(settings.selectedAudioDeviceUID == nil)
    }

    // MARK: - Legacy hotkey migration

    @Test func legacyHotkeyStringMigrationOnLoad() {
        let shared = AppSettings.shared
        let origHotkey = shared.recordingHotkey

        let defaults = UserDefaults.standard
        // Remove any existing JSON data, set legacy string
        defaults.removeObject(forKey: "recordingHotkey")
        defaults.set("Command + Space", forKey: "recordingHotkey")

        shared.loadFromDefaults()
        #expect(shared.recordingHotkey.carbonKeyCode == 49)
        #expect(shared.recordingHotkey.carbonModifiers == 0x0100)
        #expect(shared.recordingHotkey.isModifierOnly == false)

        // Restore
        shared.recordingHotkey = origHotkey
    }

    // MARK: - Idle unload

    @Test func idleUnloadMinutesDefault() {
        let settings = AppSettings()
        #expect(settings.idleUnloadMinutes == 10)
    }

    // MARK: - Custom prompt persistence

    @Test func customPromptAutoSaves() {
        let shared = AppSettings.shared
        let origPrompt = shared.customSystemPrompt

        shared.customSystemPrompt = "测试自动保存提示词"

        // Reload and verify
        shared.loadFromDefaults()
        #expect(shared.customSystemPrompt == "测试自动保存提示词")

        // Restore
        shared.customSystemPrompt = origPrompt
    }

    // MARK: - App prompts

    @Test func appPromptsDefaultEmpty() {
        let settings = AppSettings()
        #expect(settings.appPrompts.isEmpty)
    }

    @Test func appPromptsPersistence() {
        let shared = AppSettings.shared
        let orig = shared.appPrompts

        shared.appPrompts["com.apple.Terminal"] = "test prompt"
        shared.loadFromDefaults()
        #expect(shared.appPrompts["com.apple.Terminal"] == "test prompt")

        shared.appPrompts = orig
    }
}
