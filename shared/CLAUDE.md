# Talk - Project Guidelines

## What is Talk

Talk 是一个 macOS 菜单栏语音输入工具，使用本地 MLX 模型实现：录音 → ASR 语音识别 → LLM 文本润色 → 自动粘贴到当前应用。

## Architecture

```
Talk/
├── TalkApp.swift          # App entry, AppDelegate, lifecycle
├── Audio/                 # 音频层
│   ├── AudioRecorder.swift      # AVAudioEngine 录音 + 设备选择
│   ├── AudioDeviceManager.swift # CoreAudio 设备枚举/监听
│   ├── HotKeyManager.swift      # 全局热键 (Carbon API)
│   └── TextInjector.swift       # 文本注入 (Accessibility API)
├── ASR/                   # 语音识别
│   └── ASRService.swift         # Qwen3-ASR via MLXAudioSTT
├── LLM/                   # 文本润色
│   └── LLMService.swift         # Qwen3-LLM via MLXLLM
├── Models/                # 数据模型
│   ├── AppSettings.swift        # 设置 + HotKeyCombo
│   ├── HistoryItem.swift        # 历史记录
│   └── VocabularyItem.swift     # 个人词库
├── Data/                  # 数据持久化
│   ├── HistoryManager.swift     # 历史管理
│   └── VocabularyManager.swift  # 词库管理
├── UI/                    # 界面
│   ├── SettingsView.swift       # 设置面板 (5 tabs)
│   ├── KeyRecorderView.swift    # 快捷键录制组件
│   ├── MenuBarView.swift        # 菜单栏弹出视图
│   ├── LocalTypeMenuBar.swift   # 菜单栏控制器
│   └── HistoryView.swift        # 历史浏览
└── Utils/                 # 工具
    ├── Logger.swift             # 日志系统
    └── MLXRuntimeValidator.swift # Metal 运行时检查
```

## Dependencies

通过 Swift Package Manager 远程引用，pin 到具体 commit：

| Package | Source | Purpose |
|---------|--------|---------|
| mlx-swift | ml-explore/mlx-swift | MLX 核心运算 |
| mlx-swift-lm | ml-explore/mlx-swift-lm | LLM 推理 |
| mlx-audio-swift | platx-ai/mlx-audio-swift (fork) | 语音识别 |
| swift-huggingface | huggingface/swift-huggingface | 模型下载 |

> mlx-audio-swift 使用 platx-ai fork，因为上游 MLXAudioCodecs 缺少 MLXFast 依赖。

## Working Principles

- **First Principles + Occam's Razor**: 设计决策先问"这个机制到底在解决什么问题？"，如果问题不存在就删掉设计。删比修优先。
- **Test-Driven Changes**: 代码变更必须有对应测试。
- **Doc-First Changes**: 功能变更前先同步文档。
- **No Hidden Side Effects**: 测试中使用显式依赖注入。

## Build & Test

```bash
make build          # 构建 Debug 版本
make build-release  # 构建 Release 版本
make test           # 运行测试
make run            # 构建并运行
make clean          # 清理构建产物
make resolve        # 解析 SPM 依赖
```

## Key Conventions

- Swift 5, macOS 26.2+, Apple Silicon only
- `@Observable` + `@MainActor` for state management
- Singleton pattern for services (ASRService, LLMService, AudioRecorder, etc.)
- UserDefaults for settings persistence, JSON files for history/vocabulary
- Carbon API for global hotkeys (no macOS alternative)
- CoreAudio for device enumeration, AVAudioEngine for capture
- Models load from HuggingFace cache or app bundle

## Important Notes

- App requires Accessibility permission for text injection (Cmd+V simulation)
- App requires Microphone permission for audio capture
- Metal GPU required (Apple Silicon only, no Intel support)
- Sandboxing is disabled (`com.apple.security.app-sandbox = false`)
- DEVELOPMENT_TEAM is empty — each developer sets their own in Xcode
