# Talk 项目代码审查结论（2026-03-29）

本文档汇总本次全仓 code review 的主要发现，按严重级别排序。

## High

### 1. 录音启动路径包含阻塞与 Cmd+C 自动回退，违反项目硬性约束
- 文件：`Talk/TalkApp.swift`
- 位置：约 636, 640, 657, 696, 708 行
- 证据：`captureSelectedText()` 会在 AX 失败后自动回退 `captureSelectedTextViaClipboard()`；`captureSelectedTextViaClipboard()` 使用 `Thread.sleep(forTimeInterval: 0.1)`。
- 关联规范：`AGENTS.md` 明确要求 `startRecording()` 路径禁止 `Thread.sleep`、禁止默认模拟 Cmd+C，Cmd+C 仅在用户明确选择时允许。
- 影响：可能引入终端输入卡顿、SIGINT 风险和主线程阻塞。
- 建议：默认仅走 Accessibility；Cmd+C 改为显式用户配置；移除主线程 sleep。

### 2. AudioRecorder 引擎重启会清空回调且未恢复，流式链路可能静默失效
- 文件：`Talk/Audio/AudioRecorder.swift`
- 位置：约 231-232, 318-319, 250, 334 行
- 证据：在配置变更和 watchdog 重启路径中将 `onAudioData` / `onAudioLevel` 置空，重启成功后未恢复。
- 影响：设备切换后实时识别和音量更新可能停止。
- 建议：重启前保存并在重启成功后恢复回调；或让重启逻辑不触碰业务回调。

### 3. ASR 流式监听任务无句柄管理，stopStreaming 无法主动取消
- 文件：`Talk/ASR/ASRService.swift`
- 位置：约 163, 166, 219, 225 行
- 证据：`Task { for await event in session.events { ... } }` 未持有 `Task` 引用；`stopStreaming()` 仅将 `streamingSession = nil`。
- 影响：旧事件监听任务可能残留，导致资源占用与时序混乱。
- 建议：引入 `streamingTask`，在 `startStreaming` 赋值，在 `stopStreaming` 中 `cancel()` 并置空。

## Medium

### 4. ASR/LLM 并发加载等待分支可能吞掉首次失败结果
- 文件：`Talk/ASR/ASRService.swift`、`Talk/LLM/LLMService.swift`
- 位置：约 76, 104 行
- 证据：`while isLoading { sleep }` 等待后直接 `return`，无法向等待者传播首次加载失败。
- 影响：调用方可能误判为“加载完成”，错误延迟暴露。
- 建议：使用共享 `Task` 或 continuation 传递同一加载结果（含失败）。

### 5. HotKeyManager 使用 nonisolated(unsafe) 共享状态，存在竞争窗口
- 文件：`Talk/Audio/HotKeyManager.swift`
- 位置：约 59-62, 140, 155 行
- 证据：CGEventTap 线程与主线程共享 `_cachedWasPressed` 等字段，无原子/锁保护。
- 影响：极端情况下可能重复触发或状态抖动。
- 建议：对共享字段加锁/原子化；或抽离线程安全状态容器。

### 6. AppSettings.resetToDefaults 重置语义不完整
- 文件：`Talk/Models/AppSettings.swift`
- 位置：约 509-510 行
- 证据：删除的是 `userDefaultsKey`（`"AppSettings"`），但实际设置字段分散存储在多个 key。
- 影响：重置后可能残留旧配置。
- 建议：显式删除所有已使用 key，或统一命名空间存储。

### 7. 主线程同步持久化可能带来 UI 抖动
- 文件：`Talk/Models/AppSettings.swift`、`Talk/Data/HistoryManager.swift`、`Talk/Data/VocabularyManager.swift`
- 位置：`autoSave()` 与 `saveHistory()`/`saveVocabulary()`
- 证据：高频 `didSet -> autoSave` 与同步文件写入。
- 影响：频繁设置变更或大数据量时可能卡顿。
- 建议：去抖动写入、后台异步落盘。

## 测试覆盖缺口

1. 未见覆盖“录音启动路径中的选中文本回退策略 + 阻塞行为”回归测试。
2. 未见覆盖 AudioRecorder 引擎重启后回调恢复语义。
3. ASR 测试未覆盖并发 `loadModel` 失败传播与流式任务取消生命周期。
4. AppSettings reset 测试未能检出“分散 key 未清理”的问题。

## 审查范围说明

- 已审查：`Talk/`、`TalkTests/` 下主要 Swift 源文件及关键规范文件。
- 自动化信号：Problems 面板未发现现有静态错误。
- 测试执行：尝试 `make test`，但受外部网络影响，SPM 依赖拉取失败（无法连接 GitHub），未完成完整测试回归。
