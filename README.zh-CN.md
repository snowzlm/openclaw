# 🦞 OpenClaw — 个人 AI 助手

<p align="center">
    <picture>
        <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/openclaw-logo-text-dark.png">
        <img src="https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/openclaw-logo-text.png" alt="OpenClaw" width="500">
    </picture>
</p>

<p align="center">
  <strong>EXFOLIATE! EXFOLIATE!</strong>
</p>

<p align="center">
  <a href="https://github.com/openclaw/openclaw/actions/workflows/ci.yml?branch=main"><img src="https://img.shields.io/github/actions/workflow/status/openclaw/openclaw/ci.yml?branch=main&style=for-the-badge" alt="CI status"></a>
  <a href="https://github.com/openclaw/openclaw/releases"><img src="https://img.shields.io/github/v/release/openclaw/openclaw?include_prereleases&style=for-the-badge" alt="GitHub release"></a>
  <a href="https://discord.gg/clawd"><img src="https://img.shields.io/discord/1456350064065904867?label=Discord&logo=discord&logoColor=white&color=5865F2&style=for-the-badge" alt="Discord"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
</p>

**OpenClaw** 是一个你可以在自己的设备上运行的**个人 AI 助手**。
它可以在你已经使用的渠道上回复你（WhatsApp、Telegram、Slack、Discord、Google Chat、Signal、iMessage、Microsoft Teams、WebChat），以及扩展渠道如 BlueBubbles、Matrix、Zalo 和 Zalo Personal。它可以在 macOS/iOS/Android 上说话和收听，并且可以渲染你控制的实时 Canvas。Gateway 只是控制平面——产品是助手本身。

如果你想要一个感觉本地、快速且始终在线的个人单用户助手，这就是它。

