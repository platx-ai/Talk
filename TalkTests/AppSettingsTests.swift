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
        // Use a unique suite to avoid polluting standard UserDefaults
        let settings = AppSettings()
        settings.recordingTriggerMode = .toggle
        settings.polishIntensity = .strong
        settings.sampleRate = 44100
        settings.conversationHistoryRounds = 10
        settings.outputMethod = .clipboardOnly
        settings.save()

        let loaded = AppSettings.load()
        #expect(loaded.recordingTriggerMode == .toggle)
        #expect(loaded.polishIntensity == .strong)
        #expect(loaded.sampleRate == 44100)
        #expect(loaded.conversationHistoryRounds == 10)
        #expect(loaded.outputMethod == .clipboardOnly)

        // Restore defaults to not affect other tests
        _ = AppSettings.resetToDefaults()
    }

    // MARK: - Reset

    @Test func resetReturnsDefaultSettings() {
        let settings = AppSettings()
        settings.recordingTriggerMode = .toggle
        settings.save()

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
        let defaults = UserDefaults.standard
        // Remove any existing JSON data, set legacy string
        defaults.removeObject(forKey: "recordingHotkey")
        defaults.set("Command + Space", forKey: "recordingHotkey")

        let loaded = AppSettings.load()
        #expect(loaded.recordingHotkey.carbonKeyCode == 49)
        #expect(loaded.recordingHotkey.carbonModifiers == 0x0100)
        #expect(loaded.recordingHotkey.isModifierOnly == false)

        // Cleanup
        defaults.removeObject(forKey: "recordingHotkey")
        _ = AppSettings.resetToDefaults()
    }
}
