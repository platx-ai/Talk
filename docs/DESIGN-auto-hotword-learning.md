# Design: Auto Hotword Learning via Edit Observation

> Feature: 注入文本后被动观察用户编辑，通过 LLM 结构化提取热词修正，自动学习到词库。

## 1. 动机

当前词库学习依赖用户手动在历史界面编辑，摩擦大、使用率低。实际上，用户在目标应用中修改 Talk 注入的文本时，就包含了最有价值的纠正信号 —— 比如把 ASR 误听的 "Cloud Code" 改成 "Claude Code"。

本特性通过被动观察这些编辑行为，自动提取热词修正，形成闭环学习。

**设计原则：启发式，不打断，能抓到就学，抓不到静默放弃。**

## 2. 整体架构

```
用户语音 → ASR（热词 prefix）→ LLM 润色（强制替换规则）→ 注入文本
                                                              │
                                                    ┌────────┘
                                                    ▼
                                          EditObserver 启动
                                          （焦点驱动，后台轮询）
                                                    │
                                          焦点离开 / 文本稳定
                                                    │
                                          收集 (injectedText, editedText)
                                          加入待处理队列
                                                    │
                                          系统空闲时 LLM 提取热词
                                                    │
                                          VocabularyManager.addCorrection()
                                          菜单栏闪电胶囊通知 "已收录 X → Y"（5s）
```

## 3. 模块设计

### 3.1 EditObserver — 焦点驱动的被动观察

新增文件：`Talk/Data/EditObserver.swift`

```swift
/// 观察注入文本后用户的编辑行为
/// 启发式：能检测到就学习，检测不到静默放弃
@Observable
@MainActor
final class EditObserver {
    static let shared = EditObserver()

    /// 待处理的编辑对比队列（等 LLM 空闲时处理）
    private(set) var pendingDiffs: [(original: String, edited: String, timestamp: Date)] = []

    /// 开始观察（注入完成后调用）
    func startObserving(
        injectedText: String,
        targetApp: NSRunningApplication,
        prefixContext: String?
    )

    /// 停止观察（新一轮录音开始时调用）
    func stopObserving()
}
```

#### 观察生命周期

```
注入完成
    │
    ├─ 获取焦点 AXUIElement（AXUIElementCreateApplication + kAXFocusedUIElementAttribute）
    │   └─ 失败 → 静默退出（该应用不支持）
    │
    ├─ 尝试读取 kAXValueAttribute
    │   └─ 失败 → 静默退出
    │
    ├─ 记录 baseline：injectedText + prefixAnchor + 初始控件文本
    │
    ▼
┌──────────── 后台 Task 观察循环 ────────────┐
│                                              │
│  每 500ms 检查：                             │
│                                              │
│  1. 前台应用还是同一个？                      │
│     └─ NO → 停止，触发收集                   │
│                                              │
│  2. 焦点元素还能读取 kAXValueAttribute？      │
│     └─ NO → 停止，触发收集                   │
│                                              │
│  3. 文本有变化？                              │
│     ├─ YES → 记录最新文本，重置去抖计时器     │
│     └─ NO  → 去抖计时器继续                  │
│                                              │
│  4. 去抖计时器达到 1.5s（文本稳定）？         │
│     └─ YES → 触发收集                        │
│                                              │
│  外部停止条件：                               │
│  • stopObserving() 被调用（用户再次录音）     │
│                                              │
└──────────────────────────────────────────────┘
            │
            ▼
       触发收集：
       在控件全文中定位注入区域（锚点匹配）
       提取 editedText → 加入 pendingDiffs 队列
```

#### 注入区域定位策略

```
注入前控件：  "Hello, |"
注入后控件：  "Hello, Cloud Code is great|"

记录：
  injectedText = "Cloud Code is great"
  prefixAnchor = "Hello, "  （注入位置前 ~30 字符）

后续读取到：  "Hello, Claude Code is great"
定位：找到 prefixAnchor "Hello, " → 其后的文本即为注入区域
提取：editedText = "Claude Code is great"

定位失败（锚点找不到、大幅重写） → 放弃该次观察
```

#### 跳过的应用

复用已有的 `isTerminalApp()` 判断 + `axUnsupportedApps` 集合，这些应用直接不启动观察。

### 3.2 LLM 结构化热词提取

新增方法：`LLMService.extractHotwords(original:edited:)`

#### 核心设计：异步队列 + 空闲处理

