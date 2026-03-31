//
//  KeyRecorderView.swift
//  Talk
//
//  快捷键录制视图
//

import SwiftUI
import AppKit
import Carbon

// MARK: - KeyRecorderView

struct KeyRecorderView: View {
    @Binding var hotkey: HotKeyCombo
    var onSave: ((HotKeyCombo) -> Void)?

    enum RecordingState {
        case display
        case recording
        case recorded(HotKeyCombo)
    }

    @State private var state: RecordingState = .display

    var body: some View {
        HStack {
            Text(String(localized: "快捷键"))
            Spacer()

            switch state {
            case .display:
                Text(hotkey.displayString)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 100, alignment: .trailing)
                Button(String(localized: "录制")) {
                    state = .recording
                }

            case .recording:
                KeyCaptureRepresentable { combo in
                    state = .recorded(combo)
                }
                .frame(width: 180, height: 24)
                .overlay(
                    Text(String(localized: "请按下快捷键..."))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                )
                Button(String(localized: "取消")) {
                    state = .display
                }

            case .recorded(let combo):
                Text(combo.displayString)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 100, alignment: .trailing)
                Button(String(localized: "保存")) {
                    hotkey = combo
                    state = .display
                    onSave?(combo)
                }
                Button(String(localized: "取消")) {
                    state = .display
                }
            }
        }
    }
}

// MARK: - NSViewRepresentable wrapper

private struct KeyCaptureRepresentable: NSViewRepresentable {
    var onCapture: (HotKeyCombo) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
    }
}

// MARK: - KeyCaptureNSView

/// Custom NSView that captures key events for hotkey recording.
/// Supports both regular key + modifier combos and modifier-only hotkeys.
final class KeyCaptureNSView: NSView {
    var onCapture: ((HotKeyCombo) -> Void)?

    /// Timer for detecting modifier-only press (fires after 300ms with no regular key)
    private var modifierTimer: Timer?
    /// The pending modifier-only combo waiting to be confirmed
    private var pendingModifierCombo: HotKeyCombo?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Cancel any pending modifier-only detection
        cancelModifierTimer()

        let carbonMods = carbonModifiers(from: event.modifierFlags)
        let keyCode = UInt32(event.keyCode)

        let combo = HotKeyCombo(
            carbonModifiers: carbonMods,
            carbonKeyCode: keyCode,
            isModifierOnly: false
        )
        onCapture?(combo)
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags
        let keyCode = UInt32(event.keyCode)

        // Check if a modifier key was pressed (not released)
        let isDown: Bool
        switch keyCode {
        case 59, 62:  // Left/Right Control
            isDown = flags.contains(.control)
        case 58, 61:  // Left/Right Option
            isDown = flags.contains(.option)
        case 56, 60:  // Left/Right Shift
            isDown = flags.contains(.shift)
        case 55, 54:  // Left/Right Command
            isDown = flags.contains(.command)
        default:
            return
        }

        if isDown {
            // Modifier pressed: compute additional modifiers (other modifiers held)
            let primaryKeyCode = normalizedModifierKeyCode(keyCode)
            var otherMods: UInt32 = carbonModifiers(from: flags)
            // Remove the primary modifier from the mask
            otherMods &= ~carbonMaskForKeyCode(primaryKeyCode)

            let combo = HotKeyCombo(
                carbonModifiers: otherMods,
                carbonKeyCode: primaryKeyCode,
                isModifierOnly: true
            )
            pendingModifierCombo = combo

            // Start 300ms timer; if no regular key arrives, treat as modifier-only
            cancelModifierTimer()
            modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self = self, let combo = self.pendingModifierCombo else { return }
                DispatchQueue.main.async {
                    self.onCapture?(combo)
                    self.pendingModifierCombo = nil
                }
            }
        } else {
            // Modifier released before timer: still treat as modifier-only if timer hasn't fired
            if let combo = pendingModifierCombo {
                cancelModifierTimer()
                onCapture?(combo)
                pendingModifierCombo = nil
            }
        }
    }

    // MARK: - Helpers

    private func cancelModifierTimer() {
        modifierTimer?.invalidate()
        modifierTimer = nil
    }

    /// Normalize left/right variants to the canonical key code
    private func normalizedModifierKeyCode(_ keyCode: UInt32) -> UInt32 {
        switch keyCode {
        case 59, 62: return 59   // Control
        case 58, 61: return 58   // Option
        case 56, 60: return 56   // Shift
        case 55, 54: return 55   // Command
        default: return keyCode
        }
    }

    /// Convert NSEvent.ModifierFlags to Carbon modifier mask
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= 0x1000 }
        if flags.contains(.option)  { result |= 0x0800 }
        if flags.contains(.shift)   { result |= 0x0200 }
        if flags.contains(.command) { result |= 0x0100 }
        return result
    }

    /// Carbon modifier mask for a given modifier key code
    private func carbonMaskForKeyCode(_ keyCode: UInt32) -> UInt32 {
        switch keyCode {
        case 59: return 0x1000  // Control
        case 58: return 0x0800  // Option
        case 56: return 0x0200  // Shift
        case 55: return 0x0100  // Command
        default: return 0
        }
    }
}
