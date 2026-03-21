//
//  AudioDeviceManagerTests.swift
//  TalkTests
//
//  AudioDeviceManager unit tests using Swift Testing framework
//

import Testing
import Foundation
import CoreAudio
@testable import Talk

@MainActor
struct AudioDeviceManagerTests {

    // MARK: - Shared instance

    @Test func sharedInstanceExists() {
        let manager = AudioDeviceManager.shared
        #expect(manager != nil)
    }

    // MARK: - Enumerate devices

    @Test func enumerateInputDevicesReturnsAtLeastOneDevice() {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()
        #expect(manager.inputDevices.count >= 1)
    }

    @Test func atLeastOneDeviceIsBuiltIn() {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()
        let hasBuiltIn = manager.inputDevices.contains(where: { $0.isBuiltIn })
        #expect(hasBuiltIn)
    }

    @Test func audioDeviceHasNonEmptyUIDAndName() {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()
        guard let device = manager.inputDevices.first else {
            Issue.record("No input devices found")
            return
        }
        #expect(!device.uid.isEmpty)
        #expect(!device.name.isEmpty)
    }

    // MARK: - builtInMicrophoneUID

    @Test func builtInMicrophoneUIDReturnsNonNil() {
        let uid = AudioDeviceManager.builtInMicrophoneUID()
        #expect(uid != nil)
    }

    // MARK: - deviceID(forUID:)

    @Test func deviceIDForBuiltInMicReturnsValidID() {
        guard let uid = AudioDeviceManager.builtInMicrophoneUID() else {
            Issue.record("No built-in microphone UID")
            return
        }
        let deviceID = AudioDeviceManager.deviceID(forUID: uid)
        #expect(deviceID != nil)
    }

    @Test func deviceIDForUnknownUIDReturnsNil() {
        let deviceID = AudioDeviceManager.deviceID(forUID: "com.nonexistent.fake.device.uid.12345")
        #expect(deviceID == nil)
    }
}
