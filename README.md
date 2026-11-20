# KupaDesk — Antigravity 一体化云核心与中文增强插件

**KupaDesk v2.0.0** 现已整合云核心按对话动态绑定（顶层 `systemInstruction`）、Antigravity 中文汉化、上下文监控圆环、右键「打开存放位置」、新对话自动中文标题，以及基于 ES256 签名的自动云更新能力。

---

## 一键安装

### 1. 让 Antigravity AI 直接帮您安装（推荐）
把下面这句话复制粘贴进 Antigravity 对话框发送即可：

> 帮我安装 KupaDesk 插件：运行 `irm https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main/install.ps1 | iex`

### 2. Windows PowerShell 一行命令
```powershell
irm https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main/install.ps1 | iex
```

### 3. Windows 双击安装器（无需敲命令）
下载后直接双击运行：
https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main/install-kupadesk.cmd

### 4. macOS / Linux 一行命令
```bash
curl -fsSL https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main/install.sh | bash
```

---

## 安装后使用说明

1. 安装脚本会自动把插件解压到 `~/.gemini/config/plugins/prompt-injector`，并一键挂载 **中文汉化 + 上下文监控 + 右键打开存放位置 + 输入框右上方悬浮红框入口**，随后自动重启一次 Antigravity。
2. 打开任意对话，点击输入框右上角的 **KupaDesk 胶囊 → ⚙ 设置图标**（或右侧扩展栏中的 **KupaDesk**），在「云端授权」卡片中激活您的 KupaDesk 卡密即可选用云核心。
3. 后续版本更新直接在插件右上角 **⚙ 设置页 → 插件云更新** 中一键验签热更新，无需重复重装。
