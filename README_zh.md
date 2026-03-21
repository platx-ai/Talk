# Talk

**Open Typeless. Local Typeless. Typeless in your box.**

macOS 菜单栏语音输入工具 — 按住快捷键说话，自动识别、润色、粘贴到当前应用。你的声音，直达文字，无需云端，无需打字。

[English](README.md)

> 本项目的原始算法和代码基于孔老师（[@jiamingkong](https://github.com/jiamingkong)）的慷慨贡献。我们只是想快速验证一下十分钟能不能搞定一个 typeless。

## Features

- **本地推理** — 基于 Apple Silicon MLX，无云端依赖，隐私优先
- **语音识别** — Qwen3-ASR-0.6B-4bit，支持中英文
- **文本润色** — Qwen3-4B-Instruct，去口语化、加标点、智能排版
- **全局热键** — 支持自定义快捷键录制，Push-to-Talk / Toggle 两种模式
- **音频设备选择** — 支持选择输入设备，默认内置麦克风
- **自动粘贴** — 通过辅助功能 API 模拟 Cmd+V 注入文本

## Requirements

- macOS 26.2+
- Apple Silicon (M1/M2/M3/M4)
- Xcode 26.3+
- ~5GB 磁盘空间（模型文件）

## Quick Start

```bash
# 克隆项目
git clone https://github.com/platx-ai/Talk.git
cd Talk

# 解析依赖 + 构建
make build

# 下载模型（首次需要）
make download-models

# 运行
make run
```

## Build

```bash
make build          # Debug 构建
make build-release  # Release 构建
make test           # 运行测试
make clean          # 清理构建产物
make resolve        # 仅解析 SPM 依赖
make lint           # 代码检查（swiftlint，如已安装）
```

## Architecture

```
录音(AVAudioEngine) → ASR(Qwen3-ASR) → LLM润色(Qwen3-4B) → 文本注入(Cmd+V)
     ↑                                                           ↑
  CoreAudio                                                 Accessibility
  设备选择                                                    API 权限
```

### 模块结构

| 模块 | 职责 |
|------|------|
| `Audio/` | 录音引擎、全局热键(Carbon API)、音频设备管理、文本注入 |
| `ASR/` | 语音识别 (MLXAudioSTT + Qwen3-ASR) |
| `LLM/` | 文本润色 (MLXLLM + Qwen3-4B-Instruct) |
| `Models/` | 数据模型 (AppSettings, HotKeyCombo, HistoryItem) |
| `Data/` | 历史记录和词库的 JSON 持久化 |
| `UI/` | SwiftUI 菜单栏、设置面板、快捷键录制器、历史浏览 |
| `Utils/` | 日志系统、Metal 运行时检查 |

### Dependencies

| Package | Source | Version |
|---------|--------|---------|
| mlx-swift | [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | `b6e128c` |
| mlx-swift-lm | [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | `edd42fc` |
| mlx-audio-swift | [platx-ai/mlx-audio-swift](https://github.com/platx-ai/mlx-audio-swift) (fork) | `4ece9e0` |
| swift-huggingface | [huggingface/swift-huggingface](https://github.com/huggingface/swift-huggingface) | `0.9.0` |

> mlx-audio-swift 使用 platx-ai fork 修复了上游 [MLXAudioCodecs 缺少 MLXFast 依赖](https://github.com/Blaizzy/mlx-audio-swift/issues/) 的问题。

### Models

| Model | Size | Purpose |
|-------|------|---------|
| [mlx-community/Qwen3-ASR-0.6B-4bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit) | ~400MB | 语音识别 |
| [mlx-community/Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) | ~2.5GB | 文本润色 |

模型首次运行时自动从 HuggingFace 下载到 `~/.cache/huggingface/`，也可通过 `make download-models` 预下载。

## Permissions

首次运行需要授权：

1. **麦克风** — 系统自动弹出授权请求
2. **辅助功能** — 需手动在「系统设置 → 隐私与安全性 → 辅助功能」中添加 Talk.app

## Development

```bash
# 在 Xcode 中打开
open Talk.xcodeproj

# 设置签名团队：Xcode → Signing & Capabilities → Team
# 构建并运行：⌘R
```

### Code Signing

项目中 `DEVELOPMENT_TEAM` 为空，每个开发者需在 Xcode 中设置自己的签名团队。命令行构建使用 ad-hoc 签名。

## License

[MIT](LICENSE)
