# ChatGPT × Doris 集成指南

ChatGPT 桌面 App 没有公开的 hooks / 回调接口，所以无法像 Claude Code 那样自动通知 Doris。最干净的方式是用 **macOS 快捷指令（Shortcuts）** 给 ChatGPT 加一个手动触发的"完成通知"按钮：你回到 Doris 之前点一下快捷指令，Doris 就会弹一个 banner，让你不会忘记切回去看 ChatGPT 的回复。

完整流程大约 **3 分钟**。

---

## 工作原理

Doris 监听一个自定义 URL Scheme：

```
doris://notify?title=<title>&body=<body>&source=chatgpt&level=info&click=chatgpt://
```

任何能 `open URL` 的工具（Shortcuts / shell / Raycast / Alfred / 浏览器书签）都能触发 Doris banner。`click=chatgpt://` 让 banner 点击后切回 ChatGPT，无需手动 Dock 切换。

---

## 步骤 1：创建快捷指令

1. 打开 macOS 自带的 **快捷指令.app**（Spotlight 搜 `Shortcuts`）
2. 点左上角 **+** 新建快捷指令，命名为 **`ChatGPT 完成`**
3. 从右侧操作库里搜 **"打开 URL"**，拖进编辑区
4. 把 URL 字段粘贴成：

```
doris://notify?title=ChatGPT&body=回复已就绪&source=chatgpt&level=info&click=chatgpt://
```

> **可选定制**：
> - `body=...` 改成你想要的说明文字（URL 编码后粘贴）
> - `level=reminder` 把图标从灰色 info 变成醒目橙色（适合长任务）
> - `level=critical` 红色高优先级（不推荐用在 ChatGPT 上）

5. 按 ⌘S 保存。

## 步骤 2：给快捷指令绑全局快捷键

最快的触发方式 — 一个键搞定：

1. 打开 **系统设置 → 键盘 → 键盘快捷键 → 服务**
2. 在列表里找到刚才创建的"ChatGPT 完成"
3. 点右侧空白处，按下你想用的组合键（推荐 `⌃⌥⌘C`，跟 ChatGPT 的 C 对应）
4. 关掉系统设置

或者更简单，直接在快捷指令.app 里：
- 选中 `ChatGPT 完成` → 右侧 **i** 图标 → **添加键盘快捷键**

## 步骤 3：使用流程

1. 在 ChatGPT 里发出 prompt
2. 切到其他 App 干别的（写代码 / 看文档 ...）
3. ChatGPT 回复完，回去看一眼，按下 **`⌃⌥⌘C`** —— Doris 弹 banner
4. 之后看到 banner，点一下 → 回到 ChatGPT 接着用

---

## 进阶玩法

### 用菜单栏图标快速触发

不想记快捷键？

1. 快捷指令.app → 选中 `ChatGPT 完成` → 右侧 **i** 图标
2. 勾选 **"在菜单栏中固定"**
3. 现在菜单栏会出现快捷指令小图标，下拉点 `ChatGPT 完成` 也能触发

### 跟焦点（Focus）联动

如果你用 macOS 的 **专注模式**（比如"工作"专注），可以把这个快捷指令塞进焦点的"快捷指令"列表，让 Doris banner 即使在专注模式下也能正常显示（Doris 默认会被普通通知过滤掉，但 banner 是 Doris 自己渲染的，不走系统通知中心，所以已经免疫）。

### 让 Raycast / Alfred 触发

Raycast 用户：在 Raycast 设置 → Extensions → Shortcuts，找到 `ChatGPT 完成`，给它配个 alias（比如 `gpt`）。打字就触发，比快捷键还方便。

---

## 测试

打开 Terminal 跑一下：

```bash
open "doris://notify?title=Test&body=From%20Terminal&source=chatgpt&click=chatgpt://"
```

应该立刻看到 Doris banner 弹出（顶部菜单栏附近）。点它会切到 ChatGPT。如果**没**弹出，参考"故障排查"。

---

## 故障排查

### Banner 不弹

- 确认 **Doris 在跑**（菜单栏看得见图标）
- 确认 Doris 的 **iCloud / 通知权限**没被禁用（设置 → 隐私与安全性 → 通知 → Doris）
- 检查 URL 没拼错 — 至少要有 `title`，缺了它 Doris 会静默丢弃请求
- 在 Terminal 直接跑上面的测试命令；如果连这条都不弹，说明 URL Scheme 注册有问题（重启 Doris 一次再试）

### 弹了但 banner 点了没切到 ChatGPT

- `click=chatgpt://` 这个 scheme 是 ChatGPT 桌面 App 注册的
- 没装 ChatGPT 桌面 App 的话改成 `click=https://chatgpt.com`，会用默认浏览器打开

### 想要更多 banner 样式

`level` 参数：
- `info`（默认）— 灰色，不打扰
- `reminder` — 橙色，长事件提醒
- `critical` — 红色，高优先级

`mode` 参数：
- `banner`（默认）— 短暂弹出后自动消失
- `fix` — 固定显示，需要手动点掉

举例：
```
doris://notify?title=ChatGPT&body=长任务跑完了&source=chatgpt&level=reminder&mode=fix&click=chatgpt://
```

---

## 为什么不能像 Claude Code 一样自动？

Claude Code 提供了 [Hooks API](https://docs.claude.com/en/docs/claude-code/hooks)，允许 Doris 注入一段 shell 命令在每次 Claude 回复后跑（具体见 Doris → 设置 → 应用集成 → Claude Code）。OpenAI 的 ChatGPT 桌面 App **目前没有等价的接口**，所以只能靠用户手动触发。

如果 OpenAI 以后开放类似 API，Doris 的 `ChatGPTIntegration` 会从 `.manual` 升级到 `.full`，到时候就不需要这份文档了。
