# Talk

**Open Typeless. Local Typeless. Typeless in your box.**

macOS 菜单栏语音输入工具 — 按住快捷键说话，自动识别、润色、粘贴到当前应用。你的声音，直达文字，无需云端，无需打字。

[English](README.md)

> 本项目的原始算法和代码基于孔老师（[@jiamingkong](https://github.com/jiamingkong)）的慷慨贡献。我们只是想快速验证一下十分钟能不能搞定一个 typeless。

## 功能

- **本地推理** — 基于 Apple Silicon MLX，无云端依赖，隐私优先
- **语音识别** — Qwen3-ASR-0.6B-4bit，支持中英文
- **文本润色** — Qwen3-4B-Instruct，去口语化、加标点、智能排版
- **自定义提示词** — 4 种预设模板（严格纠错/轻度润色/会议纪要/技术文档），支持自定义
- **选中编辑模式** — 选中文字后说语音指令（"把错字改了"、"变成口语"），直接替换
- **悬浮状态指示器** — 全屏可见的浮窗，显示录音/处理状态和音频电平
- **全局热键** — 支持自定义快捷键录制，Push-to-Talk / Toggle 两种模式
- **音频设备选择** — 支持选择输入设备，默认内置麦克风
- **自动粘贴** — 通过辅助功能 API 模拟 Cmd+V 注入文本
- **词库学习** — 在历史记录中编辑润色结果，系统自动学习纠正用于后续润色
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

## 系统要求

- macOS 26.2+
- Apple Silicon (M1/M2/M3/M4)
- Xcode 26.3+
- 推荐 16 GB 内存（8 GB 可用轻量模型 — 即将推出）
- ~3 GB 磁盘空间（模型文件）

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
make test           # 运行单元测试（43 个）
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
| `Audio/` | 录音引擎、全局热键(Carbon API)、音频设备管理、文本注入 |
| `ASR/` | 语音识别 (MLXAudioSTT + Qwen3-ASR) |
| `LLM/` | 文本润色 (MLXLLM + Qwen3-4B-Instruct) |
| `Models/` | 数据模型 (AppSettings, HotKeyCombo, HistoryItem) |
| `Data/` | 历史记录和词库的 JSON 持久化 |
| `UI/` | SwiftUI 菜单栏、设置面板、快捷键录制器、悬浮指示器、历史浏览 |
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

## 词库

Talk 会从你的修改中学习，持续改进润色质量。

**工作原理**：在历史记录中编辑润色结果时，系统会记录"原文 -> 修正"的映射。最近学习的 20 条纠正会作为【已学习的纠正】注入 LLM 系统提示词，让模型在后续润色中自动应用。

**使用方式**：
- **自动学习** -- 在历史记录中编辑任意润色文本，系统自动学习该纠正。
- **手动添加** -- 设置 -> 高级 -> 个人词库 -> 管理词库，添加原词和修正词。
- **导入/导出** -- JSON 格式，通过管理词库界面导出备份或导入共享。

**示例**：如果 ASR 反复将"LLM"识别为"拉拉木"，你在历史记录中修正后，系统会学习这个映射，后续润色时自动将"拉拉木"纠正为"LLM"。

## 权限

首次运行需要授权：

1. **麦克风** — 系统自动弹出授权请求
2. **辅助功能** — 需手动在「系统设置 → 隐私与安全性 → 辅助功能」中添加 Talk.app

## 开发

```bash
# 在 Xcode 中打开
open Talk.xcodeproj

# 设置签名团队：Xcode → Signing & Capabilities → Team
# 构建并运行：⌘R
```

### 测试

```bash
make test       # 43 个单元测试（HotKeyCombo、AppSettings、AudioDevice、FloatingIndicator、VocabularyManager）
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
