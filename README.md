# Talk

**Open Typeless. Local Typeless. Typeless in your box.**

A macOS menu bar voice input tool — hold a hotkey, speak, and your words are recognized, polished, and pasted into the active app. Your voice, straight to text. No cloud. No typing.

[中文文档](README_zh.md)

> The original algorithm and code are based on the generous contribution of [@jiamingkong](https://github.com/jiamingkong). We just wanted to see if we could build a typeless in ten minutes.

## Features

- **On-device inference** — Powered by Apple Silicon MLX, no cloud dependency, privacy-first
- **Speech recognition** — Qwen3-ASR-0.6B-4bit, supports Chinese and English
- **Text polishing** — Qwen3-4B-Instruct, removes filler words, adds punctuation, smart formatting
- **Customizable prompts** — 4 preset templates (strict/light/meeting/tech) or write your own system prompt
- **Selection edit mode** — Select text, speak a command ("fix the typo", "make it casual"), and it's done
- **Floating status indicator** — Always-on-top overlay showing recording/processing state with audio level meter
- **Global hotkey** — Customizable key recorder, Push-to-Talk / Toggle modes
- **Audio device selection** — Pick your input device, defaults to built-in microphone
- **Auto-paste** — Injects text via Accessibility API (Cmd+V simulation)

## Requirements

- macOS 26.2+
- Apple Silicon (M1/M2/M3/M4)
- Xcode 26.3+
- ~5GB disk space (model files)

## Quick Start

```bash
# Clone the project
git clone https://github.com/platx-ai/Talk.git
cd Talk

# Resolve dependencies & build
make build

# Download models (first time only)
make download-models

# Run
make run
```

## Build

```bash
make build          # Debug build
make build-release  # Release build
make test           # Run unit tests
make clean          # Clean build artifacts
make resolve        # Resolve SPM dependencies only
make setup          # Full setup: resolve deps + download models
make lint           # Run SwiftLint (if installed)
```

## Architecture

```
Record(AVAudioEngine) → ASR(Qwen3-ASR) → LLM Polish(Qwen3-4B) → Text Inject(Cmd+V)
       ↑                                                               ↑
    CoreAudio                                                     Accessibility
  Device Selection                                                 API Permission
```

### Modules

| Module | Responsibility |
|--------|---------------|
| `Audio/` | Recording engine, global hotkeys (Carbon API), audio device management, text injection |
| `ASR/` | Speech recognition (MLXAudioSTT + Qwen3-ASR) |
| `LLM/` | Text polishing (MLXLLM + Qwen3-4B-Instruct) |
| `Models/` | Data models (AppSettings, HotKeyCombo, HistoryItem) |
| `Data/` | History and vocabulary JSON persistence |
| `UI/` | SwiftUI menu bar, settings panel, key recorder, history browser |
| `Utils/` | Logging system, Metal runtime validation |

### Dependencies

| Package | Source | Version |
|---------|--------|---------|
| mlx-swift | [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | `b6e128c` |
| mlx-swift-lm | [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | `edd42fc` |
| mlx-audio-swift | [platx-ai/mlx-audio-swift](https://github.com/platx-ai/mlx-audio-swift) (fork) | `4ece9e0` |
| swift-huggingface | [huggingface/swift-huggingface](https://github.com/huggingface/swift-huggingface) | `0.9.0` |

> mlx-audio-swift uses the platx-ai fork to fix an upstream bug where [MLXAudioCodecs is missing the MLXFast dependency](https://github.com/Blaizzy/mlx-audio-swift/issues/).

### Models

| Model | Size | Purpose |
|-------|------|---------|
| [mlx-community/Qwen3-ASR-0.6B-4bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit) | ~400MB | Speech recognition |
| [mlx-community/Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) | ~2.5GB | Text polishing |

Models are automatically downloaded from HuggingFace on first run to `~/.cache/huggingface/`. You can also pre-download them with `make download-models`.

## Permissions

On first launch, you need to grant:

1. **Microphone** — macOS will prompt automatically
2. **Accessibility** — Manually add Talk.app in System Settings → Privacy & Security → Accessibility

## Development

```bash
# Open in Xcode
open Talk.xcodeproj

# Set your signing team: Xcode → Signing & Capabilities → Team
# Build & Run: ⌘R
```

### Code Signing

`DEVELOPMENT_TEAM` is left empty in the project. Each developer sets their own signing team in Xcode. CLI builds use ad-hoc signing.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full product roadmap.

**Near-term**
- Floating status indicator (recording → recognizing → polishing → done)
- Real-time transcription preview overlay
- Audio level visualization
- Model loading progress

**Mid-term**
- Project-aware vocabulary & prompt profiles (per-repo `.talk/` config)
- iCloud vocabulary sync across devices
- iOS companion app with offline on-device inference

**Long-term**
- Multi-language vocabulary management
- Team shared terminology libraries
- Plugin system for custom post-processing pipelines

## License

[MIT](LICENSE)
