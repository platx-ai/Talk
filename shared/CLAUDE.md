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
│   ├── HistoryView.swift        # 历史浏览
│   └── VocabularyView.swift     # 词库管理（导入/导出/手动编辑）
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
- 模型加载必须在后台线程（`Task.detached`），禁止在 `@MainActor` 上做重活
- 模型推理（ChatSession.respond, model.generate）必须在 `@MainActor` 上（MLX 有线程亲和性），但不要用 `Task.detached` 包裹
- UI 更新回到主线程（`@MainActor` 的 property 赋值自动保证）

### 终端输入卡顿防线（两次回归教训，绝不能再犯）

**根本原则：快捷键触发路径上禁止任何阻塞操作。**

已发生过的回归：
1. CGEventTap 挂在主线程 RunLoop → 每次按键创建 Task 淹没主线程
2. captureSelectedText() 的 Cmd+C fallback → Thread.sleep 阻塞 + 终端收到 SIGINT

**硬性规则：**
- CGEventTap 必须在独立后台线程的 RunLoop 上运行，永远不能放在主线程
- CGEventTap 回调中只做轻量比较，不匹配时立即 return，匹配时才 dispatch 到主线程
- `_cachedWasPressed` 去重 — 状态没变化不 dispatch
- 只监听需要的事件类型（修饰键模式只监听 flagsChanged，普通按键模式只监听 keyDown/keyUp）
- `startRecording()` 路径上禁止 `Thread.sleep`、禁止模拟 Cmd+C（终端会 SIGINT）
- 选中文本捕获默认只用 Accessibility API（零阻塞），Cmd+C 方式仅在用户明确选择时使用
- 任何新增的快捷键回调逻辑，必须在终端中实测打字流畅度

## Key Conventions

- Swift 5, macOS 26.2+, Apple Silicon only
- `@Observable` + `@MainActor` for state management
- Singleton pattern for services (ASRService, LLMService, AudioRecorder, etc.)
- UserDefaults for settings persistence, JSON files for history/vocabulary
- CGEventTap for global hotkeys (替代了 Carbon API，后台线程运行)
- CoreAudio for device enumeration, AVAudioEngine for capture
- Models load from HuggingFace cache or app bundle

## Important Notes

- App requires Accessibility permission for text injection (Cmd+V simulation)
- App requires Microphone permission for audio capture
- Metal GPU required (Apple Silicon only, no Intel support)
- Sandboxing is disabled (`com.apple.security.app-sandbox = false`)
- DEVELOPMENT_TEAM is empty — each developer sets their own in Xcode
