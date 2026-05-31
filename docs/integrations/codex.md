# Codex × Doris 集成指南

> **Doris 1.0 起一键注册**。打开菜单栏 Doris → ⚙ 设置 → 应用集成 → Codex 那行 → 点 **注册** 即可。Doris 会接入 Codex 自带的 `notify` 钩子，**Codex 桌面 App 和命令行都生效**——每当一个 Codex 回合（turn）完成，就弹一条 Doris 提醒。
>
> 这份文档讲注册按钮**底下到底干了什么**，以及手动配置 / 排查的方法。日常用户**不用读**。

Codex（OpenAI 的 agentic 编程工具）在 `~/.codex/config.toml` 里提供了一个原生的 **`notify` 钩子**——这正是和 Claude Code 的 `settings.json` hooks 对等的机制。Codex 每完成一个回合就会调用你配置的 `notify` 程序，并把一段 JSON 负载作为最后一个参数传进去。Doris 把自己接到这个钩子上，于是任务一完成就弹 banner。

> **为什么不再用 shell wrapper？** 1.0 之前的版本是往 `~/.zshrc` 里塞一个 `codex()` 函数。那个只在**终端里敲 `codex` 且进程退出**时才触发——对**Codex 桌面 App** 完全无效（App 里任务跑完，进程还活着）。绝大多数人用的是 App，所以 wrapper 形同虚设。`notify` 钩子对 App 和 CLI 都有效，已全面替换掉 wrapper 方案。

---

## 工作原理

Doris CLI 随 App 一起分发（`Doris.app/Contents/Resources/doris`，首次启动会有 wizard 引导把它链接到 `/usr/local/bin/doris`）。`doris notify` 经 App Group 写一条事件给 Doris App，触发 banner。注册要做的，就是让 Codex 在回合结束时去调一个会 fire `doris notify` 的小脚本。

最终的调用链：

```
Codex 回合结束  →  notify 程序  →  Doris 派发脚本  →  doris CLI  →  Doris banner
```

### 和 Codex App 自带通知器共存

带 computer-use 功能的 Codex App 会**接管** `notify` 槽位:它把 `notify[0]` 重置成自己的客户端（`SkyComputerUseClient`），并支持一个 `--previous-notify` 链。当 Doris 把 `notify` 设成自己的派发脚本时，App 会把这个脚本「吸收」成它的下游，于是实际链路变成:

```
Codex  →  SkyComputerUseClient（computer-use 通知）  →  Doris 派发脚本  →  doris CLI
```

也就是说 App 自己的通知器在我们**上游**——所以 Doris 的派发脚本**绝不能反过来再去调它**（否则 App 的通知会弹两次）。派发脚本只 fire Doris banner，从不转发。两边的通知互不干扰。

---

## 注册按钮做的事

点 **设置 → 应用集成 → Codex → 注册** 后，Doris 会：

1. 定位 `doris` CLI 的绝对路径（`/usr/local/bin/doris` 或 bundle 内置那份）
2. 写一个派发脚本 `~/.codex/doris-notify-dispatch.sh`（可执行，里面 baked 了 CLI 路径）
3. 把 `~/.codex/config.toml` 里的 `notify` 指向这个派发脚本
4. 把原本的 `notify` 那一行备份到 `~/.codex/.doris-notify-backup`，供取消注册时**原样还原**
5. 不动 config.toml 里的任何其他内容

点 **取消注册** 会还原原来的 `notify`（没有就删掉该行），并删除派发脚本与备份。

> Codex App 在运行时会把上面第 3 步的 `notify` 自动改写成「`SkyComputerUseClient` 在前、Doris 派发脚本作为 `--previous-notify`」的规范形态——这是预期行为，不用管。

---

## 手动配置（不走 Doris UI）

### 步骤 1：确认 CLI 在

```bash
which doris && doris --version
```

没结果的话先装 CLI（见下方「没装 CLI」）。

### 步骤 2：写派发脚本