```
pendingDiffs 队列
    │
    ▼
EditObserver 定期检查（每 5s）：
  LLM 空闲（!isPolishing）且队列非空？
    ├─ YES → 取出一条，调用 extractHotwords()
    └─ NO  → 继续等待
```

**绝对不能干扰前台用户的润色操作。** 热词提取是最低优先级任务。

#### LLM Prompt

```
你是一个热词提取器。给定语音识别的原始输出和用户的修正版本，
提取出属于 ASR 误识别导致的词语修正。

只提取以下类型：
1. 专有名词拼写错误（公司名、产品名、人名、技术术语）
2. ASR 同音字/近音字错误（翔→样）
3. 缩写/术语识别错误（la laam→LLM）

不要提取：
- 语法润色、删减口语词、调整语序
- 标点变化
- 纯粹的措辞偏好改写

返回 JSON 数组，无修正则返回 []：
[{"original": "错误形式", "corrected": "正确形式", "type": "proper_noun|homophone|abbreviation"}]

【原始文本】
{original}

【用户修改后】
{edited}
```

#### 结构化输出解析

```swift
struct HotwordCorrection: Codable {
    let original: String
    let corrected: String
    let type: String  // "proper_noun" | "homophone" | "abbreviation"
}

func extractHotwords(original: String, edited: String) async throws -> [HotwordCorrection] {
    // 使用独立的 ChatSession（不与润色共用，避免污染 KV cache）
    // sessionKey = "__hotword_extraction__"
    // JSON 解析失败 → 返回空数组（静默容错）
}
```

#### 过滤规则

提取结果在写入词库前，额外过滤：
- `original` 和 `corrected` 长度 <= 30 字符（过长的不是热词）
- `original` 和 `corrected` 不完全相同
- `original` 不为空

### 3.3 菜单栏通知 — 闪电胶囊

学到新热词时，在菜单栏弹出一个轻量胶囊通知：

```
 ┌─────────────────────────────────┐
 │ ⚡ 已收录: Cloud Code → Claude Code │
 └─────────────────────────────────┘
       5 秒后自动消失
```

**设计要求：**
- 外观：小胶囊形状，左侧闪电图标，圆角背景
- 位置：菜单栏图标下方弹出（与现有通知位置一致）
- 动画：淡入，5 秒后淡出
- 不可交互（不打断用户）
- 多个修正合并显示（如果一次提取到多个）

复用现有的 `statusBar.showNotification()` 机制或类似实现。

### 3.4 设置开关

在 `AppSettings` 中新增：

```swift
var enableAutoHotwordLearning: Bool = true { didSet { autoSave() } }
```

在设置面板的"高级功能"区域添加开关：
- 标签：自动热词学习 / Auto Hotword Learning
- 说明：注入文本后自动观察编辑，学习 ASR 常错的词汇

## 4. 集成点

### 4.1 TalkApp.swift

```swift
// 注入完成后（~line 719）
try await TextInjector.shared.inject(polishedText)

// ★ 新增：启动编辑观察
if settings.enableAutoHotwordLearning,
   settings.outputMethod == .autoPaste,
   let target = self.targetApp {
    EditObserver.shared.startObserving(
        injectedText: polishedText,
        targetApp: target,
        prefixContext: nil  // TODO: 注入前读取光标前文本作为锚点
    )
}

// 录音开始时
func startRecording() {
    EditObserver.shared.stopObserving()  // ★ 停止上一次观察
    // ... existing code
}
```

### 4.2 LLMService.swift

新增 `extractHotwords()` 方法，使用独立 session key `"__hotword_extraction__"`。

### 4.3 VocabularyManager.swift

复用现有 `addCorrection(original:corrected:)` 方法，无需修改。

### 4.4 菜单栏 UI

在 `LocalTypeMenuBar` 或 `MenuBarView` 中添加闪电胶囊通知视图。

## 5. 数据流总结

