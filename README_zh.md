<p align="center">
  <img src="docs/assets/icon_512.png" width="128" height="128" alt="Talk icon">
</p>

<h1 align="center">Talk</h1>

<p align="center"><strong>Open Typeless. Local Typeless. Typeless in your box.</strong></p>

macOS 菜单栏语音输入工具 — 按住快捷键说话，自动识别、润色、粘贴到当前应用。你的声音，直达文字，无需云端，无需打字。

[**下载 Talk v0.4.0**](https://github.com/platx-ai/Talk/releases/latest) · [English](README.md)

> 本项目的原始算法和代码基于孔老师（[@jiamingkong](https://github.com/jiamingkong)）的慷慨贡献。我们只是想快速验证一下十分钟能不能搞定一个 typeless。

## 功能

- **本地推理** — 基于 Apple Silicon MLX，无云端依赖，隐私优先
- **双引擎语音识别** — 本地 MLX（Qwen3-ASR-0.6B-4bit）或 Apple Speech，在设置中切换
- **文本润色** — Qwen3-4B-Instruct，去口语化、加标点、智能排版
- **自动热词学习** — 被动观察用户对注入文本的编辑，通过 LLM 自动提取 ASR 常错词汇（专有名词、同音字、缩写）
- **录音历史** — 每次语音输入保存为 AAC/M4A + ASR 上下文快照，支持回放复盘和调试
- **自定义提示词** — 按应用配置独立提示词，3 档润色强度，支持自定义系统提示词
- **选中编辑模式** — 选中文字后说语音指令（"把错字改了"、"变成口语"），直接替换
- **悬浮状态指示器** — 全屏可见的浮窗，显示录音/处理状态和音频电平
- **全局热键** — 支持自定义快捷键录制，Push-to-Talk / Toggle 两种模式
- **音频设备选择** — 支持选择输入设备，默认内置麦克风
- **自动粘贴** — 通过辅助功能 API 模拟 Cmd+V，自动处理 CJK 输入法切换
- **词库学习** — 编辑历史自动学习 + 手动添加，纠正词库注入 LLM 上下文
- **空闲内存管理** — 空闲后自动卸载模型释放内存，下次使用时按需加载

## 性能

所有推理在 Apple Silicon GPU 上本地运行，模型下载后无需网络。

| 阶段 | 延迟 | 说明 |
|------|------|------|
| ASR 识别（3-5s 音频） | **0.07 - 0.18s** | 实时倍率 17-51x |
| LLM 润色（短文本） | **0.35 - 0.50s** | ~30 字输入 |
| LLM 润色（长文本） | **1.1 - 1.2s** | ~120 字输入 |
| **完整流程** | **~1s** | ASR + LLM（模型已加载） |
| ASR 模型加载 | 2s | 冷启动，一次性 |
| LLM 模型加载 | 10s | 冷启动，一次性 — **瓶颈** |

内存占用：

| 状态 | RSS |
|------|-----|
| ASR 模型加载后 | ~1.6 GB |
| 双模型加载后 | ~5.4 GB |

> 完整 benchmark 数据和复现步骤见 [docs/BENCHMARK.md](docs/BENCHMARK.md)
>
> 运行 `make benchmark` 在你的机器上复现。

## 兼容性

[Releases](https://github.com/platx-ai/Talk/releases/latest) 中的 DMG 在 **macOS 26.2 (Tahoe) + Apple Silicon** 上构建和测试。这是我们唯一的测试环境 — 人类还没给我们更多设备来测试。

| | 已测试 | 应该可用 | 说明 |
|---|-------|---------|------|
| macOS 26.x (Tahoe) | ✅ | ✅ | 构建和测试环境 |
| macOS 15.x (Sequoia) | | 大概率 | 依赖库支持 macOS 14+ |
| macOS 14.x (Sonoma) | | 可能 | MLX 依赖的最低要求 |
| macOS 13 及以下 | | 不支持 | MLX 框架要求 macOS 14+ |
| Intel Mac | | 不支持 | MLX 仅支持 Apple Silicon |

如果你的系统版本较低遇到问题，可以尝试从源码构建：
```bash
git clone https://github.com/platx-ai/Talk.git && cd Talk
make build && make run
```
如果还是不行，[提个 Issue](https://github.com/platx-ai/Talk/issues) 告诉我们哪里出了问题。我们非常需要更多测试环境。

## 系统要求

- Apple Silicon (M1/M2/M3/M4) — **必须**，不支持 Intel
- macOS 14.0+ (Sonoma) — MLX 依赖的最低要求；预构建 DMG 目标版本 26.2+
- 推荐 16 GB 内存（8 GB 可用轻量模型 — 即将推出）
- ~3 GB 磁盘空间（模型文件）
- Xcode 26.3+（仅源码构建需要）

## 快速开始

```bash
# 克隆项目
git clone https://github.com/platx-ai/Talk.git
cd Talk

# 完整初始化：解析依赖 + 下载模型
make setup

# 运行
make run
```

## 构建

```bash
make build          # Debug 构建
make build-release  # Release 构建
make test           # 运行单元测试
make benchmark      # 运行性能基准测试
make run            # 构建并运行
make clean          # 清理构建产物
make resolve        # 仅解析 SPM 依赖
make download-models # 下载 HuggingFace 模型
make setup          # 完整初始化：解析 + 下载模型
make lint           # 代码检查（swiftlint，如已安装）
```

## 架构

```
录音(AVAudioEngine) → ASR(Qwen3-ASR) → LLM 润色(Qwen3-4B) → 文本注入(Cmd+V)
       ↑                  0.1s              0.5s                    ↑
    CoreAudio                                                  Accessibility
    设备选择                                                     API 权限
```

### 模块

| 模块 | 职责 |
|------|------|
| `Audio/` | 录音引擎、全局热键(CGEventTap)、音频设备管理、文本注入 |
| `ASR/` | 语音识别 — MLX 本地 (Qwen3-ASR) + Apple Speech |
| `LLM/` | 文本润色 + 热词提取 (MLXLLM + Qwen3-4B-Instruct) |
| `Models/` | 数据模型 (AppSettings, HotKeyCombo, HistoryItem, ASRContext) |
| `Data/` | 历史记录 (JSON + M4A 音频)、词库管理、编辑观察器 |
| `UI/` | SwiftUI 菜单栏、设置面板、快捷键录制器、悬浮指示器、历史浏览、闪电胶囊 |
| `Utils/` | 日志系统、Metal 运行时检查 |

### 依赖

通过 Swift Package Manager 管理，锁定到具体 commit：

| 包 | 来源 | 用途 |
|---|------|------|
| mlx-swift | [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | MLX 核心运算 |
| mlx-swift-lm | [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | LLM 推理框架 |
| mlx-audio-swift | [platx-ai/mlx-audio-swift](https://github.com/platx-ai/mlx-audio-swift) (fork) | 语音识别框架 |
| swift-huggingface | [huggingface/swift-huggingface](https://github.com/huggingface/swift-huggingface) | 模型下载 |

> mlx-audio-swift 使用 platx-ai fork，修复了上游 MLXAudioCodecs 缺少 MLXFast 依赖的问题。

### 模型

| 模型 | 大小 | 加载时间 | 内存 | 用途 |
|------|------|---------|------|------|
| [Qwen3-ASR-0.6B-4bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit) | ~400 MB | 2s | ~1.6 GB | 语音识别 |
| [Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) | ~2.5 GB | 10s | ~4 GB | 文本润色 |

模型首次运行时自动从 HuggingFace 下载到 `~/.cache/huggingface/`，可通过 `make download-models` 预下载。

## 词库与自动学习

Talk 通过两种方式从你的使用中学习：

### 被动编辑观察（v0.4.0）
文本注入到目标应用后，Talk 通过辅助功能 API 被动监控文本框。如果你编辑了注入的文本（如修正一个识别错误的词），Talk 检测到变化后，用后台 LLM 提取热词修正，自动加入词库。菜单栏会弹出 ⚡ 闪电胶囊确认收录。全程自动，无需手动操作。

### 手动修正
- **历史编辑** — 在历史记录中编辑润色文本，系统自动学习纠正。
- **手动添加** — 设置 → 个人词库 → 管理词库，添加原词和修正词。
- **导入/导出** — JSON 格式，通过管理词库界面操作。

学习到的高频纠正会注入 LLM 系统提示词，让模型在后续润色中自动应用。

**示例**：如果 ASR 反复将"LLM"识别为"拉拉木"，修正后系统会自动学习，后续润色自动纠正。

## 录音历史（v0.4.0）

每次语音输入保存为 AAC/M4A（64kbps，10 秒约 80KB）+ 上下文快照（热词列表、语言、润色强度、目标应用），支持：

- **回放调试** — 用 ASR 实际处理的音频精确复现问题
- **回归测试** — 跨版本对比识别质量
- **自动清理** — 删除历史记录时同步删除音频文件

在设置 → 个人词库 → "保存录音历史" 中开关。

## 权限

首次运行需要授权：

1. **麦克风** — 用于录音，系统会自动弹出授权请求
2. **输入监控** — 用于监听全局快捷键。请在「系统设置 → 隐私与安全性 → 输入监控」中打开 Talk
3. **辅助功能** — 用于自动粘贴文本到其他应用。请在「系统设置 → 隐私与安全性 → 辅助功能」中打开 Talk.app

如果全局快捷键没有反应，优先检查 **输入监控**。开启输入监控后，需要退出并重新打开 Talk，热键才会稳定生效。

## 开发

```bash
# 在 Xcode 中打开
open Talk.xcodeproj

# 设置签名团队：Xcode → Signing & Capabilities → Team
# 构建并运行：⌘R
```

### 测试

```bash
make test       # 单元测试
make benchmark  # 性能基准测试（ASR/LLM 加载、推理、管线、内存）
```

所有变更必须有对应测试。Bug 修复前必须写回归测试。详见 [CLAUDE.md](CLAUDE.md) 的测试规范。

### 代码签名

`DEVELOPMENT_TEAM` 为空，每个开发者在 Xcode 中设置自己的签名团队。命令行构建使用 ad-hoc 签名。

## 路线图

完整路线图见 [ROADMAP.md](ROADMAP.md)。

**近期**
- 自研轻量润色模型 (0.5-1.5B) — 加载 < 1s，内存 < 1 GB
- 实时转写预览浮窗
- 硬件自动选模型（8GB → 轻量，16GB+ → 完整）

**中期**
- 项目感知的词库与提示词配置（`.talk/` 目录）
- iCloud 词库同步
- iOS 离线伴侣应用

**长期**
- 团队共享术语库
- 自定义后处理管线插件系统

## License

[MIT](LICENSE)
