# KupaDesk（云核心注入与中文增强一体化插件）

KupaDesk `v2.0.0` 已将原 `antigravity-cn-toolkit` 与 `prompt-injector` 合并为统一的一体化插件，提供云核心与系统提示词注入、客户端中文汉化/上下文监控/右键「打开存放位置」、新对话自动中文标题，以及基于 `kupakupa.vip` 的 ES256 签名云更新能力。

## 注入层级与可靠性机制

1. **顶层 `systemInstruction` 按对话 ID 动态绑定（默认推荐）**：
   - 开启或切换核心时，插件原子写入 `rules/AGENTS.md`（仅含纯净正文）；每次模型推理前，Hook 会按当前正在推理的 `conversationId` 自动将规则切为该对话的选定配置（未开启注入的对话推理前自动移除），并配合 260ms 并发排队互斥锁与 120ms 刷新等待，交由 Antigravity 原生组装至顶层 `systemInstruction`（`<user_rules>` 区块）。
   - 全程无痕运行：`PreInvocation` Hook 永远只返回 `{}`，不会在对话流插入额外注入气泡或 `Hook Json PreInvocation` 提示块。
   - **随开随关零残留**：关闭开关、清空内容、租约失效或 Sidecar 退出时立即删除 `rules/AGENTS.md`（保留 `rules/` 目录句柄），彻底清除顶层规则。
2. **Hook 轨迹兼容模式（`hook`）**：
   - 可在「设置 → 高级注入策略」切回 `PreInvocation` 轨迹注入模式（云核心正文仅驻留 Sidecar 内存）。

## 中文增强、右键菜单与红框入口（`antigravity-cn-toolkit` 已合并）

- **静态简体中文规则**：`rules/cn-language-rule.md` 与动态云核心文件 `rules/AGENTS.md` 完全解耦，可在控制面板随时开关。
- **新对话自动中文标题**：由 `hooks/auto-title.mjs`（`Stop` Hook）离线提炼中文标题写入新会话（绝不覆盖手动重命名）。
- **一体化客户端挂载与恢复**：
  - 支持将 **中文汉化 + 上下文监控圆环 + 右键「打开存放位置 / 复制路径」 + KupaDesk 输入框右上方红框入口** 一键组合部署进客户端 `app.asar`（外置热加载，更新前端几乎无需重装 `app.asar`）。
  - 可在右侧控制面板顶部导航栏切换 **对话 / 增强 / 设置 / 诊断** 四大标签页，也可通过输入框右上角悬浮胶囊快捷键或输入 `/cn` 直达 **KupaDesk「增强」页**（`sidecar://kupadesk/prompt_panel/?view=client`）管理，或使用 CLI 脚本：
    - 查询状态：`node lib/cn-runner.cjs --action status`
    - 干跑预检：`node lib/cn-runner.cjs --action install-all --dry-run`
    - 一键全套安装/恢复：`node lib/cn-runner.cjs --action install-all --auto-restart`

## `kupakupa.vip` 云更新与打包签名发布流程

1. **云端托管方式（纯静态，无需改后端）**：
   - 插件启动后或点击设置页「检查更新」时，请求 `${cloud.origin}/releases/antigravity/manifest.json`（默认 `https://kupakupa.vip/releases/antigravity/manifest.json`）。
   - 使用内置 ES256 公钥校验 `manifest.json` 签名，校对同源 `.zip` 下载地址、文件字节数与 SHA-256 摘要，校验防穿越/禁写路径（严格保护 `rules/AGENTS.md` 不被覆盖）并保留旧版备份自动回滚，应用后热重启 Sidecar 生效。
2. **本地一键打包与签名命令**：
   - 提升 [plugin.json](plugin.json) 版本号后，在插件根目录运行：
     ```bash
     node scripts/build-release.mjs --changelog "本次更新说明"
     ```
   - 如本次改到了 `desktop/install-desktop.cjs`、`vendor/` 需重新打客户端 `app.asar`，追加 `--requires-asar`。
   - 产物默认生成至 `~/.gemini/config/plugin-data/prompt-injector/releases/`：
     - `manifest.json`
     - `kupadesk-v<version>.zip`
   - 将上述两个文件直接上传至 `kupakupa.vip` 的静态目录 `/releases/antigravity/` 即可完成发布。
   - **重要提示**：发布签名私钥保存在 `~/.gemini/config/plugin-data/prompt-injector/release-signing/kupadesk-release-private.pem`，请妥善备份，不要提交到公开仓库或打入发布包中（脚本默认已自动排除）。

## 目录与数据存储

- 插件根目录：`~/.gemini/config/plugins/prompt-injector/`
- 持久化数据目录：`~/.gemini/config/plugin-data/prompt-injector/`（含 `global.json`、`conversations/`、`cloud/device.json`、`cn-toolkit/state.json`、`releases/`、`release-signing/`、`update-backup/`）
