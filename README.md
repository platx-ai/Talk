<p align="center">
  <img src="docs/assets/icon_512.png" width="128" height="128" alt="Talk icon">
</p>

<h1 align="center">Talk</h1>

<p align="center"><strong>Open Typeless. Local Typeless. Typeless in your box.</strong></p>

<p align="center">macOS menu bar voice input — hold a hotkey, speak, and your words are recognized, polished, and pasted into the active app. No cloud. No typing.</p>

<p align="center">
  <a href="https://github.com/platx-ai/Talk/releases/latest">
    <img src="https://img.shields.io/github/v/release/platx-ai/Talk?label=Download&color=blue" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%20%2B%20Apple%20Silicon-black" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

[**Download latest Talk**](https://github.com/platx-ai/Talk/releases/latest) · [中文文档](README_zh.md) · [开发文档](DEV.md)

## Features

- **On-device inference** — Apple Silicon + MLX, no cloud, no network after model download
- **Three ASR engines** — MLX local (Qwen3-ASR), Apple Speech Recognition, or Gemma 4 multimodal
- **Text polishing** — Qwen3.5-4B or Gemma 4, removes filler words, adds punctuation, smart formatting
- **One-pass mode** — Set both ASR and LLM to Gemma 4 for single-model speech-to-polished-text
- **Auto hotword learning** — Passively observes your edits, learns ASR corrections via LLM extraction
- **Selection edit mode** — Select text, speak a command ("fix the typo", "make it casual")
- **Per-app prompt profiles** — Different polish styles for Terminal, VSCode, WeChat, etc.
- **Audio history** — Every recording saved as AAC/M4A with ASR context for replay and debugging
- **Usage statistics** — Daily session count, recording duration, error rate, 7-day chart, 90-day retention
- **Real-time preview** — Streaming ASR shows partial transcription as you speak
- **Floating status indicator** — Always-on-top overlay with audio level meter
- **Customizable hotkey** — Key recorder, Push-to-Talk / Toggle modes
- **Output options** — Auto-paste, clipboard-only, or preview window

## Quick Start

1. **Download** [latest release](https://github.com/platx-ai/Talk/releases/latest) (DMG)
2. **Open** the DMG, drag Talk to `/Applications`
3. **Launch** — macOS will prompt for permissions:
   - **Microphone** — for recording
   - **Input Monitoring** — for global hotkey (System Settings → Privacy & Security)
   - **Accessibility** — for auto-pasting text (System Settings → Privacy & Security)
4. **Hold your hotkey** (default `Fn+A`), speak, release — text appears in the active app

Models (~3 GB) download automatically from HuggingFace on first use. Pre-download with `make download-models` if building from source.

## Performance

All inference on-device via Apple Silicon GPU. No network required after model download.

| Stage | Latency | Notes |
|-------|---------|-------|
| ASR (3-5s audio) | **0.07 - 0.18s** | 17-51× faster than real-time |
| LLM polish (short) | **0.35 - 0.50s** | ~30 chars input |
| LLM polish (long) | **1.1 - 1.2s** | ~120 chars input |
| **Full pipeline** | **~1s** | ASR + LLM combined (models warm) |
| ASR model load | 2s | Cold start, one-time |
| LLM model load | 0.6s | Cold start, one-time |

Memory usage:

| State | RSS |
|-------|-----|
| ASR model loaded | ~1.6 GB |
| Both models loaded | ~5.4 GB |

> Full benchmark details: [docs/BENCHMARK.md](docs/BENCHMARK.md)

## Compatibility

| | Supported | Notes |
|---|-----------|-------|
| macOS 26.x (Tahoe) | ✅ | Built & tested |
| macOS 15.x (Sequoia) | Likely | MLX dependencies support macOS 14+ |
| macOS 14.x (Sonoma) | Maybe | Minimum for MLX |
| macOS 13 and below | No | MLX requires macOS 14+ |
| Intel Mac | No | MLX is Apple Silicon only |

## Requirements

- Apple Silicon (M1/M2/M3/M4)
- macOS 14.0+ (Sonoma minimum; pre-built DMG targets macOS 26.2+)
- 16 GB RAM recommended
- ~3 GB disk space for model files

## Models

| Model | Size | Purpose |
|-------|------|---------|
| [Qwen3-ASR-0.6B-4bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit) | ~400 MB | Speech recognition (MLX) |
| [Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) | ~2.8 GB | Text polishing (default LLM) |
| [Gemma 4 4B](https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit) | — | Multimodal: ASR + LLM in one model |
| [Gemma 4 2B](https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit) | — | Lightweight multimodal option |

Models auto-download from HuggingFace to `~/.cache/huggingface/`.

## Permissions

On first launch, grant these in **System Settings → Privacy & Security**:

1. **Microphone** — Required for recording. macOS prompts automatically.
2. **Input Monitoring** — Required for global hotkey.
3. **Accessibility** — Required for auto-pasting text into other apps.

If the hotkey doesn't respond, check **Input Monitoring** first. Quit and relaunch Talk after enabling.

## Vocabulary & Auto Learning

Talk learns from your corrections in two ways:

**Passive edit observation** — After text injection, Talk monitors the text field. If you edit (e.g., fix a misrecognized word), it detects the change and extracts corrections via a background LLM pass. A ⚡ capsule confirms when new corrections are learned.

**Manual** — Edit polished text in history view, or add entries in Settings → Personal Vocabulary → Manage Vocabulary. Supports JSON import/export.

Top corrections are injected into the LLM system prompt and applied automatically in future sessions.

## License

[MIT](LICENSE)