[网站](https://openclaw.ai) · [文档](https://docs.openclaw.ai) · [愿景](VISION.md) · [DeepWiki](https://deepwiki.com/openclaw/openclaw) · [入门指南](https://docs.openclaw.ai/start/getting-started) · [更新](https://docs.openclaw.ai/install/updating) · [展示](https://docs.openclaw.ai/start/showcase) · [FAQ](https://docs.openclaw.ai/start/faq) · [向导](https://docs.openclaw.ai/start/wizard) · [Nix](https://github.com/openclaw/nix-openclaw) · [Docker](https://docs.openclaw.ai/install/docker) · [Discord](https://discord.gg/clawd)

首选设置：在终端中运行入门向导 (`openclaw onboard`)。
向导会一步步指导你设置 gateway、工作区、渠道和技能。CLI 向导是推荐的路径，适用于 **macOS、Linux 和 Windows（通过 WSL2；强烈推荐）**。
支持 npm、pnpm 或 bun。
新安装？从这里开始：[入门指南](https://docs.openclaw.ai/start/getting-started)

**订阅（OAuth）：**

- **[Anthropic](https://www.anthropic.com/)** (Claude Pro/Max)
- **[OpenAI](https://openai.com/)** (ChatGPT/Codex)

模型说明：虽然支持任何模型，但我强烈推荐 **Anthropic Pro/Max (100/200) + Opus 4.6**，以获得长上下文优势和更好的提示注入抵抗力。参见 [入门](https://docs.openclaw.ai/start/onboarding)。

## 模型（选择 + 认证）

- 模型配置 + CLI: [模型](https://docs.openclaw.ai/concepts/models)
- 认证配置文件轮换（OAuth vs API 密钥）+ 故障转移：[模型故障转移](https://docs.openclaw.ai/concepts/model-failover)

## 安装（推荐）

运行时：**Node ≥22**。

```bash
npm install -g openclaw@latest
# 或：pnpm add -g openclaw@latest

openclaw onboard --install-daemon
```

向导会安装 Gateway 守护进程（launchd/systemd 用户服务），使其保持运行。

## 快速入门（TL;DR）

运行时：**Node ≥22**。

完整初学者指南（认证、配对、渠道）：[入门指南](https://docs.openclaw.ai/start/getting-started)

```bash
openclaw onboard --install-daemon

openclaw gateway --port 18789 --verbose

# 发送消息
openclaw message send --to +1234567890 --message "Hello from OpenClaw"

# 与助手对话（可选择交付回任何连接的渠道：WhatsApp/Telegram/Slack/Discord/Google Chat/Signal/iMessage/BlueBubbles/Microsoft Teams/Matrix/Zalo/Zalo Personal/WebChat）
openclaw agent --message "Ship checklist" --thinking high
```

升级中？[更新指南](https://docs.openclaw.ai/install/updating)（并运行 `openclaw doctor`）。

## 开发渠道

- **stable**: 标记发布（`vYYYY.M.D` 或 `vYYYY.M.D-<patch>`），npm dist-tag `latest`。
- **beta**: 预发布标记（`vYYYY.M.D-beta.N`），npm dist-tag `beta`（macOS 应用可能缺失）。
- **dev**: `main` 的移动头部，npm dist-tag `dev`（发布时）。

切换渠道（git + npm）：`openclaw update --channel stable|beta|dev`。
详情：[开发渠道](https://docs.openclaw.ai/install/development-channels)。

## 从源码（开发）

推荐使用 `pnpm` 进行源码构建。Bun 可选用于直接运行 TypeScript。

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw

pnpm install
pnpm ui:build # 首次运行时自动安装 UI 依赖
pnpm build

pnpm openclaw onboard --install-daemon

# 开发循环（TS 更改时自动重新加载）
pnpm gateway:watch
```

注意：`pnpm openclaw ...` 直接运行 TypeScript（通过 `tsx`）。`pnpm build` 生成 `dist/` 用于通过 Node / 打包的 `openclaw` 二进制文件运行。

## 安全默认值（DM 访问）

OpenClaw 连接到真实的消息渠道。将入站 DM 视为**不受信任的输入**。

完整安全指南：[安全](https://docs.openclaw.ai/gateway/security)

Telegram/WhatsApp/Signal/iMessage/Microsoft Teams/Discord/Google Chat/Slack 上的默认行为：

- **DM 配对** (`dmPolicy="pairing"` / `channels.discord.dmPolicy="pairing"` / `channels.slack.dmPolicy="pairing"`; 旧版：`channels.discord.dm.policy`, `channels.slack.dm.policy`)：未知发送者会收到一个简短的配对代码，机器人不会处理他们的消息。
- 批准使用：`openclaw pairing approve <channel> <code>`（然后发送者会被添加到本地允许列表存储）。
- 公共入站 DM 需要明确选择加入：设置 `dmPolicy="open"` 并在渠道允许列表中包含 `"*"`（`allowFrom` / `channels.discord.allowFrom` / `channels.slack.allowFrom`；旧版：`channels.discord.dm.allowFrom`, `channels.slack.dm.allowFrom`）。

运行 `openclaw doctor` 以暴露有风险/配置错误的 DM 策略。

## 亮点

- **[本地优先 Gateway](https://docs.openclaw.ai/gateway)** — 用于会话、渠道、工具和事件的单一控制平面。
- **[多渠道收件箱](https://docs.openclaw.ai/channels)** — WhatsApp、Telegram、Slack、Discord、Google Chat、Signal、BlueBubbles (iMessage)、iMessage (旧版)、Microsoft Teams、Matrix、Zalo、Zalo Personal、WebChat、macOS、iOS/Android。
- **[多代理路由](https://docs.openclaw.ai/gateway/configuration)** — 将入站渠道/账户/对等方路由到隔离的代理（工作区 + 每代理会话）。
- **[Voice Wake](https://docs.openclaw.ai/nodes/voicewake) + [Talk Mode](https://docs.openclaw.ai/nodes/talk)** — macOS/iOS/Android 上的始终在线语音，使用 ElevenLabs。
- **[Live Canvas](https://docs.openclaw.ai/platforms/mac/canvas)** — 代理驱动的视觉工作区，带有 [A2UI](https://docs.openclaw.ai/platforms/mac/canvas#canvas-a2ui)。
- **[一流工具](https://docs.openclaw.ai/tools)** — 浏览器、canvas、节点、cron、会话和 Discord/Slack 操作。
- **[伴侣应用](https://docs.openclaw.ai/platforms/macos)** — macOS 菜单栏应用 + iOS/Android [节点](https://docs.openclaw.ai/nodes)。
- **[入门](https://docs.openclaw.ai/start/wizard) + [技能](https://docs.openclaw.ai/tools/skills)** — 向导驱动设置，带有捆绑/管理/工作区技能。

## Star 历史

[![Star History Chart](https://api.star-history.com/svg?repos=openclaw/openclaw&type=date&legend=top-left)](https://www.star-history.com/#openclaw/openclaw&type=date&legend=top-left)

## 我们迄今为止构建的一切

### 核心平台

- [Gateway WS 控制平面](https://docs.openclaw.ai/gateway)，带有会话、存在、配置、cron、webhooks、[控制 UI](https://docs.openclaw.ai/web) 和 [Canvas 主机](https://docs.openclaw.ai/platforms/mac/canvas#canvas-a2ui)。
- [CLI 表面](https://docs.openclaw.ai/tools/agent-send)：gateway、agent、send、[向导](https://docs.openclaw.ai/start/wizard) 和 [doctor](https://docs.openclaw.ai/gateway/doctor)。
- [Pi 代理运行时](https://docs.openclaw.ai/concepts/agent)，RPC 模式，带有工具流和块流。
- [会话模型](https://docs.openclaw.ai/concepts/session)：`main` 用于直接聊天、组隔离、激活模式、队列模式、回复。组规则：[组](https://docs.openclaw.ai/concepts/groups)。
- [媒体管道](https://docs.openclaw.ai/nodes/images)：图像/音频/视频、转录钩子、大小限制、临时文件生命周期。音频详情：[音频](https://docs.openclaw.ai/nodes/audio)。

### 渠道

- [渠道](https://docs.openclaw.ai/channels)：[WhatsApp](https://docs.openclaw.ai/channels/whatsapp) (Baileys)、[Telegram](https://docs.openclaw.ai/channels/telegram) (grammY)、[Slack](https://docs.openclaw.ai/channels/slack) (Bolt)、[Discord](https://docs.openclaw.ai/channels/discord) (discord.js)、[Google Chat](https://docs.openclaw.ai/channels/googlechat) (Chat API)、[Signal](https://docs.openclaw.ai/channels/signal) (signal-cli)、[BlueBubbles](https://docs.openclaw.ai/channels/bluebubbles) (iMessage，推荐)、[iMessage](https://docs.openclaw.ai/channels/imessage) (旧版 imsg)、[Microsoft Teams](https://docs.openclaw.ai/channels/msteams) (扩展)、[Matrix](https://docs.openclaw.ai/channels/matrix) (扩展)、[Zalo](https://docs.openclaw.ai/channels/zalo) (扩展)、[Zalo Personal](https://docs.openclaw.ai/channels/zalouser) (扩展)、[WebChat](https://docs.openclaw.ai/web/webchat)。
- [组路由](https://docs.openclaw.ai/concepts/group-messages)：提及门控、回复标签、每渠道分块和路由。渠道规则：[渠道](https://docs.openclaw.ai/channels)。

### 应用 + 节点

- [macOS 应用](https://docs.openclaw.ai/platforms/macos)：菜单栏控制平面、[Voice Wake](https://docs.openclaw.ai/nodes/voicewake)/PTT、[Talk Mode](https://docs.openclaw.ai/nodes/talk) 覆盖、[WebChat](https://docs.openclaw.ai/web/webchat)、调试工具、[远程 gateway](https://docs.openclaw.ai/gateway/remote) 控制。
- [iOS 节点](https://docs.openclaw.ai/platforms/ios)：[Canvas](https://docs.openclaw.ai/platforms/mac/canvas)、[Voice Wake](https://docs.openclaw.ai/nodes/voicewake)、[Talk Mode](https://docs.openclaw.ai/nodes/talk)、相机、屏幕录制、Bonjour 配对。
- [Android 节点](https://docs.openclaw.ai/platforms/android)：[Canvas](https://docs.openclaw.ai/platforms/mac/canvas)、[Talk Mode](https://docs.openclaw.ai/nodes/talk)、相机、屏幕录制、可选 SMS。
- [macOS 节点模式](https://docs.openclaw.ai/nodes)：system.run/notify + canvas/camera 暴露。

### 工具 + 自动化

- [浏览器控制](https://docs.openclaw.ai/tools/browser)：专用的 openclaw Chrome/Chromium、快照、操作、上传、配置文件。
- [Canvas](https://docs.openclaw.ai/platforms/mac/canvas)：[A2UI](https://docs.openclaw.ai/platforms/mac/canvas#canvas-a2ui) push/reset、eval、快照。
- [节点](https://docs.openclaw.ai/nodes)：相机快照/剪辑、屏幕录制、[location.get](https://docs.openclaw.ai/nodes/location-command)、通知。
- [Cron + 唤醒](https://docs.openclaw.ai/automation/cron-jobs)；[webhooks](https://docs.openclaw.ai/automation/webhook)；[Gmail Pub/Sub](https://docs.openclaw.ai/automation/gmail-pubsub)。
- [技能平台](https://docs.openclaw.ai/tools/skills)：带有安装门控 + UI 的捆绑、管理和工作区技能。

### 运行时 + 安全

- [渠道路由](https://docs.openclaw.ai/concepts/channel-routing)、[重试策略](https://docs.openclaw.ai/concepts/retry) 和 [流式/分块](https://docs.openclaw.ai/concepts/streaming)。
- [存在](https://docs.openclaw.ai/concepts/presence)、[输入指示器](https://docs.openclaw.ai/concepts/typing-indicators) 和 [使用跟踪](https://docs.openclaw.ai/concepts/usage-tracking)。
- [模型](https://docs.openclaw.ai/concepts/models)、[模型故障转移](https://docs.openclaw.ai/concepts/model-failover) 和 [会话修剪](https://docs.openclaw.ai/concepts/session-pruning)。
- [安全](https://docs.openclaw.ai/gateway/security) 和 [故障排除](https://docs.openclaw.ai/channels/troubleshooting)。

### 运维 + 打包

- [控制 UI](https://docs.openclaw.ai/web) + [WebChat](https://docs.openclaw.ai/web/webchat) 直接从 Gateway 提供。
- [Tailscale Serve/Funnel](https://docs.openclaw.ai/gateway/tailscale) 或 [SSH 隧道](https://docs.openclaw.ai/gateway/remote)，带有令牌/密码认证。
- [Nix 模式](https://docs.openclaw.ai/install/nix) 用于声明式配置；[Docker](https://docs.openclaw.ai/install/docker) 基础安装。
- [Doctor](https://docs.openclaw.ai/gateway/doctor) 迁移、[日志记录](https://docs.openclaw.ai/logging)。

## 工作原理（简短）

```
WhatsApp / Telegram / Slack / Discord / Google Chat / Signal / iMessage / BlueBubbles / Microsoft Teams / Matrix / Zalo / Zalo Personal / WebChat
               │
               ▼
┌───────────────────────────────┐
│            Gateway            │
│       (控制平面)               │
│     ws://127.0.0.1:18789      │
└──────────────┬────────────────┘
               │
               ├─ Pi 代理 (RPC)
               ├─ CLI (openclaw …)
               ├─ WebChat UI
               ├─ macOS 应用
               └─ iOS / Android 节点
```

## 关键子系统

- **[GatewayWebSocket 网络](https://docs.openclaw.ai/concepts/architecture)** — 用于客户端、工具和事件的单一 WS 控制平面（加上运维：[Gateway 运行手册](https://docs.openclaw.ai/gateway)）。
- **[Tailscale 暴露](https://docs.openclaw.ai/gateway/tailscale)** — Serve/Funnel 用于 Gateway 仪表板 + WS（远程访问：[远程](https://docs.openclaw.ai/gateway/remote)）。
- **[浏览器控制](https://docs.openclaw.ai/tools/browser)** — openclaw 管理的 Chrome/Chromium，带有 CDP 控制。
- **[Canvas + A2UI](https://docs.openclaw.ai/platforms/mac/canvas)** — 代理驱动的视觉工作区（A2UI 主机：[Canvas/A2UI](https://docs.openclaw.ai/platforms/mac/canvas#canvas-a2ui)）。
- **[Voice Wake](https://docs.openclaw.ai/nodes/voicewake) + [Talk Mode](https://docs.openclaw.ai/nodes/talk)** — 始终在线语音和连续对话。
- **[节点](https://docs.openclaw.ai/nodes)** — Canvas、相机快照/剪辑、屏幕录制、`location.get`、通知，加上 macOS 专用 `system.run`/`system.notify`。

## Tailscale 访问（Gateway 仪表板）

OpenClaw 可以自动配置 Tailscale **Serve**（仅限 tailnet）或 **Funnel**（公共），而 Gateway 保持绑定到 loopback。配置 `gateway.tailscale.mode`：

- `off`: 无 Tailscale 自动化（默认）。
- `serve`: 通过 `tailscale serve` 的 tailnet-only HTTPS（默认使用 Tailscale 身份头）。
- `funnel`: 通过 `tailscale funnel` 的公共 HTTPS（需要共享密码认证）。

注意：

- 当启用 Serve/Funnel 时，`gateway.bind` 必须保持 `loopback`（OpenClaw 强制执行此）。
- 可以通过设置 `gateway.auth.mode: "password"` 或 `gateway.auth.allowTailscale: false` 强制 Serve 需要密码。
- 除非设置 `gateway.auth.mode: "password"`，否则 Funnel 拒绝启动。
- 可选：`gateway.tailscale.resetOnExit` 在关闭时撤销 Serve/Funnel。

详情：[Tailscale 指南](https://docs.openclaw.ai/gateway/tailscale) · [Web 表面](https://docs.openclaw.ai/web)

## 远程 Gateway（Linux 很棒）

在小型 Linux 实例上运行 Gateway 完全没问题。客户端（macOS 应用、CLI、WebChat）可以通过 **Tailscale Serve/Funnel** 或 **SSH 隧道** 连接，并且你仍然可以配对设备节点（macOS/iOS/Android）以在需要时执行设备本地操作。

- **Gateway 主机** 默认运行 exec 工具和渠道连接。
- **设备节点** 通过 `node.invoke` 运行设备本地操作（`system.run`、相机、屏幕录制、通知）。
  简而言之：exec 在 Gateway 所在处运行；设备操作在设备所在处运行。

详情：[远程访问](https://docs.openclaw.ai/gateway/remote) · [节点](https://docs.openclaw.ai/nodes) · [安全](https://docs.openclaw.ai/gateway/security)

## 通过 Gateway 协议的 macOS 权限

macOS 应用可以以**节点模式**运行，并通过 Gateway WebSocket（`node.list` / `node.describe`）广告其功能 + 权限映射。然后客户端可以通过 `node.invoke` 执行本地操作：

- `system.run` 运行本地命令并返回 stdout/stderr/退出代码；设置 `needsScreenRecording: true` 需要屏幕录制权限（否则你会得到 `PERMISSION_MISSING`）。
- 如果通知被拒绝，`system.notify` 发布用户通知并失败。
- `canvas.*`、`camera.*`、`screen.record` 和 `location.get` 也通过 `node.invoke` 路由，并遵循 TCC 权限状态。

提升的 bash（主机权限）与 macOS TCC 分开：

- 当启用 + 允许列表时，使用 `/elevated on|off` 切换每会话提升访问。
- Gateway 通过 `sessions.patch`（WS 方法）持久化每会话切换，与 `thinkingLevel`、`verboseLevel`、`model`、`sendPolicy` 和 `groupActivation` 一起。

详情：[节点](https://docs.openclaw.ai/nodes) · [macOS 应用](https://docs.openclaw.ai/platforms/macos) · [Gateway 协议](https://docs.openclaw.ai/concepts/architecture)

## 代理对代理（sessions\_\* 工具）

- 使用这些工具跨会话协调工作，而无需在聊天表面之间跳转。
- `sessions_list` — 发现活动会话（代理）及其元数据。
- `sessions_history` — 获取会话的转录日志。
- `sessions_send` — 向另一个会话发送消息；可选的回复 ping-pong + 宣布步骤（`REPLY_SKIP`、`ANNOUNCE_SKIP`）。

详情：[会话工具](https://docs.openclaw.ai/concepts/session-tool)

## 技能注册表（ClawHub）

ClawHub 是一个最小技能注册表。启用 ClawHub 后，代理可以自动搜索技能并在需要时拉入新技能。

[ClawHub](https://clawhub.com)

## 聊天命令

在 WhatsApp/Telegram/Slack/Google Chat/Microsoft Teams/WebChat 中发送这些（组命令仅限所有者）：

- `/status` — 紧凑会话状态（模型 + 令牌，可用时成本）
- `/new` 或 `/reset` — 重置会话
- `/compact` — 紧凑会话上下文（摘要）
- `/think <level>` — off|minimal|low|medium|high|xhigh（仅限 GPT-5.2 + Codex 模型）
- `/verbose on|off`
- `/usage off|tokens|full` — 每响应使用脚注
- `/restart` — 重启 gateway（组中仅限所有者）
- `/activation mention|always` — 组激活切换（仅限组）

## 应用（可选）

仅 Gateway 就能提供很棒的体验。所有应用都是可选的，并添加额外功能。

如果你计划构建/运行伴侣应用，请遵循下面的平台运行手册。

### macOS (OpenClaw.app)（可选）

- Gateway 和健康的菜单栏控制。
- Voice Wake + 一键通覆盖。
- WebChat + 调试工具。
- 通过 SSH 远程控制 gateway。

注意：签名构建是 macOS 权限在重建之间保持所必需的（参见 `docs/mac/permissions.md`）。

### iOS 节点（可选）

- 通过 Bridge 配对为节点。
- 语音触发转发 + Canvas 表面。
- 通过 `openclaw nodes …` 控制。

运行手册：[iOS 连接](https://docs.openclaw.ai/platforms/ios)。

### Android 节点（可选）

- 通过与 iOS 相同的 Bridge + 配对流程配对。
- 暴露 Canvas、相机和屏幕捕获命令。
- 运行手册：[Android 连接](https://docs.openclaw.ai/platforms/android)。

## 代理工作区 + 技能

- 工作区根目录：`~/.openclaw/workspace`（可通过 `agents.defaults.workspace` 配置）。
- 注入的提示文件：`AGENTS.md`、`SOUL.md`、`TOOLS.md`。
- 技能：`~/.openclaw/workspace/skills/<skill>/SKILL.md`。

## 配置

最小 `~/.openclaw/openclaw.json`（模型 + 默认值）：

```json5
{
  agent: {
    model: "anthropic/claude-opus-4-6",
  },
}
```

[完整配置参考（所有键 + 示例）。](https://docs.openclaw.ai/gateway/configuration)

## 安全模型（重要）

- **默认：** 工具在主机上为 **main** 会话运行，因此当只有你时，代理具有完全访问权限。
- **组/渠道安全：** 设置 `agents.defaults.sandbox.mode: "non-main"` 以在每会话 Docker 沙箱中运行**非 main 会话**（组/渠道）；bash 然后在 Docker 中为这些会话运行。
- **沙箱默认值：** 允许列表 `bash`、`process`、`read`、`write`、`edit`、`sessions_list`、`sessions_history`、`sessions_send`、`sessions_spawn`；拒绝列表 `browser`、`canvas`、`nodes`、`cron`、`discord`、`gateway`。

详情：[安全指南](https://docs.openclaw.ai/gateway/security) · [Docker + 沙箱](https://docs.openclaw.ai/install/docker) · [沙箱配置](https://docs.openclaw.ai/gateway/configuration)

### [WhatsApp](https://docs.openclaw.ai/channels/whatsapp)

- 链接设备：`pnpm openclaw channels login`（将凭据存储在 `~/.openclaw/credentials`）。
- 通过 `channels.whatsapp.allowFrom` 允许谁可以与助手交谈。
- 如果设置了 `channels.whatsapp.groups`，它将成为组允许列表；包含 `"*"` 以允许所有。

### [Telegram](https://docs.openclaw.ai/channels/telegram)

- 设置 `TELEGRAM_BOT_TOKEN` 或 `channels.telegram.botToken`（env 获胜）。
- 可选：设置 `channels.telegram.groups`（带有 `channels.telegram.groups."*".requireMention`）；当设置时，它是组允许列表（包含 `"*"` 以允许所有）。还有 `channels.telegram.allowFrom` 或 `channels.telegram.webhookUrl` + `channels.telegram.webhookSecret` 根据需要。

```json5
{
  channels: {
    telegram: {
      botToken: "123456:ABCDEF",
    },
  },
}
```

### [Slack](https://docs.openclaw.ai/channels/slack)

- 设置 `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN`（或 `channels.slack.botToken` + `channels.slack.appToken`）。

### [Discord](https://docs.openclaw.ai/channels/discord)

- 设置 `DISCORD_BOT_TOKEN` 或 `channels.discord.token`（env 获胜）。
- 可选：设置 `commands.native`、`commands.text` 或 `commands.useAccessGroups`，加上 `channels.discord.allowFrom`、`channels.discord.guilds` 或 `channels.discord.mediaMaxMb` 根据需要。

```json5
{
  channels: {
    discord: {
      token: "1234abcd",
    },
  },
}
```

### [Signal](https://docs.openclaw.ai/channels/signal)

- 需要 `signal-cli` 和 `channels.signal` 配置部分。

### [BlueBubbles (iMessage)](https://docs.openclaw.ai/channels/bluebubbles)

- **推荐** iMessage 集成。
- 配置 `channels.bluebubbles.serverUrl` + `channels.bluebubbles.password` 和 webhook（`channels.bluebubbles.webhookPath`）。
- BlueBubbles 服务器在 macOS 上运行；Gateway 可以在 macOS 或其他地方运行。

### [iMessage (旧版)](https://docs.openclaw.ai/channels/imessage)

- 旧版 macOS 专用集成，通过 `imsg`（Messages 必须登录）。
- 如果设置了 `channels.imessage.groups`，它将成为组允许列表；包含 `"*"` 以允许所有。

### [Microsoft Teams](https://docs.openclaw.ai/channels/msteams)

- 配置 Teams 应用 + Bot Framework，然后添加 `msteams` 配置部分。
- 通过 `msteams.allowFrom` 允许谁可以交谈；通过 `msteams.groupAllowFrom` 或 `msteams.groupPolicy: "open"` 进行组访问。

### [WebChat](https://docs.openclaw.ai/web/webchat)

- 使用 Gateway WebSocket；无需单独的 WebChat 端口/配置。

浏览器控制（可选）：

```json5
{
  browser: {
    enabled: true,
    color: "#FF4500",
  },
}
```

## 文档

当你完成入门流程并想要更深入的参考时，使用这些。

- [从文档索引开始导航和"在哪里"。](https://docs.openclaw.ai)
- [阅读架构概述以了解 gateway + 协议模型。](https://docs.openclaw.ai/concepts/architecture)
- [当你需要每个键和示例时，使用完整配置参考。](https://docs.openclaw.ai/gateway/configuration)
- [按照操作运行手册运行 Gateway。](https://docs.openclaw.ai/gateway)
- [了解控制 UI/Web 表面如何工作以及如何安全地暴露它们。](https://docs.openclaw.ai/web)
- [了解通过 SSH 隧道或 tailnet 的远程访问。](https://docs.openclaw.ai/gateway/remote)
- [遵循入门向导流程进行引导设置。](https://docs.openclaw.ai/start/wizard)
- [通过 webhook 表面对接外部触发器。](https://docs.openclaw.ai/automation/webhook)
- [设置 Gmail Pub/Sub 触发器。](https://docs.openclaw.ai/automation/gmail-pubsub)
- [了解 macOS 菜单栏伴侣详情。](https://docs.openclaw.ai/platforms/mac/menu-bar)
- [平台指南：Windows (WSL2)](https://docs.openclaw.ai/platforms/windows)、[Linux](https://docs.openclaw.ai/platforms/linux)、[macOS](https://docs.openclaw.ai/platforms/macos)、[iOS](https://docs.openclaw.ai/platforms/ios)、[Android](https://docs.openclaw.ai/platforms/android)
- [使用故障排除指南调试常见故障。](https://docs.openclaw.ai/channels/troubleshooting)
- [在暴露任何内容之前审查安全指南。](https://docs.openclaw.ai/gateway/security)

## 高级文档（发现 + 控制）

- [发现 + 传输](https://docs.openclaw.ai/gateway/discovery)
- [Bonjour/mDNS](https://docs.openclaw.ai/gateway/bonjour)
- [Gateway 配对](https://docs.openclaw.ai/gateway/pairing)
- [远程 gateway README](https://docs.openclaw.ai/gateway/remote-gateway-readme)
- [控制 UI](https://docs.openclaw.ai/web/control-ui)
- [仪表板](https://docs.openclaw.ai/web/dashboard)

## 运维和故障排除

- [健康检查](https://docs.openclaw.ai/gateway/health)
- [Gateway 锁](https://docs.openclaw.ai/gateway/gateway-lock)
- [后台进程](https://docs.openclaw.ai/gateway/background-process)
- [浏览器故障排除（Linux）](https://docs.openclaw.ai/tools/browser-linux-troubleshooting)
- [日志记录](https://docs.openclaw.ai/logging)

## 深入探讨

- [代理循环](https://docs.openclaw.ai/concepts/agent-loop)
- [存在](https://docs.openclaw.ai/concepts/presence)
- [TypeBox 模式](https://docs.openclaw.ai/concepts/typebox)
- [RPC 适配器](https://docs.openclaw.ai/reference/rpc)
- [队列](https://docs.openclaw.ai/concepts/queue)

## 工作区和技能

- [技能配置](https://docs.openclaw.ai/tools/skills-config)
- [默认 AGENTS](https://docs.openclaw.ai/reference/AGENTS.default)
- [模板：AGENTS](https://docs.openclaw.ai/reference/templates/AGENTS)
- [模板：BOOTSTRAP](https://docs.openclaw.ai/reference/templates/BOOTSTRAP)
- [模板：IDENTITY](https://docs.openclaw.ai/reference/templates/IDENTITY)
- [模板：SOUL](https://docs.openclaw.ai/reference/templates/SOUL)
- [模板：TOOLS](https://docs.openclaw.ai/reference/templates/TOOLS)
- [模板：USER](https://docs.openclaw.ai/reference/templates/USER)

## 平台内部

- [macOS 开发设置](https://docs.openclaw.ai/platforms/mac/dev-setup)
- [macOS 菜单栏](https://docs.openclaw.ai/platforms/mac/menu-bar)
- [macOS voice wake](https://docs.openclaw.ai/platforms/mac/voicewake)
- [iOS 节点](https://docs.openclaw.ai/platforms/ios)
- [Android 节点](https://docs.openclaw.ai/platforms/android)
- [Windows (WSL2)](https://docs.openclaw.ai/platforms/windows)
- [Linux 应用](https://docs.openclaw.ai/platforms/linux)

## 电子邮件钩子（Gmail）

- [docs.openclaw.ai/gmail-pubsub](https://docs.openclaw.ai/automation/gmail-pubsub)

## Molty

OpenClaw 是为 **Molty** 构建的，一个太空龙虾 AI 助手。🦞
由 Peter Steinberger 和社区打造。

- [openclaw.ai](https://openclaw.ai)
- [soul.md](https://soul.md)
- [steipete.me](https://steipete.me)
- [@openclaw](https://x.com/openclaw)

## 社区

参见 [CONTRIBUTING.md](CONTRIBUTING.md) 获取指南、维护者以及如何提交 PR。
欢迎 AI/vibe 编码 PR！🤖

特别感谢 [Mario Zechner](https://mariozechner.at/) 的支持以及
[pi-mono](https://github.com/badlogic/pi-mono)。
特别感谢 Adam Doppelt 的 lobster.bot。

感谢所有 clawtributors：

（贡献者头像列表...）

---

**注意：** 这是 OpenClaw 官方 README 的中文翻译版本。更多详细信息请访问 [官方文档](https://docs.openclaw.ai)。
