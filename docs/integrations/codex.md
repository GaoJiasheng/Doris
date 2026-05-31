# Codex × Doris 集成指南

> **Doris 1.0 起已经支持一键注册**。打开菜单栏 Doris → ⚙ 设置 → 应用集成 → Codex 那行 → 点 **注册** 按钮就完事。Doris 会自动检测你的 shell（zsh / bash / fish），把下面的 wrapper 函数写进对应的 rc 文件里。**新开一个 terminal 窗口**就生效。
>
> 这份文档介绍的是注册按钮**底下到底干了什么**，以及如果想自己定制的高级玩法。日常用户**不用读**。

Codex（OpenAI 的 agentic 编程工具）目前没有公开的 hooks API，**没法像 Claude Code 那样从 settings.json 走 hook**。退而求其次的方案是用一个 shell wrapper —— 把 `codex` 命令包一层，让它跑完之后自动 fire 一次 Doris banner。这样你启动一个长任务后切去干别的，跑完会有提示。

完整流程 **零步**（点注册按钮）/ 手动也只要 **2 分钟**。

---

## 工作原理

Doris CLI 装在 `/usr/local/bin/doris`（首次启动 Doris 会有 wizard 引导安装）。`doris notify` 会经 App Group 写一条事件给 Doris App，触发 banner。我们要做的就是把它接到 `codex` 命令的结尾。

最终效果：

```bash
$ codex "implement a binary search"
... (Codex 跑代码 / 思考 / 几分钟)
✅ Codex 完成   ← Doris banner 弹出，点击切回终端
```

---

## 注册按钮做的事

点 **设置 → 应用集成 → Codex → 注册** 后，Doris 会：

1. 读 `$SHELL` 判断你的 shell — zsh / bash / fish
2. 打开对应的 rc 文件（`~/.zshrc` / `~/.bashrc` / `~/.config/fish/config.fish`）
3. 在末尾插入下面的标记块（已存在则原地刷新，不重复堆叠）
4. 不会动 rc 文件里你已有的任何其他内容

之后只要**新开 terminal 窗口**（或 `source` 一下 rc 文件），`codex` 命令就被 wrapper 接管。点 **取消注册** 会精确删除这个块，其他内容原封不动。

下面是**手动**配置的步骤（仅供想知道细节 / 不用 Doris UI 注册的用户参考）。

---

## 步骤 1：选你用的 shell

```bash
echo $SHELL
```

输出 `/bin/zsh` → 编辑 `~/.zshrc`
输出 `/bin/bash` → 编辑 `~/.bashrc`（或 `~/.bash_profile`）
输出 `/opt/homebrew/bin/fish` → 编辑 `~/.config/fish/config.fish`

## 步骤 2：加 wrapper 函数

### Zsh / Bash

在 `~/.zshrc`（或对应文件）末尾加：

```bash
# Codex × Doris — fire a banner when codex exits, regardless of success.
codex() {
    command codex "$@"
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        doris notify \
            --title "Codex" \
            --body "任务完成" \
            --source codex \
            --level reminder \
            --click-url "doris://main"
    else
        doris notify \
            --title "Codex" \
            --body "退出代码 $exit_code" \
            --source codex \
            --level critical \
            --click-url "doris://main"
    fi
    return $exit_code
}
```

### Fish

`~/.config/fish/config.fish` 里加：

```fish
function codex
    command codex $argv
    set -l exit_code $status
    if test $exit_code -eq 0
        doris notify \
            --title "Codex" \
            --body "任务完成" \
            --source codex \
            --level reminder \
            --click-url "doris://main"
    else
        doris notify \
            --title "Codex" \
            --body "退出代码 $exit_code" \
            --source codex \
            --level critical \
            --click-url "doris://main"
    end
    return $exit_code
end
```

## 步骤 3：重载配置

```bash
# zsh
source ~/.zshrc

# bash
source ~/.bashrc

# fish
source ~/.config/fish/config.fish
```

