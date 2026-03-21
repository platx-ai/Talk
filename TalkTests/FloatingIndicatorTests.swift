//
//  FloatingIndicatorTests.swift
//  TalkTests
//
//  悬浮指示器测试
//

import Testing
import Foundation
@testable import Talk

@Suite("FloatingIndicatorState Tests")
struct FloatingIndicatorStateTests {

    @Test @MainActor
    func defaultPhaseIsRecording() {
        let state = FloatingIndicatorState()
        if case .recording = state.phase {
            // expected
        } else {
            Issue.record("Default phase should be .recording")
        }
    }

    @Test @MainActor
    func audioLevelDefaultsToZero() {
        let state = FloatingIndicatorState()
        #expect(state.audioLevel == 0.0)
    }

    @Test @MainActor
    func audioLevelCanBeUpdated() {
        let state = FloatingIndicatorState()
        state.audioLevel = 0.75
        #expect(state.audioLevel == 0.75)
    }

    @Test @MainActor
    func phaseCanTransitionThroughAllStates() {
        let state = FloatingIndicatorState()

        state.phase = .recording(startDate: Date())
        if case .recording = state.phase { } else {
            Issue.record("Should be recording")
        }

        state.phase = .recognizing
        if case .recognizing = state.phase { } else {
            Issue.record("Should be recognizing")
        }

        state.phase = .polishing
        if case .polishing = state.phase { } else {
            Issue.record("Should be polishing")
        }

        state.phase = .outputting
        if case .outputting = state.phase { } else {
            Issue.record("Should be outputting")
        }

        state.phase = .done
        if case .done = state.phase { } else {
            Issue.record("Should be done")
        }
    }
}

@Suite("FloatingIndicatorWindow Tests")
struct FloatingIndicatorWindowTests {

    @Test @MainActor
    func windowCanBeCreated() {
        let window = FloatingIndicatorWindow()
        // Should not crash
        _ = window
    }

    @Test @MainActor
    func showAndDismissDoesNotCrash() {
        let window = FloatingIndicatorWindow()
        window.show()
        window.dismiss()
    }

    @Test @MainActor
    func updatePhaseDoesNotCrash() {
        let window = FloatingIndicatorWindow()
        window.show()
        window.updatePhase(.recording(startDate: Date()))
        window.updatePhase(.recognizing)
        window.updatePhase(.polishing)
        window.updatePhase(.outputting)
        window.updatePhase(.done)
        window.dismiss()
    }

    @Test @MainActor
    func updateAudioLevelDoesNotCrash() {
        let window = FloatingIndicatorWindow()
        window.show()
        window.updateAudioLevel(0.0)
        window.updateAudioLevel(0.5)
        window.updateAudioLevel(1.0)
        window.dismiss()
    }
}

@Suite("AudioRecorder Audio Level Tests")
struct AudioRecorderAudioLevelTests {

    @Test
    func onAudioLevelCallbackCanBeSetAndCleared() {
        let recorder = AudioRecorder.shared
        let previous = recorder.onAudioLevel

        var receivedLevel: Float?
        recorder.onAudioLevel = { level in
            receivedLevel = level
        }
        #expect(recorder.onAudioLevel != nil)

        // Invoke it
        recorder.onAudioLevel?(0.42)
        #expect(receivedLevel == 0.42)

        // Restore previous state
        recorder.onAudioLevel = previous
    }
}
