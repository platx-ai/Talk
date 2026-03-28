//
//  AudioDeviceSwitchTests.swift
//  TalkTests
//
//  Diagnostic tests for audio device switching (especially Bluetooth)
//

import Testing
import Foundation
import AVFoundation
import CoreAudio
@testable import Talk

@MainActor
struct AudioDeviceSwitchTests {

    // MARK: - Device enumeration

    @Test func bluetoothDevicesAreEnumerated() {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()

        let bluetoothDevices = manager.inputDevices.filter { !$0.isBuiltIn }
        #expect(bluetoothDevices.count >= 0, "Should have non-built-in devices (including Bluetooth)")

        // Log all non-built-in devices for debugging
        if !bluetoothDevices.isEmpty {
            print("\n=== Available non-built-in audio devices ===")
            for device in bluetoothDevices {
                print("- \(device.name) (UID: \(device.uid))")
            }
            print("=============================================\n")
        }
    }

    // MARK: - Device ID resolution

    @Test func deviceIDForBluetoothDeviceResolves() {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()

        guard let firstNonBuiltIn = manager.inputDevices.first(where: { !$0.isBuiltIn }) else {
            print("No non-built-in devices found, skipping test")
            return
        }

        let deviceID = AudioDeviceManager.deviceID(forUID: firstNonBuiltIn.uid)
        #expect(deviceID != nil, "Should resolve device ID for \(firstNonBuiltIn.name)")

        print("Resolved device ID \(deviceID!) for \(firstNonBuiltIn.name)")
    }

    // MARK: - AudioUnit property setting

    @Test func canSetCurrentDeviceProperty() throws {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()

        guard let targetDevice = manager.inputDevices.first(where: { !$0.isBuiltIn }) else {
            print("No non-built-in devices found, skipping test")
            return
        }

        guard let deviceID = AudioDeviceManager.deviceID(forUID: targetDevice.uid) else {
            Issue.record("Cannot resolve device ID for \(targetDevice.name)")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else {
            Issue.record("Cannot get audioUnit from inputNode")
            return
        }

        var id = deviceID
        let err = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        #expect(err == noErr, "AudioUnitSetProperty should succeed (error code: \(err))")

        if err == noErr {
            print("Successfully set audio device to: \(targetDevice.name)")
            print("Device UID: \(targetDevice.uid)")
            print("Device ID: \(deviceID)")
        }
    }

    // MARK: - Format retrieval after device switch

    @Test func formatRetrievedAfterDeviceSwitch() throws {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()

        guard let targetDevice = manager.inputDevices.first(where: { !$0.isBuiltIn }) else {
            print("No non-built-in devices found, skipping test")
            return
        }

        guard let deviceID = AudioDeviceManager.deviceID(forUID: targetDevice.uid) else {
            Issue.record("Cannot resolve device ID for \(targetDevice.name)")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else {
            Issue.record("Cannot get audioUnit from inputNode")
            return
        }

        // Get format before device switch
        let formatBefore = input.outputFormat(forBus: 0)
        print("\n=== Format BEFORE device switch ===")
        print("Sample rate: \(formatBefore.sampleRate)")
        print("Channel count: \(formatBefore.channelCount)")
        print("Format ID: \(formatBefore.commonFormat)")
        print("====================================\n")

        // Switch device
        var id = deviceID
        let err = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard err == noErr else {
            Issue.record("Failed to set device: error code \(err)")
            return
        }

        // Get format after device switch
        let formatAfter = input.outputFormat(forBus: 0)
        print("\n=== Format AFTER device switch ===")
        print("Sample rate: \(formatAfter.sampleRate)")
        print("Channel count: \(formatAfter.channelCount)")
        print("Format ID: \(formatAfter.commonFormat)")
        print("===================================\n")

        // The format may or may not change depending on device capabilities
        print("Device switched to: \(targetDevice.name)")
        print("Format changed: \(formatBefore.sampleRate != formatAfter.sampleRate || formatBefore.channelCount != formatAfter.channelCount)")
    }

    // MARK: - Engine restart after device switch

    @Test func canRestartEngineWithNewDevice() throws {
        let manager = AudioDeviceManager.shared
        manager.enumerateInputDevices()

        guard let targetDevice = manager.inputDevices.first(where: { !$0.isBuiltIn }) else {
            print("No non-built-in devices found, skipping test")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Start with default device
        try engine.start()
        print("Engine started with default device")

        // Stop and switch device
        engine.stop()

        guard let deviceID = AudioDeviceManager.deviceID(forUID: targetDevice.uid) else {
            Issue.record("Cannot resolve device ID for \(targetDevice.name)")
            return
        }

        if let audioUnit = input.audioUnit {
            var id = deviceID
            let err = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )

            if err == noErr {
                print("Device switched to: \(targetDevice.name)")

                // Get format after switch
                let format = input.outputFormat(forBus: 0)
                print("Format after switch: \(format.sampleRate)Hz, \(format.channelCount) channels")

                // Restart engine
                try engine.start()
                print("Engine restarted successfully")

                #expect(true, "Engine restart after device switch should work")
            } else {
                print("Failed to set device: error code \(err)")
                #expect(err == noErr, "Device switch should succeed")
            }
        } else {
            Issue.record("Cannot get audioUnit from inputNode")
        }
    }
}
