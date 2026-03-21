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
make test           # 运行单元测试（不含 benchmark）
make benchmark      # 运行性能基准测试（需要模型）
make run            # 构建并运行
make clean          # 清理构建产物
make resolve        # 解析 SPM 依赖
```

## Testing Rules

### 必须写测试的场景
- 所有新增功能必须有对应的单元测试
- 发现的 bug 必须先写**回归测试复现问题**，再修复
- 性能问题用 benchmark 测试量化（`TalkTests/BenchmarkTests.swift`）

### 测试文件组织
- `TalkTests/` 目录下，按模块命名：`HotKeyComboTests.swift`, `AppSettingsTests.swift` 等
- Benchmark 测试放在 `BenchmarkTests.swift`，用 `@Suite("ASR Benchmarks")` 等分组
- `make test` 跳过 benchmark，`make benchmark` 只跑 benchmark

### 测试编写规范
- 使用 Swift Testing 框架（`@Test`, `#expect`, `Issue.record`），不用 XCTest
- `@MainActor` 标记需要主线程的测试（UI 组件、Singleton 访问）
- Singleton 测试要注意状态隔离 — 保存/恢复之前的状态
- 不要在测试中修改全局 UserDefaults 不清理

### 如何发现和验证问题
1. **用户反馈 → 回归测试**：用户报告"卡在润色中" → 写测试验证推理不阻塞主线程
2. **Benchmark 发现瓶颈**：`make benchmark` 量化每个阶段耗时，写入 `docs/BENCHMARK.md`
3. **性能回归检测**：benchmark 结果对比历史数据，发现回归

### 性能关键约束
- 模型加载和推理必须在后台线程（`Task.detached`），禁止在 `@MainActor` 上做重活
- UI 更新回到主线程（`@MainActor` 的 property 赋值自动保证）

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
