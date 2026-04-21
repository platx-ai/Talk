# Talk — Development Guide

## Build & Run

```bash
git clone https://github.com/platx-ai/Talk.git && cd Talk

# Full setup: resolve dependencies + download models
make setup

# Run
make run
```

### Make targets

```bash
make build          # Debug build
make build-release  # Release build
make test           # Unit tests (excludes benchmarks)
make benchmark      # Performance benchmarks (requires models)
make run            # Build and run
make clean          # Clean build artifacts
make resolve        # Resolve SPM dependencies
make download-models # Download ML models from HuggingFace
make setup          # Full setup: resolve + download models
```

## Architecture

```
Record(AVAudioEngine) → ASR(Qwen3-ASR) → LLM Polish(Qwen3-4B) → Text Inject(Cmd+V)
       ↑                  0.1s               0.5s                     ↑
    CoreAudio                                                    Accessibility
  Device Selection                                                API Permission
```

```
Talk/
├── TalkApp.swift          # App entry, AppDelegate, lifecycle
├── Audio/                 # Audio layer
│   ├── AudioRecorder.swift      # AVAudioEngine recording + device selection
│   ├── AudioDeviceManager.swift # CoreAudio device enumeration/monitoring
│   ├── HotKeyManager.swift      # Global hotkey (CGEventTap, background thread)
│   └── TextInjector.swift       # Text injection (Accessibility API)
├── ASR/                   # Speech recognition
│   └── ASRService.swift         # Qwen3-ASR / Apple Speech / Gemma 4
├── LLM/                   # Text polishing
│   └── LLMService.swift         # Qwen3.5 / Gemma 4 via MLXLLM
├── Models/                # Data models
│   ├── AppSettings.swift        # Settings + enums (ASREngine, LLMEngine, etc.)
│   ├── HistoryItem.swift        # History records
│   └── VocabularyItem.swift     # Personal vocabulary
├── Data/                  # Persistence
│   ├── HistoryManager.swift     # History (JSON + M4A audio)
│   └── VocabularyManager.swift  # Vocabulary management
├── UI/                    # Interface
│   ├── SettingsView.swift       # Settings panel (7 tabs)
│   ├── KeyRecorderView.swift    # Hotkey recorder component
│   ├── MenuBarView.swift        # Menu bar dropdown (SwiftUI Menu)
│   ├── LocalTypeMenuBar.swift   # Menu bar controller (NSStatusItem)
│   ├── HistoryView.swift        # History browser
│   └── VocabularyView.swift     # Vocabulary management
└── Utils/                 # Utilities
    ├── Logger.swift             # Logging system
    └── MLXRuntimeValidator.swift # Metal runtime check
```

## Dependencies

All via Swift Package Manager, pinned to specific commits:

| Package | Source | Purpose |
|---------|--------|---------|
| mlx-swift | [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | MLX core array operations |
| mlx-swift-lm | [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | LLM inference framework |
| mlx-audio-swift | [platx-ai/mlx-audio-swift](https://github.com/platx-ai/mlx-audio-swift) (fork) | Audio STT framework |
| swift-huggingface | [huggingface/swift-huggingface](https://github.com/huggingface/swift-huggingface) | Model downloading |

> mlx-audio-swift uses the platx-ai fork because upstream MLXAudioCodecs is missing the MLXFast dependency.

## Testing

```bash
make test       # Unit tests
make benchmark  # Performance benchmarks
```

### Testing rules

- Swift Testing framework (`@Test`, `#expect`, `Issue.record`), not XCTest
- `@MainActor` for UI components and Singleton access
- All new features require tests; bugs require regression tests first
- Benchmark tests go in `TalkTests/BenchmarkTests.swift`
- Singleton tests must isolate state (save/restore)

### Performance constraints

- Model loading: background thread (`Task.detached`), never on `@MainActor`
- Model inference: on `@MainActor` (MLX thread affinity), never wrapped in `Task.detached`
- UI updates: `@MainActor` property assignment

### Hotkey regressions (historical lessons)

- CGEventTap must run on a dedicated background thread's RunLoop, never main thread
- CGEventTap callback: lightweight comparison only, dispatch to main on match
- `startRecording()` path: no `Thread.sleep`, no simulated Cmd+C
- Selected text capture: Accessibility API by default (zero blocking)

## Code Signing

`DEVELOPMENT_TEAM` is empty in the project. Each developer sets their own in Xcode → Signing & Capabilities. CLI builds use ad-hoc signing.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full product roadmap.