新建 `~/.codex/doris-notify-dispatch.sh`：

```bash
#!/bin/bash
# 每个 Codex 回合结束都会被调一次。只 fire Doris，不转发。
DORIS_CLI="/usr/local/bin/doris"   # 或 Doris.app/Contents/Resources/doris
if [ -x "$DORIS_CLI" ]; then
    "$DORIS_CLI" notify \
        --title 'Codex 任务完成' \
        --source codex \
        --level reminder \
        --click-url 'doris://main' >/dev/null 2>&1 &
fi
exit 0
```

```bash
chmod +x ~/.codex/doris-notify-dispatch.sh
```

### 步骤 3：把 config.toml 的 notify 指过去

编辑 `~/.codex/config.toml`，加（或改）这一行到顶部、第一个 `[表]` 之前：

```toml
notify = ["/Users/<你>/.codex/doris-notify-dispatch.sh"]
```

如果之前 `notify` 已经有值（比如 Codex App 的 `SkyComputerUseClient`），**先记下原值**以便日后还原。保存后，运行中的 Codex App 会自动把你的脚本吸收成 `--previous-notify`——这是正常的。

### 步骤 4：测试

跑一个真实的 Codex 回合（在 App 里发一条消息，或命令行 `codex exec "say hi"`）。回合结束应弹出一条 reminder banner「Codex 任务完成」。

也可以直接验证派发脚本本身：

```bash
~/.codex/doris-notify-dispatch.sh '{"type":"agent-turn-complete"}'
```

立刻弹 banner 就说明脚本通。

---

## 没装 CLI

如果 `which doris` 没结果：

1. 打开 Doris.app
2. 菜单栏图标 → ⚙ 设置 → **应用集成** → 找 CLI 安装入口
3. 或菜单栏顶部 **Doris → Install CLI…**

详情看 [CLI Manual](../cli-manual.md)。

---

## 故障排查

### 没弹 banner

逐项确认：

```bash
pgrep -f Doris.app                    # Doris 在跑？
which doris && doris --version        # CLI 装好？
grep '^notify' ~/.codex/config.toml   # notify 指向 doris-notify-dispatch.sh？
ls -l ~/.codex/doris-notify-dispatch.sh   # 脚本存在且可执行？
```

绕过整条链，直接测 CLI ↔ App 通信：

```bash
doris notify --title test --source codex --level reminder
```

应立刻弹 banner。连这个都没反应 → 问题在 Doris ↔ CLI（看 [CLI Manual](../cli-manual.md) → 「故障排查」）；通知权限也查一下：系统设置 → 隐私与安全性 → 通知 → Doris。

### config.toml 里的 notify 被 Codex App 改写了

这是**正常**的。带 computer-use 的 Codex App 会把 `notify[0]` 设回它自己的客户端，并把 Doris 的派发脚本挂到 `--previous-notify` 上。只要 `grep doris-notify-dispatch ~/.codex/config.toml` 还能搜到这个脚本，链路就是通的。

### banner 弹了两次

说明派发脚本里在反向转发到 `SkyComputerUseClient`。新版派发脚本**不应该**有任何转发——重新点一次「注册」让 Doris 重写脚本即可。

### Banner 点击没反应

`--click-url 'doris://main'` 让 banner 打开 Doris 主窗口。想点了开 Codex 网页版就把它换成 `--click-url 'https://chatgpt.com/codex'`，再重新注册。

---

## 和 Claude Code 的对照

| | Claude Code | Codex |
|---|---|---|
| 钩子位置 | `~/.claude/settings.json` 的 `hooks` | `~/.codex/config.toml` 的 `notify` |
| 触发时机 | 每次回复 / Stop 事件 | 每个回合（turn）完成 |
| Doris 接入 | 注入一段 `doris notify` hook | `notify` 指向 Doris 派发脚本 |
| 自动注册 | ✅ `.full` | ✅ `.full` |

两者现在都是 `.full` 一键注册。
