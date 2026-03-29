# Changelog

All notable changes to Talk are documented here.

## [0.2.5] - 2026-03-29

### Added
- **Streaming ASR** — real-time transcription while recording ("边录边出字"), toggle in Settings → ASR
- **Silero VAD** — voice activity detection filters silence, improves ASR accuracy
- **Toast feedback** — settings changes show brief "已保存" confirmation
- **Clipboard-only output mode** — Settings → Output → "仅复制到剪贴板"

### Fixed
- **Trigger mode switch** — push-to-talk / toggle now takes effect immediately without restart
- **VAD model bundled** — Silero VAD CoreML model (904KB) included in app, no more "model not found" errors
- **Streaming ASR garbled text** — real-time audio resampling (48kHz→16kHz) + 3s startup delay
- **silero-vad-swift** — converted from broken local path to remote SPM (paean-ai/silero-vad-swift)
- **3 upstream test failures** — resample rounding, MainActor isolation, singleton state leakage
- **Output tab clarity** — removed unimplemented options, only working modes shown with explanations
- **LLM settings auto-save** — llmModelId was missing didSet { autoSave() }

### Changed
- 94 unit tests (up from 58)
- Removed committed .vscode/settings.json

## [0.2.4] - 2026-03-26

### Added
- **Panda menu bar icon** — replaces generic mic icon with panda silhouette from app logo; turns red when recording
- **Parallel model loading on cold start** — pressing hotkey with models unloaded now starts recording immediately while models load in background; no more "模型加载中" rejection

### Fixed
- **Thread-safe model loading** — loadModel() guards with isLoading flag; concurrent callers wait via polling instead of duplicate loading
- **Terminal input safety** — selection capture auto-learns unsupported apps, falls back to Cmd+C only for safe apps (never terminals)
- **Idle unload setting=0 persists** — disabling idle unload no longer resets to 10 on restart

### Changed
- Separate edit prompt — Settings → LLM now has "听写润色" and "编辑指令" tabs
- "填入默认" button fills TextEditor with default prompt text instead of clearing
- Floating indicator: aura glow ring with rotating gradient, fade-out dismiss animation
- 58 unit tests

## [0.2.3] - 2026-03-25

(see release notes)

## [0.2.2] - 2026-03-25

### Added
- **Edit mode indicator** — floating capsule shows orange ✏️ "编辑" when text is selected, vs red dot for normal voice input
- **Aura glow ring** — rotating gradient border around floating indicator, color changes per processing phase
- **Fade-out dismiss** — indicator fades away smoothly on completion
- **Auto update checker** — checks GitHub releases on launch, skip-version support, 24h throttle
- **Input Monitoring permission** — added to onboarding and settings (PR #1 by @LuyiTian)
- **PermissionManager** — unified permission detection with mock-testable protocol
- **PermissionRowView** — reusable permission status UI component

### Fixed
- **Edit mode selection capture** — restored Cmd+C fallback for apps that don't support Accessibility API
- **Edit prompt quality** — 4 explicit instruction types with examples; "replace only specified words" emphasis
- **Floating indicator background** — removed rectangular background leak, clean frosted glass capsule

### Changed
- Floating indicator positioned at screen top-center below menu bar
- 58 unit tests (up from 55)

## [0.2.1] - 2026-03-23

### Added
- **Custom app icon** — designed by Gemini, all macOS icon sizes generated
- **Auto update checker** — checks GitHub for new releases on launch
- **DMG drag-to-install** — Applications symlink in DMG
- **Per-app prompt profiles** — auto-detect frontmost app, use app-specific polish rules
- **Vocabulary management UI** — add, delete, search, import/export corrections
- **Vocabulary learning** — edit history to teach corrections, injected into LLM context

### Fixed
- **Microphone permission** — app registers with TCC on launch, appears in System Settings
- **audio-input entitlement** — added `com.apple.security.device.audio-input` for macOS 26
- **Noisy notifications removed** — success/loading/empty notifications removed, floating indicator suffices
- **LLM infinite generation** — maxTokens limit prevents runaway output on short input
- **Bluetooth audio** — system-level device switching prevents restart loop (by @jiamingkong)
- **History editing** — NSTextView wrapper fixes uneditable TextEditor in sheet on macOS

### Changed
- Compatibility matrix added to README (tested on macOS 26.2, deps support 14+)
- 55 unit tests (up from 48)

## [0.2.0] - 2026-03-23

### Added
- **Floating status indicator** — transparent overlay showing recording/processing/done states
- **Audio level visualization** — real-time RMS meter with waveform display
- **Editable LLM prompts** — 4 preset templates + custom system prompt
- **Selection edit mode** — select text + speak command = LLM executes instruction
- **Per-app prompts** — auto-detect frontmost app, app-specific polish rules
- **Customizable hotkey** — KeyRecorderView for arbitrary key combos
- **Audio device selection** — CoreAudio enumeration + hot-plug monitoring
- **Model loading indicator** — "加载模型中..." during cold start
- **Idle model unload** — configurable timeout, auto-reload on next use
- **ASR error feedback loop** — edit history to teach vocabulary corrections
- **Benchmark framework** — `make benchmark` for ASR/LLM load, inference, pipeline, memory
- **Onboarding** — 5-step first-launch guide (permissions, model download, hotkey)
- **ModelScope support** — download source for China mainland users
- **Packaging scripts** — `make package-lite` (23 MB) / `make package-full` (2.5 GB)
- **Apple notarization** — automated signing + notarization in build pipeline

### Fixed
- **Settings persistence** — AppSettings singleton with didSet auto-save
- **CGEventTap hotkey** — replaced Carbon RegisterEventHotKey, supports all key combos
- **CGEventTap performance** — background thread, no input lag
- **Personal info leaks** — removed xcuserdata, sanitized Accessibility dialog
- **LLM prompt hardening** — strict output-only rules prevent conversational filler

### Changed
- SPM remote references (pinned commits) replacing local ../MLX/ packages
- Bundle ID: `ai.platx.talk`
- 48 unit tests

## [0.1.0] - 2026-03-21

Initial release based on @jiamingkong's contribution.

- On-device ASR (Qwen3-ASR-0.6B-4bit) + LLM polish (Qwen3-4B-Instruct)
- Menu bar app with Push-to-Talk / Toggle modes
- Auto-paste via Accessibility API
- History and vocabulary persistence