```
┌─────────────────────────────────────────────────────────────────────┐
│ 前台（实时，不可阻塞）                                                │
│                                                                     │
│  语音 → ASR → LLM润色 → 注入 → EditObserver.startObserving()       │
│                                    │                                │
│                              AX 轮询（500ms）                       │
│                              焦点驱动，去抖 1.5s                    │
│                                    │                                │
│                              收集 (original, edited)                │
│                              加入 pendingDiffs 队列                 │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ 后台（空闲时，最低优先级）                                            │
│                                                                     │
│  pendingDiffs 队列                                                  │
│       │                                                             │
│       ▼                                                             │
│  LLM 空闲？ ─── NO ──→ 继续等待                                    │
│       │                                                             │
│      YES                                                            │
│       │                                                             │
│       ▼                                                             │
│  extractHotwords() → JSON 解析 → 过滤                               │
│       │                                                             │
│       ▼                                                             │
│  VocabularyManager.addCorrection()                                  │
│  闪电胶囊通知 ⚡                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 6. 边界条件

| 情况 | 处理 |
|------|------|
| 应用不支持 kAXValueAttribute | 静默退出 |
| 终端类应用 | 跳过（isTerminalApp） |
| 用户连续录音 | stopObserving() 取消上一次 |
| 控件文本 > 10K 字符 | 只读局部 / 放弃 |
| LLM 长时间繁忙 | 队列积压超过 10 条时丢弃最旧的 |
| JSON 解析失败 | 返回空数组，静默 |
| 锚点定位失败 | 放弃该次 |
| 用户没有编辑 | baseline == current → 不入队 |
| 功能开关关闭 | 不启动观察 |

## 7. ASR 热词 Prefix 注入（已实现）

在 `platx-ai/mlx-audio-swift` fork 的 `feat/asr-initial-prompt` 分支中，给 Qwen3ASR 添加了 `initialPrompt` 参数。

### 关键实验发现

热词注入位置对结果影响巨大：

| 注入位置 | 效果 |
|---------|------|
| ❌ `<asr_text>` 之后（decoder prefix） | 破坏解码，输出为空或乱码 |
| ✅ system prompt 区域 | 正常工作，不干扰生成 |

最终方案：将 `"The following terms may appear in the audio: {hotwords}"` 放入 system message。

### 实验数据

| 测试用例 | Baseline | With Hotwords |
|---------|----------|---------------|
| EN: "Claude Code" | ✅ Claude Code | ✅ Claude Code |
| EN: "Anthropic" + "Claude" | ✅ 2/2 | ✅ 2/2 |
| EN: LLM/MLX/Apple Silicon | ✅ 4/4 | ✅ 4/4 |
| **ZH: "Claude Code"** | ❌ "Claud Code" | ✅ **"Claude Code"** |
| **Total** | **8/9** | **9/9** |

### 改动文件（mlx-audio-swift fork）

- `Generation.swift` — `STTGenerateParameters.initialPrompt`
- `Qwen3ASR.swift` — `buildPrompt()` 在 system 区域注入热词
- `StreamingTypes.swift` — `StreamingConfig.initialPrompt`
- `StreamingInferenceSession.swift` — 传递 initialPrompt

### Talk 侧集成

- `ASRService.buildHotwordPrompt()` — 从词库高频纠正条目提取正确形式
- `ASRService.transcribe()` — 自动传递 hotword prompt
- `ASRService.startStreaming()` — StreamingConfig 中传递 initialPrompt

## 8. 未来增强

### LLM Prompt 强化（4b）

将现有词库 prompt 从"建议"升级为"强制规则"：

```
当前（弱）：【已学习的纠正】Cloud Code → Claude Code
改进（强）：【强制替换规则】以下是用户确认的 ASR 纠正，必须执行替换...
```

## 9. 实现状态

### Phase 1: 基础设施 ✅
- [x] `EditObserver` 模块（AX 轮询 + 焦点驱动 + 去抖）
- [x] `AppSettings.enableAutoHotwordLearning` 开关
- [x] 设置 UI 开关 + i18n

### Phase 2: LLM 提取 ✅
- [x] `LLMService.extractHotwords()` 方法（独立 session + JSON prompt）
- [x] 后台队列处理逻辑（空闲检测 + 最低优先级）
- [x] JSON 解析 + 过滤

### Phase 3: 集成与通知 ✅
- [x] TalkApp 注入后 → startObserving() 集成
- [x] 闪电胶囊通知 UI（⚡ 5 秒淡出）
- [x] 端到端测试（ASRHotwordTests + 4 个 TTS 测试音频）

### Phase 4: ASR 热词 Prefix ✅
- [x] mlx-audio-swift fork `initialPrompt` 支持
- [x] ASRService 热词传递
- [x] 端到端对比测试（Baseline 8/9 → Hotword 9/9）

### 待做
- [ ] 推送 mlx-audio-swift fork 分支 + 更新 Talk SPM pin
- [ ] LLM prompt 强化为强制规则
- [ ] 更多真实语音测试音频（非 TTS 合成）
