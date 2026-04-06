<p align="center">
  <img src="docs/assets/icon_512.png" width="128" height="128" alt="Talk icon">
</p>

<h1 align="center">Talk</h1>

<p align="center"><strong>Open Typeless. Local Typeless. Typeless in your box.</strong></p>

A macOS menu bar voice input tool — hold a hotkey, speak, and your words are recognized, polished, and pasted into the active app. Your voice, straight to text. No cloud. No typing.

[**Download Talk v0.4.0**](https://github.com/platx-ai/Talk/releases/latest) · [中文文档](README_zh.md)

> The original algorithm and code are based on the generous contribution of [@jiamingkong](https://github.com/jiamingkong). We just wanted to see if we could build a typeless in ten minutes.

## Features

- **On-device inference** — Powered by Apple Silicon MLX, no cloud dependency, privacy-first
- **Dual ASR engines** — Local MLX (Qwen3-ASR-0.6B-4bit) or Apple Speech Recognition, switchable in settings
- **Text polishing** — Qwen3-4B-Instruct, removes filler words, adds punctuation, smart formatting
- **Auto hotword learning** — Passively observes your edits after text injection, automatically learns ASR corrections (proper nouns, homophones, abbreviations) via LLM extraction
- **Audio history** — Every recording saved as AAC/M4A with full ASR context snapshot for replay and debugging
- **Customizable prompts** — Per-app prompt profiles, 3 polish intensity levels, or write your own system prompt
- **Selection edit mode** — Select text, speak a command ("fix the typo", "make it casual"), and it's done
- **Floating status indicator** — Always-on-top overlay showing recording/processing state with audio level meter
- **Global hotkey** — Customizable key recorder, Push-to-Talk / Toggle modes
- **Audio device selection** — Pick your input device, defaults to built-in microphone
- **Auto-paste** — Injects text via Accessibility API with CJK input method auto-switching
- **Vocabulary learning** — Automatic learning from edit history + manual entry, corrections injected into LLM context
- **Idle memory management** — Auto-unload models after inactivity, reload on demand

## Performance

All inference runs on-device via Apple Silicon GPU. No network required after model download.

| Stage | Latency | Notes |
|-------|---------|-------|
| ASR (3-5s audio) | **0.07 - 0.18s** | 17-51x faster than real-time |
| LLM polish (short text) | **0.35 - 0.50s** | ~30 chars input |
| LLM polish (long text) | **1.1 - 1.2s** | ~120 chars input |
| **Full pipeline** | **~1s** | ASR + LLM combined (models warm) |
| ASR model load | 2s | Cold start, one-time |
| LLM model load | 10s | Cold start, one-time — **bottleneck** |

Memory usage:

| State | RSS |
|-------|-----|
| ASR model loaded | ~1.6 GB |
| Both models loaded | ~5.4 GB |

> Full benchmark details and reproduction steps: [docs/BENCHMARK.md](docs/BENCHMARK.md)
>
> Run `make benchmark` to reproduce on your machine.

## Compatibility

The pre-built DMG in [Releases](https://github.com/platx-ai/Talk/releases/latest) is built and tested on **macOS 26.2 (Tahoe)** with Apple Silicon. That's the only environment we have — our human overlords haven't blessed us with more test devices yet.

| | Tested | Should Work | Notes |
|---|--------|------------|-------|
| macOS 26.x (Tahoe) | ✅ | ✅ | Built & tested here |
| macOS 15.x (Sequoia) | | Likely | Dependencies support macOS 14+ |
| macOS 14.x (Sonoma) | | Maybe | Minimum required by MLX dependencies |
| macOS 13 and below | | No | MLX framework requires macOS 14+ |
| Intel Mac | | No | MLX is Apple Silicon only |

If you're on an older macOS version and encounter issues, try building from source — it might just work:
```bash
git clone https://github.com/platx-ai/Talk.git && cd Talk
make build && make run
```
If it doesn't, [open an issue](https://github.com/platx-ai/Talk/issues) and tell us what broke. We'd love more test environments.

## Requirements

- Apple Silicon (M1/M2/M3/M4) — **required**, no Intel support
- macOS 14.0+ (Sonoma) — minimum for MLX dependencies; pre-built DMG targets 26.2+
- 16 GB RAM recommended (8 GB works with lightweight model — coming soon)
- ~3 GB disk space (model files)
- Xcode 26.3+ (only for building from source)

## Quick Start

```bash
# Clone the project
git clone https://github.com/platx-ai/Talk.git
cd Talk

# Full setup: resolve dependencies + download models
make setup

# Run
make run
```

## Build

```bash
make build          # Debug build
make build-release  # Release build
make test           # Run unit tests
make benchmark      # Run performance benchmarks
make run            # Build and run
make clean          # Clean build artifacts
make resolve        # Resolve SPM dependencies only
make download-models # Download ML models from HuggingFace
make setup          # Full setup: resolve + download models
make lint           # Run SwiftLint (if installed)
```

## Architecture

```
Record(AVAudioEngine) → ASR(Qwen3-ASR) → LLM Polish(Qwen3-4B) → Text Inject(Cmd+V)
       ↑                  0.1s               0.5s                     ↑
    CoreAudio                                                    Accessibility
  Device Selection                                                API Permission
```

### Modules

| Module | Responsibility |
|--------|---------------|
| `Audio/` | Recording engine, global hotkeys (CGEventTap), audio device management, text injection |
| `ASR/` | Speech recognition — MLX local (Qwen3-ASR) + Apple Speech |
| `LLM/` | Text polishing + hotword extraction (MLXLLM + Qwen3-4B-Instruct) |
| `Models/` | Data models (AppSettings, HotKeyCombo, HistoryItem, ASRContext) |
| `Data/` | History (JSON + M4A audio), vocabulary, edit observer |
| `UI/` | SwiftUI menu bar, settings panel, key recorder, floating indicator, history browser, flash capsule |
| `Utils/` | Logging system, Metal runtime validation |

### Dependencies

All dependencies managed via Swift Package Manager, pinned to specific commits:

| Package | Source | Purpose |
|---------|--------|---------|
| mlx-swift | [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | MLX core array operations |
| mlx-swift-lm | [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | LLM inference framework |
| mlx-audio-swift | [platx-ai/mlx-audio-swift](https://github.com/platx-ai/mlx-audio-swift) (fork) | Audio STT framework |
| swift-huggingface | [huggingface/swift-huggingface](https://github.com/huggingface/swift-huggingface) | Model downloading |

> mlx-audio-swift uses the platx-ai fork to fix an upstream bug where MLXAudioCodecs is missing the MLXFast dependency.

### Models

| Model | Size | Load Time | Memory | Purpose |
|-------|------|-----------|--------|---------|
| [Qwen3-ASR-0.6B-4bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit) | ~400 MB | 2s | ~1.6 GB | Speech recognition |
| [Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) | ~2.5 GB | 10s | ~4 GB | Text polishing |

Models are automatically downloaded from HuggingFace on first run to `~/.cache/huggingface/`. Pre-download with `make download-models`.

## Vocabulary & Auto Learning

Talk learns from your corrections in two ways:

### Passive Edit Observation (v0.4.0)
After text is injected into the target app, Talk passively monitors the text field via Accessibility API. If you edit the injected text (e.g., fix a misrecognized word), Talk detects the change, extracts hotword corrections using a background LLM pass, and adds them to the vocabulary. A flash ⚡ capsule in the menu bar confirms when new corrections are learned. This works automatically — no manual steps needed.

### Manual Correction
- **History edit** — Edit polished text in the history view. The system learns the correction automatically.
- **Manual entry** — Settings → Personal Vocabulary → Manage Vocabulary. Add original words and their corrected forms.
- **Import/Export** — JSON format via Manage Vocabulary.

The top learned corrections are injected into the LLM system prompt, so the model applies them automatically in future polishing.

**Example**: If ASR outputs "la laam" but you correct it to "LLM", future polishing will automatically apply this correction.

## Audio History (v0.4.0)

Every voice input is saved as AAC/M4A (64kbps, ~80KB per 10s) alongside a context snapshot (hotword list, language, polish intensity, target app). This enables:

- **Replay & debugging** — Reproduce ASR issues with the exact audio that was processed
- **Regression testing** — Compare recognition quality across versions
- **Automatic cleanup** — Audio files are deleted when history entries are removed or expired

Toggle in Settings → Personal Vocabulary → "Save Audio History".

## Permissions

On first launch, you need to grant:

1. **Microphone** — Required for recording. macOS will prompt automatically.
2. **Input Monitoring** — Required for the global hotkey. Enable Talk in System Settings → Privacy & Security → Input Monitoring.
3. **Accessibility** — Required for auto-pasting text into other apps. Enable Talk in System Settings → Privacy & Security → Accessibility.

If the global hotkey does not respond, check **Input Monitoring** first. After enabling it, quit and relaunch Talk so the hotkey listener can work reliably.

## Development

```bash
# Open in Xcode
open Talk.xcodeproj

# Set your signing team: Xcode → Signing & Capabilities → Team
# Build & Run: ⌘R
```

### Testing

```bash
make test       # Unit tests
make benchmark  # Performance benchmarks (ASR/LLM load, inference, pipeline, memory)
```

All changes require tests. Bugs require regression tests before fixing. See [CLAUDE.md](CLAUDE.md) for testing rules.

### Code Signing

`DEVELOPMENT_TEAM` is left empty in the project. Each developer sets their own signing team in Xcode. CLI builds use ad-hoc signing.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full product roadmap.

**Next up**
- Custom lightweight polish model (0.5-1.5B) — < 1s load, < 1 GB memory
- Real-time transcription preview overlay
- Model auto-select by hardware (8 GB → lightweight, 16 GB+ → full)

**Mid-term**
- Project-aware vocabulary & prompt profiles (per-repo `.talk/` config)
- iCloud vocabulary sync across devices
- iOS companion app with offline on-device inference

**Long-term**
- Team shared terminology libraries
- Plugin system for custom post-processing pipelines

## License

[MIT](LICENSE)
