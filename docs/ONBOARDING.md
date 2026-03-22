# Talk 首次启动引导设计

## 概述

Talk 首次启动时展示引导流程，帮助用户完成权限授予、模型下载和快捷键配置。引导采用多步骤卡片式设计，每步占满一屏，底部有"下一步"/"跳过"按钮。

引导仅在首次启动时展示，通过 `UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")` 控制。用户可随时跳过，未完成的步骤可在设置中重新触发。

---

## 流程步骤

### Step 1: 欢迎

**界面内容：**

- App 图标 + 名称 "Talk"
- 标语："按住说话，自动输入"
- 一句话描述："Talk 是 macOS 语音输入工具。按下快捷键说话，AI 自动识别、润色并输入到光标位置。全部在本地运行，无需联网。"
- 按钮：`开始设置`

**技术说明：**

- 点击"开始设置"后进入 Step 2
- 无需任何系统调用

---

### Step 2: 权限设置

**界面内容：**

两个权限项，各占一行，左侧图标 + 说明文字，右侧状态标记（未授权 / 已授权 checkmark）。

#### 2a. 麦克风权限

- 图标：`mic.circle`
- 标题："麦克风权限"
- 说明："Talk 需要录制你的语音，音频仅在本地处理，不会上传任何服务器。"
- 按钮：`授权麦克风`
- 行为：调用 `AVCaptureDevice.requestAccess(for: .audio)`，macOS 弹出系统授权弹窗
- 授权后：按钮变为绿色 checkmark + "已授权"

#### 2b. 辅助功能权限

- 图标：`hand.raised.circle`
- 标题："辅助功能权限"
- 说明："Talk 需要辅助功能权限来将文字自动粘贴到当前应用。此权限需要手动授予。"
- 操作指引（折叠/展开，默认展开）：
  1. 点击下方按钮打开系统设置
  2. 在「隐私与安全性 → 辅助功能」列表中，点击左下角 `+` 按钮
  3. 在弹出的文件选择器中找到 Talk.app（通常在"应用程序"文件夹）并添加
  4. 确保 Talk.app 旁边的开关已打开
  5. 回到 Talk，状态会自动更新
- 按钮：`打开辅助功能设置`
- 行为：调用 `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`
- 检测逻辑：用定时器（每 2 秒）轮询 `AXIsProcessTrusted()`，授权后显示 checkmark

**底部按钮：**

- `下一步` —— 两项都已授权时高亮
- `稍后设置` —— 始终可点，跳到 Step 3（缺少权限不影响模型下载）

**技术说明：**

- 麦克风权限状态通过 `AVCaptureDevice.authorizationStatus(for: .audio)` 检查
- 辅助功能权限状态通过 `AXIsProcessTrusted()` 检查
- 页面出现时立即检查当前状态，已授权的项直接显示 checkmark

---

### Step 3: 模型下载

**界面内容：**

- 图标：`arrow.down.circle`
- 标题："下载 AI 模型"
- 说明："Talk 使用本地 AI 模型进行语音识别和文本润色，首次使用需下载约 3GB 模型文件。"

#### 下载源选择

两个选项卡片，单选：

| 选项 | 标签 | 说明 | 模型 ID |
|------|------|------|---------|
| A | HuggingFace | 国际用户推荐，速度稳定 | `mlx-community/Qwen3-ASR-0.6B-4bit`<br>`mlx-community/Qwen3-4B-Instruct-2507-4bit` |
| B | ModelScope 镜像 | 中国大陆用户推荐，国内直连 | `mlx-community/Qwen3-ASR-0.6B-4bit`<br>`mlx-community/Qwen3-4B-Instruct-2507-4bit` |

> **ModelScope 镜像说明：** 两个模型在 ModelScope 上的 ID 与 HuggingFace 完全相同（均为 `mlx-community/` 组织下同名仓库），已验证可用。选择 ModelScope 时仅切换下载源域名，模型 ID 不变。

#### 下载进度

- 选择源后显示"开始下载"按钮
- 下载中显示：
  - 当前下载模型名称（先 ASR，后 LLM）
  - 进度条 + 百分比 + 已下载/总大小
  - "正在下载 Qwen3-ASR (1/2)..." → "正在下载 Qwen3-LLM (2/2)..."
- 下载完成：两个 checkmark + "模型已就绪"
- 下载失败：显示错误信息 + "重试"按钮

