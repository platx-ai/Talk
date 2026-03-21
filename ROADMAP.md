# Talk Roadmap

## v0.2 — Visual Feedback & Polish *(in progress)*

> Make the invisible visible. Users must know what Talk is doing at every moment.

### P0: Critical Fixes

- [x] **Remove personal info leaks**
  - Remove committed `xcuserdata/` directory
  - Sanitize executable path in Accessibility permission dialog
  - Add `xcuserdata/` to `.gitignore`

- [x] **Floating status indicator**
  - Transparent NSPanel overlay at screen top-center
  - States: 🎙 Recording (with timer + audio level) → 🔄 Recognizing → ✨ Polishing → 📤 Outputting → ✅ Done
  - Auto-dismiss after 1.5s
  - Visible in full-screen apps and across all spaces

### P1: Core UX

- [x] **Audio level visualization**
  - Real-time RMS level meter in the floating indicator
  - Green (normal) / yellow (loud) color coding

- [x] **Recording duration timer**
  - Elapsed time displayed in the floating indicator

- [x] **Editable LLM system prompt**
  - 4 preset templates (strict correction, light polish, meeting notes, tech docs)
  - Custom prompt overrides polish intensity
  - "Reset to default" button

- [x] **Selection edit mode**
  - Select text + speak voice command = LLM executes the instruction
  - Supports: typo correction, style rewrite, formatting changes
  - Dual capture: Accessibility API (default) with Cmd+C fallback

- [x] **Model loading progress**
  - Floating indicator shows "加载模型中..." when models are loading
  - Prevents user confusion during first-time model download

- [ ] **Real-time transcription preview**
  - Live text overlay showing ASR output as the user speaks
  - Setting `showRealtimeRecognition` already exists — needs UI implementation

- [ ] **ASR error feedback loop**
  - User corrects a mis-recognized word → system learns the mapping (e.g., "la laam" → "LLM")
  - Corrections stored in vocabulary, injected as LLM context for future polishing
  - History view: edit polished text → system auto-learns from correction
  - First-launch experience: show download/loading progress in floating indicator
  - Prevent users from thinking the app is frozen

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

- [ ] **Custom polish prompts**
  - Engineering projects: preserve code identifiers, format as technical docs
  - Meeting notes: bullet points, action items, attendee names
  - Creative writing: preserve tone, minimal edits
  - Email drafts: formal tone, greeting/closing conventions

- [ ] **Profile switching**
  - Quick-switch between project profiles from menu bar
  - Auto-switch based on active directory / app

---

## v0.4 — Cross-Device Sync

> Your vocabulary and settings should follow you everywhere.

- [ ] **iCloud vocabulary sync**
  - Global vocabulary synced via iCloud Drive / CloudKit
  - Merge strategy for concurrent edits
  - Sync history (optional, privacy-aware)

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
  - `npm`-style install: `talk vocab add @company/engineering-terms`
  - Version-controlled term definitions

- [ ] **Multi-language vocabulary**
  - Per-language term mappings
  - Code-switching support (mixed Chinese/English in one utterance)

- [ ] **Plugin system**
  - Custom post-processing pipelines
  - Hooks: `afterASR`, `afterPolish`, `beforeInject`
  - Use cases: auto-translation, summary, formatting rules, Slack/Notion integration

- [ ] **Analytics dashboard**
  - Usage stats: words per day, accuracy trends, most-corrected terms
  - Vocabulary learning insights

---

## Non-Goals (Explicit)

- **Cloud-based inference** — Talk is local-first. Cloud is not a fallback, it's a different product.
- **Real-time translation** — Polishing is not translating. Translation is a separate workflow.
- **Voice commands / app control** — Talk types for you. It doesn't click for you.
- **Windows/Linux support** — macOS + iOS only. MLX is Apple Silicon native.