或者直接开个新 terminal 窗口。

## 步骤 4：测试

```bash
codex --version
```

应该立刻看到一个绿色（reminder level）banner 弹出："Codex / 任务完成"。如果有，配置成功。

故意制造一次失败：

```bash
codex --this-flag-does-not-exist
```

应该看到红色 critical banner "Codex / 退出代码 1"。

---

## 进阶：只在长任务后通知

不想每次 `codex --version` / `codex --help` 都弹 banner？加个时间阈值——只有跑超过 **N 秒**才提醒：

### Zsh / Bash

```bash
codex() {
    local start=$(date +%s)
    command codex "$@"
    local exit_code=$?
    local elapsed=$(($(date +%s) - start))

    # 跑不到 10 秒的任务不打扰
    if [ $elapsed -ge 10 ]; then
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))
        local body="${mins}m${secs}s"
        if [ $exit_code -eq 0 ]; then
            doris notify --title "Codex 完成" --body "$body" \
                --source codex --level reminder --click-url "doris://main"
        else
            doris notify --title "Codex 失败" --body "$body · exit $exit_code" \
                --source codex --level critical --click-url "doris://main"
        fi
    fi
    return $exit_code
}
```

### Fish

```fish
function codex
    set -l start (date +%s)
    command codex $argv
    set -l exit_code $status
    set -l elapsed (math (date +%s) - $start)

    if test $elapsed -ge 10
        set -l mins (math $elapsed / 60)
        set -l secs (math $elapsed % 60)
        set -l body "$mins"m"$secs"s
        if test $exit_code -eq 0
            doris notify --title "Codex 完成" --body $body \
                --source codex --level reminder --click-url "doris://main"
        else
            doris notify --title "Codex 失败" --body "$body · exit $exit_code" \
                --source codex --level critical --click-url "doris://main"
        end
    end
    return $exit_code
end
```

---

## 没装 CLI

如果 `which doris` 没结果：

1. 打开 Doris.app
2. 顶部菜单栏图标 → ⚙ 设置 → **应用集成** → 找 CLI 安装入口
3. 或者直接菜单栏顶部 **Doris → Install CLI…**

详情看 [CLI Manual](../cli-manual.md)。

---

## 故障排查

### 没弹 banner

确认 Doris 在跑 → `pgrep Doris`
确认 CLI 装好 → `which doris && doris --version`
确认通知权限 → 系统设置 → 隐私与安全性 → 通知 → Doris

直接跑 CLI 测试，绕过 wrapper：

```bash
doris notify --title test --source codex --level reminder
```

应该立刻弹 banner。如果连这个都没反应，问题在 Doris ↔ CLI 通信（看 [CLI Manual](../cli-manual.md) → "故障排查"）。

### `codex` 被无限递归调用

如果 wrapper 写错（漏了 `command codex`），shell 会无限递归。

修复：直接编辑配置文件删掉/改对 wrapper，重启 shell。在没修好之前可以用 `\codex "$@"` 绕过别名 / `/path/to/codex` 走绝对路径。

### Banner 点击没反应

`--click-url "doris://main"` 让 banner 打开 Doris 主窗口。如果你想点了直接打开 Codex 网页版：

```bash
--click-url "https://codex.openai.com"
```

---

## 为什么不能像 Claude Code 一样自动？

Claude Code 暴露了 `~/.claude/settings.json` 里的 `hooks` 字段，让 Doris 注入一段 `doris notify` 命令在每次 Claude 回复后自动跑（具体看 Doris → 设置 → 应用集成 → Claude Code 那行右边的"已注册"状态）。

Codex 目前**没有等价机制**。OpenAI 团队提了类似 issue，但还在 roadmap 上。一旦上线，Doris 的 `CodexIntegration` 会从 `.manual` 升级到 `.full`，到时这份文档可以删掉。