#### 终端替代方式

进度条下方灰色提示文字：

> 也可以在终端中运行 `make download-models` 手动下载。

**底部按钮：**

- `下一步` —— 下载完成后高亮
- `稍后下载` —— 始终可点（未下载模型时 app 启动会再次尝试下载）

**技术说明：**

- HuggingFace 下载使用现有 `HubCache.default` + `snapshot_download` 机制
- ModelScope 下载需要将 hub endpoint 切换为 `https://modelscope.cn`（具体实现取决于 swift-huggingface 库是否支持自定义 endpoint，或需要使用 modelscope SDK）
- 下载的模型存储在 `~/.cache/huggingface/` 目录，与命令行 `make download-models` 共享缓存
- 如果检测到模型已存在于缓存中，直接显示"已就绪"并跳过下载

---

### Step 4: 快捷键设置

**界面内容：**

- 图标：`keyboard`
- 标题："设置快捷键"
- 说明："选择触发录音的快捷键和触发方式。"

#### 快捷键选择

- 当前快捷键显示区域，带录制功能（复用现有 `KeyRecorderView` 组件）
- 默认值：`⌃ Control`
- 点击后进入录制模式，按下新键即完成设置

#### 触发方式

两个选项，单选：

| 模式 | 说明 |
|------|------|
| 按住说话 (Push-to-Talk) | 按住快捷键开始录音，松开后自动处理。**推荐新用户使用。** |
| 切换模式 (Toggle) | 按一次开始录音，再按一次停止并处理。适合较长的口述场景。 |

默认选中"按住说话"。

**底部按钮：**

- `完成设置`

---

### Step 5: 设置完成

**界面内容：**

- 大号 checkmark 图标
- 标题："Talk 已就绪！"
- 使用说明：
  - "按住 `⌃ Control` 开始说话"（根据实际设置的快捷键动态显示）
  - "松开后 AI 自动识别、润色并输入到光标位置"
- 按钮：`开始使用`
- 链接文字："打开设置可以调整更多选项" —— 点击打开 SettingsView

**技术说明：**

- 点击"开始使用"：
  - 设置 `UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")`
  - 关闭引导窗口
  - 如果模型已下载，开始加载模型

---

## 全局规则

### 显示条件

- `UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == false` 时显示
- 引导窗口为独立 `NSWindow`，居中显示，不可缩放
- 引导期间菜单栏图标正常显示，但录音功能不可用（模型未加载）

### 跳过与恢复

- 每一步都可以跳过（"稍后设置" / "稍后下载"）
- 跳过不会设置 `hasCompletedOnboarding`，除非到达 Step 5 并点击"开始使用"
- 用户如果直接关闭引导窗口（红色关闭按钮），视为跳过全部，设置 `hasCompletedOnboarding = true`，下次不再弹出
- 设置面板中添加"重新运行引导"按钮，清除 `hasCompletedOnboarding` 后重新打开引导窗口

### 语言

- 所有引导文案使用中文（与 app 主界面语言一致）
- 若后续支持英文界面，引导文案跟随 `AppSettings.appLanguage` 切换

### 窗口规格

- 固定尺寸：520 x 440pt
- 居中显示
- 标题栏隐藏，使用自定义标题区域
- 步骤指示器（圆点）显示在底部按钮上方，标示当前位于第几步

---

## ModelScope 镜像调研结果

已验证以下 ModelScope 模型可用（API 返回 200）：

| 用途 | HuggingFace ID | ModelScope ID | ModelScope URL |
|------|----------------|---------------|----------------|
| ASR | `mlx-community/Qwen3-ASR-0.6B-4bit` | `mlx-community/Qwen3-ASR-0.6B-4bit` | https://modelscope.cn/models/mlx-community/Qwen3-ASR-0.6B-4bit |
| LLM | `mlx-community/Qwen3-4B-Instruct-2507-4bit` | `mlx-community/Qwen3-4B-Instruct-2507-4bit` | https://modelscope.cn/models/mlx-community/Qwen3-4B-Instruct-2507-4bit |

两个模型在 ModelScope 上由 `mlx-community` 组织发布，ID 与 HuggingFace 完全一致。实现时只需切换 API base URL（`huggingface.co` -> `modelscope.cn`），无需维护单独的 model ID 映射。
