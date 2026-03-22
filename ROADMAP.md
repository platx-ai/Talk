# Talk Roadmap

## v0.2 — Visual Feedback & Polish *(complete)*

> Make the invisible visible. Users must know what Talk is doing at every moment.

### P0: Critical Fixes — All Done

- [x] Remove personal info leaks (xcuserdata, executable path)
- [x] Floating status indicator (recording → recognizing → polishing → done)
- [x] Settings persistence — singleton with auto-save, no more data loss
- [x] CGEventTap hotkey system — replaces Carbon API, supports all key combos
- [x] CGEventTap on background thread — no input lag in Terminal

### P1: Core UX — All Done

- [x] Audio level visualization (real-time RMS meter)
- [x] Recording duration timer
- [x] Editable LLM system prompt (4 presets + custom)
- [x] Selection edit mode (select text → speak command → LLM executes)
- [x] Model loading indicator ("加载模型中...")

### P1: Remaining

- [ ] **Real-time transcription preview**
  - Live text overlay showing ASR output as the user speaks
  - Setting `showRealtimeRecognition` already exists — needs UI implementation
  - Blocked by: first-hotkey-press latency investigation

- [x] **ASR error feedback loop**
  - User edits polished text in history → system learns correction mapping
  - Word-level LCS diff extracts changed words (e.g., "la laam" → "LLM")
  - Top-20 corrections injected as LLM context for future polishing

---

## v0.2.1 — Performance & Stability

> The bottleneck is LLM load time (10s) and memory (9.6 GB). Inference is fast once loaded.

- [x] **First-hotkey-press latency fix**
  - Root cause: captureSelectedText() Cmd+C fallback blocked main thread 17+ seconds
  - Fix: use only Accessibility API in hot path, no blocking fallback

- [ ] **Remaining first-press warmup**
  - Still ~1-2s delay on very first hotkey press (likely Metal/audio engine warmup)
  - Need to profile further; not a regression, but room for improvement

- [x] **Idle model unload**
  - Unload models after N minutes of inactivity (default 10 min, configurable)
  - Lazy reload on next hotkey press (with "加载模型中..." indicator)
  - Toggle and timeout in Settings → Advanced → 内存管理

- [ ] **Custom lightweight polish model (platx-ai/talk-polish)**
  - Train a purpose-built small model (0.5B-1.5B) specifically for text polishing
  - Single-task model: no general chat capability, only ASR output cleanup
  - Target: < 1s load, < 0.5s inference, < 1 GB memory
  - Training data: ASR output → clean text pairs from real Talk usage
  - MLX-native quantization (4-bit) for Apple Silicon

- [ ] **Model auto-select by hardware**
  - 8 GB Mac → talk-polish (lightweight)
  - 16 GB+ Mac → Qwen3-4B (full)
  - User can override in settings

---

## v0.2.2 — App-Aware Prompts

> The simplest context-awareness: different apps get different prompts. Zero config, immediate value.

When the user records in different apps, Talk automatically uses app-specific polish prompts. This is simpler and more practical than project-directory-based profiles.

- [ ] **Per-app prompt profiles**
  - Detect frontmost app (Bundle ID) when recording starts (already captured as `targetApp`)
  - Settings UI: list of app → custom prompt mappings
  - Example presets:
    - Terminal/iTerm2: "保留命令行语法和技术术语，代码标识符不要修改"
    - Slack/WeChat: "口语化，简洁，适合即时通讯"
    - Mail/Outlook: "正式语气，添加问候和结尾"
    - Xcode/VSCode: "保留代码变量名和函数名，技术文档风格"
    - Notes/Bear: "结构化笔记格式，使用标题和列表"
  - Fallback to global prompt when no app-specific prompt is set

- [ ] **App prompt auto-suggestion**
  - First time recording in a new app, suggest creating an app-specific prompt
  - Learn from usage patterns which apps benefit most from custom prompts

- [ ] **Vocabulary management UI**
  - View, add, edit, delete vocabulary entries
  - Import/export vocabulary as JSON
  - Shows learned corrections and their frequencies

---

## v0.3 — Project-Aware Profiles

> Different projects need different vocabularies and prompts. Talk should adapt to the project you're working in.

### `.talk/` Project Configuration

Each project directory can contain a `.talk/` folder with project-specific settings:

```
my-project/
├── .talk/
│   ├── config.md          # Project description & context for LLM
│   ├── vocabulary.json    # Domain-specific terms and corrections
│   └── prompt.md          # Custom polish prompt override
├── src/
└── ...
```

- [ ] **Auto-detect project context**
  - When recording starts, detect the frontmost app's working directory
  - Load `.talk/config.md` as additional LLM context
  - Merge `vocabulary.json` with global vocabulary

- [ ] **Project vocabulary**
  - Terms like "Kubernetes" → not "Q8S"
  - Abbreviations: "k8s" → "Kubernetes", "PR" → "Pull Request"
  - Per-project terminology: code identifiers, product names, team jargon

- [ ] **Custom polish prompts per project**
  - Engineering projects: preserve code identifiers, format as technical docs
  - Meeting notes: bullet points, action items, attendee names
  - Creative writing: preserve tone, minimal edits

- [ ] **Profile switching**
  - Quick-switch between project profiles from menu bar
  - Auto-switch based on active directory / app

---

## v0.4 — Cross-Device Sync

> Your vocabulary and settings should follow you everywhere.

- [ ] **iCloud vocabulary sync**
  - Global vocabulary synced via iCloud Drive / CloudKit
  - Merge strategy for concurrent edits

- [ ] **iOS companion app**
  - Offline on-device inference using CoreML / MLX for iOS
  - Shared vocabulary with macOS via iCloud
  - Keyboard extension for system-wide voice input
  - Optimized models for iPhone/iPad (smaller quantization)

- [ ] **Settings sync**
  - Polish intensity, language preferences, trigger mode
  - Per-device overrides (different hotkey on different Mac)

---

## v0.5 — Team Collaboration

> From personal tool to team infrastructure.

- [ ] **Shared terminology libraries**
  - Team-managed vocabulary packages (Git-based or hosted)
  - Version-controlled term definitions

- [ ] **Multi-language vocabulary**
  - Per-language term mappings
  - Code-switching support (mixed Chinese/English in one utterance)

- [ ] **Plugin system**
  - Custom post-processing pipelines
  - Hooks: `afterASR`, `afterPolish`, `beforeInject`
  - Use cases: auto-translation, summary, formatting rules, Slack/Notion integration

---

## Non-Goals (Explicit)

- **Cloud-based inference** — Talk is local-first. Cloud is not a fallback, it's a different product.
- **Real-time translation** — Polishing is not translating. Translation is a separate workflow.
- **Voice commands / app control** — Talk types for you. It doesn't click for you.
- **Windows/Linux support** — macOS + iOS only. MLX is Apple Silicon native.
