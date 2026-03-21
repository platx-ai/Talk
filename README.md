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

## Requirements

- macOS 26.2+
- Apple Silicon (M1/M2/M3/M4)
- Xcode 26.3+
- 16 GB RAM recommended (8 GB works with lightweight model — coming soon)
- ~3 GB disk space (model files)

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
make test           # Run unit tests (35 tests)
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
| `Audio/` | Recording engine, global hotkeys (Carbon API), audio device management, text injection |
| `ASR/` | Speech recognition (MLXAudioSTT + Qwen3-ASR) |
| `LLM/` | Text polishing (MLXLLM + Qwen3-4B-Instruct) |
| `Models/` | Data models (AppSettings, HotKeyCombo, HistoryItem) |
| `Data/` | History and vocabulary JSON persistence |
| `UI/` | SwiftUI menu bar, settings panel, key recorder, floating indicator, history browser |
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

### Testing

```bash
make test       # 35 unit tests (HotKeyCombo, AppSettings, AudioDeviceManager, FloatingIndicator)
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
- ASR error feedback loop (user corrections → vocabulary learning)

**Mid-term**
- Project-aware vocabulary & prompt profiles (per-repo `.talk/` config)
- iCloud vocabulary sync across devices
- iOS companion app with offline on-device inference

**Long-term**
- Team shared terminology libraries
- Plugin system for custom post-processing pipelines

## License

[MIT](LICENSE)
