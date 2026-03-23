//
//  AudioDeviceManager.swift
//  Talk
//
//  音频输入设备管理器
//

import Foundation
import CoreAudio
import AudioToolbox

@Observable
@MainActor
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    struct AudioDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let isBuiltIn: Bool
    }

    private(set) var inputDevices: [AudioDevice] = []

    private init() {
        enumerateInputDevices()
        listenForDeviceChanges()
    }

    // MARK: - Enumerate all audio input devices

    func enumerateInputDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        var devices: [AudioDevice] = []

        for deviceID in deviceIDs {
            // Check if device has input streams
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(
                deviceID, &streamAddress, 0, nil, &streamSize
            )
            guard streamStatus == noErr, streamSize > 0 else { continue }

            // Get UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            let uidStatus = AudioObjectGetPropertyData(
                deviceID, &uidAddress, 0, nil, &uidSize, &uid
            )
            guard uidStatus == noErr else { continue }

            // Get name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            let nameStatus = AudioObjectGetPropertyData(
                deviceID, &nameAddress, 0, nil, &nameSize, &name
            )
            guard nameStatus == noErr else { continue }

            // Check transport type for built-in
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(
                deviceID, &transportAddress, 0, nil, &transportSize, &transportType
            )
            let isBuiltIn = transportType == kAudioDeviceTransportTypeBuiltIn

            let device = AudioDevice(
                id: deviceID,
                uid: uid as String,
                name: name as String,
                isBuiltIn: isBuiltIn
            )
            devices.append(device)
        }

        inputDevices = devices
    }

    // MARK: - Listen for device changes

    private func listenForDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.enumerateInputDevices()
            }
        }
    }

    // MARK: - Utility

    /// Find the UID of the built-in microphone
    static func builtInMicrophoneUID() -> String? {
        let manager = AudioDeviceManager.shared
        return manager.inputDevices.first(where: { $0.isBuiltIn })?.uid
    }

    /// Resolve a UID string to an AudioDeviceID
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var deviceUID: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            let uidStatus = AudioObjectGetPropertyData(
                deviceID, &uidAddress, 0, nil, &uidSize, &deviceUID
            )
            if uidStatus == noErr, (deviceUID as String) == uid {
                return deviceID
            }
        }

        return nil
    }

    /// Set the default system input device (works better than setting per AudioUnit)
    static func setDefaultInputDevice(deviceID: AudioDeviceID?) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDToSet = deviceID ?? 0
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDToSet
        )

        if status == noErr {
            AppLogger.info("设置系统默认输入设备成功: \(deviceIDToSet)", category: .audio)
        } else {
            AppLogger.error("设置系统默认输入设备失败: \(status)", category: .audio)
        }
    }

    /// Get the current default input device
    static func getDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var defaultDeviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &defaultDeviceID
        )

        if status == noErr, defaultDeviceID != 0 {
            return defaultDeviceID
        }
        return nil
    }
}
