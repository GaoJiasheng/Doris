# 界面文案

两个平台、两种语言的界面文字都写在代码里的 `L("English", "中文")`。这份文档的上半部分是用词和写法规范，是手写的；下半部分是全部文案的清单，由 `./scripts/copy-inventory.py` 从代码重新生成。改了文案后，重新跑一次这个脚本。

## 用词

| 概念 | 中文 | English | 不要用 |
|---|---|---|---|
| 一条要做的事 | 任务 | task | 笔记、条目（清单里的子项除外） |
| 主列表页 / 标签 | 待办 | To-dos | TODO、笔记 / Notes |
| 任务里的勾选子项 | 条目 | item | 行 |
| 数量（小组件等） | N 件待办 | N to do | |
| 首页 / 今日卡片 | 今日 | Today | |
| 日期本身 | 今天、明天 | Today, Tomorrow | 今日（当日期用时） |
| 截止日期 | 截止日期 / 截止 | due date / Due | 日期（单独用） |
| 置顶区 / 到期区 | 置顶 / 日程 | Pinned / Upcoming | Due（当区名用） |
| 新建 | 添加任务、添加条目 | Add task, Add item | 新增任务 |
| 从归档或回收站拿回来 | 恢复 | Restore | 还原 |
| 取消归档 | 取消归档 | Unarchive | 解归档、回到活动 |
| 勾选完成 / 取消 | 标为已完成 / 标为未完成 | Mark as done / Mark as not done | 标记完成、取消完成（滑动按钮除外） |
| 进回收站 | 移到回收站 | Move to trash | |
| 永久删除（只在回收站里） | 彻底删除 | Delete forever | |
| iCloud 开关状态 | iCloud 同步未开启 | iCloud sync is off | 未启用 |
| 同步失败 | 同步失败 | Sync failed | 同步错误（标题里） |
| 从没同步过 | 尚未同步 | Never synced | Never synced yet |
| 自动同步 | 每分钟自动同步 | Auto-sync every minute | 每 60 秒 |

## 写法

- **中文标点用全角**：，。？：；（）「」。路径、命令、代码（`~/.claude.json`、`sudo mkdir -p`）保持原样。
- **中文里的引用**用「」，不用英文引号。
- **说清楚真实行为**。回收站里的任务 24 小时后自动清除，不要写「清空之前都能恢复」；编辑器里的按钮是归档，不要写「删除」或「无法撤销」。
- **Mac 上写「点击」，iOS 上写「点」/ Tap**。共用组件只出现在一个平台时，按那个平台写。
- **英文**：按钮和菜单项保持各处一致，同一个动作只用一种说法；说明文字用完整句子。
- 不对用户讲实现细节（CloudKit、record、刷写），讲用户能感知到的结果。

## 不在 `L()` 里的文字

- **系统权限说明**（`project.yml` 里的 `NS…UsageDescription`）：iOS 相机说明是中英双语写在一句里；Mac 的麦克风和语音识别说明只有英文。系统按 App 本地化取这些文字，要分语言需要加 `InfoPlist.strings`。
- **通知标题**（专注结束、今天到期、Claude / Codex 任务完成）和 agent 改动提示（`AgentActivityAnnouncer`）各自按语言判断，也已经是中英两套。
- **Mac 的分享扩展和小组件**目前没有打进 App，里面的英文没有处理。

<!-- generated below: ./scripts/copy-inventory.py -->

668 strings. Duplicates within a file are listed once.

## iOS

### `CalendarTimelineScreen.swift`

| English | 中文 |
|---|---|
| Overdue | 已逾期 |
| Today | 今天 |
| Tomorrow | 明天 |
| Unscheduled | 未排期 |
| Timeline | 时间轴 |
| AGENDA | 日程 |
| Nothing scheduled | 暂无安排 |
| Give a task a due date to see it on the timeline. | 给任务设定截止日期，就会出现在时间轴上。 |
| Untitled | 无标题 |

### `EventsScreen.swift`

| English | 中文 |
|---|---|
| Mark as read | 标为已读 |
| Dismiss | 忽略 |
| Delete | 删除 |
| Events | 事件 |
| No events yet | 暂无事件 |
| Pull down to sync now. | 下拉以立即同步。 |

### `NoteDetailHost.swift`

| English | 中文 |
|---|---|
| Task not found | 任务不存在 |

### `NoteDetailScreen.swift`

| English | 中文 |
|---|---|
| Title | 标题 |
| Mark as not done | 标为未完成 |
| Mark as done | 标为已完成 |
| Insert Image | 插入图片 |
| Archive | 归档 |
| Archive this task? | 归档这个任务？ |
| Cancel | 取消 |
| It moves to Archived and stays there until you delete it. You can restore it any time. | 任务会移到「已归档」，一直保留到你手动删除，随时可以恢复。 |
| Pinned | 置顶 |
| Checklist | 清单 |
| Due | 截止 |
| Done | 已完成 |
| Created  | 创建于  |
| Due date | 截止日期 |
| Clear due date | 清除截止日期 |
| Set due date | 设置截止日期 |
| Done | 完成 |

### `NotesScreen.swift`

| English | 中文 |
|---|---|
| Done | 完成 |
| cyber helper | 赛博助手 |
| Not done | 取消完成 |
| Unpin | 取消置顶 |
| Pin | 置顶 |
| Mark as not done | 标为未完成 |
| Mark as done | 标为已完成 |
| Set due date | 设置截止日期 |
| Stop focus | 停止专注 |
| \(m) min | \(m) 分钟 |
| Start focus | 开始专注 |
| Archive | 归档 |
| Due date | 截止日期 |
| Clear due date | 清除截止日期 |
| Search tasks… | 搜索任务… |
| Archive done (\(doneActiveCount)) | 归档已完成 (\(doneActiveCount)) |
| Archived | 已归档 |
| Local only | 仅本地 |
| Never synced | 尚未同步 |
| Synced · just now | 已同步 · 刚刚 |
| Synced  | 已同步  |
| No tasks yet | 暂无任务 |
| No results | 无搜索结果 |
| Tap + to add one. Pull down to sync. | 点 + 添加任务，下拉可同步。 |
| No archived tasks | 暂无归档任务 |
| Untitled | 无标题 |
| Restore | 恢复 |
| Delete | 删除 |
| Delete All | 全部删除 |
| [Image] | [图片] |
| DONE | 已完成 |

### `QuickActions.swift`

| English | 中文 |
|---|---|
| Today | 今天 |
| Tomorrow | 明天 |
| No date | 不设日期 |
| What needs doing? | 要做什么？ |
| A title for this photo (optional) | 给这张照片起个标题（可不填） |
| Due | 截止 |
| Add task | 添加任务 |
| Photo Task | 拍照记一条 |
| Cancel | 取消 |
| Add | 添加 |
| en_US | zh_CN |
| 'Photo' MMM d, HH:mm | '照片' M月d日 HH:mm |
| Length | 时长 |
| \($0) min | \($0) 分钟 |
| Today | 今日 |
| Other tasks | 其他任务 |
| Focus | 专注 |
| Just focus — no task | 自由专注（不绑定任务） |
| Start a Focus | 开始专注 |
| Untitled | 无标题 |

### `RootTabView.swift`

| English | 中文 |
|---|---|
| Today | 今日 |
| To-dos | 待办 |
| Events | 事件 |
| Settings | 设置 |

### `SettingsScreen.swift`

| English | 中文 |
|---|---|
| Settings | 设置 |
| Theme | 主题 |
| Appearance | 外观 |
| Dark is the neon cyber look. Light is a bright version: white cards, deeper accents that stay readable. | 深色是霓虹赛博风格；浅色是明亮版本，白色卡片，强调色加深以保证清晰可读。 |
| Display | 显示 |
| Language | 语言 |
| Switch the interface between English and Chinese. | 在英文和中文之间切换界面。 |
| Use iCloud sync | 使用 iCloud 同步 |
| Auto-sync every minute | 每分钟自动同步 |
| Sync | 同步 |
| Not the Production database — this build syncs with a separate dataset your other devices don't read. | 不是 Production 数据库 —— 此构建同步到一份独立数据，其他设备读不到。 |
| Restart Doris after turning iCloud on or off. | 开关 iCloud 后需重启 Doris 才能生效。 |
| Local only. Your tasks stay on this device. | 仅本地存储，任务不会离开本机。 |
| Version | 版本 |
| About | 关于 |
| Syncing… | 同步中… |
| Sync Now | 立即同步 |
| Never synced | 尚未同步 |

### `TodayScreen.swift`

| English | 中文 |
|---|---|
| Pinned | 置顶 |
| Long-term | 长期 |
| Upcoming | 日程 |
| TODAY | 今日 |
| All clear | 今日清净 |
| Pin a task or give it a due date to see it here. | 置顶任务或设定截止日期，就会出现在这里。 |

### `EventsWidget.swift`

| English | 中文 |
|---|---|
| Doris · Events | Doris · 事件 |
| Recent notifications. | 最近收到的通知。 |
| No events yet | 暂无事件 |

### `TasksWidget.swift`

| English | 中文 |
|---|---|
| Doris · Today | Doris · 今日 |
| Pinned and today's tasks — tap one to tick it off. | 置顶 + 今日任务，点一下即可勾选完成。 |
| Untitled | 无标题 |
| Pinned | 置顶 |
| Upcoming | 日程 |
| Add | 添加 |
| Focus | 专注 |
| Photo | 拍照 |
| Later | 之后 |
| Nothing due today | 今天没有待办 |
| +\(hidden) more | +\(hidden) 更多 |
| \(laterLeft) more later | 之后还有 \(laterLeft) 项 |
| \(laterLeft) later | 之后 \(laterLeft) 项 |
| to do | 件待办 |
| \(entry.laterTotal) later | 之后 \(entry.laterTotal) 项 |
| \(entry.openCount) to do | \(entry.openCount) 件待办 |

## macOS

### `AnchorView.swift`

| English | 中文 |
|---|---|
| cyber helper | 赛博助手 |
| Today | 今日 |
| To-dos | 待办 |
| Events | 事件 |
| No events yet | 暂无事件 |
| No tasks yet | 暂无任务 |
| No archived tasks | 暂无归档任务 |
| Trash is empty | 回收站为空 |
| Active | 未归档 |
| Archived | 已归档 |
| Trash | 回收站 |
| Empty trash? | 清空回收站？ |
| Empty (\(trashCount)) | 清空 (\(trashCount)) |
| Cancel | 取消 |
| Items in the trash will be permanently deleted and can't be recovered. | 回收站中的任务将被彻底删除，无法恢复。 |
| Archive done (\(doneActiveCount)) | 归档已完成 (\(doneActiveCount)) |
| Move all completed tasks to archive | 把所有已完成任务移到归档 |
| Permanently delete every item in trash | 彻底删除回收站中所有任务 |
| Add task | 添加任务 |
| Pinned | 置顶 |
| Upcoming | 日程 |
| All clear | 今日清净 |
| Pin a task or give it a due date to see it here. | 置顶任务或设定截止日期，就会出现在这里。 |

### `DesktopPetController.swift`

| English | 中文 |
|---|---|
| Doris — drag to move · right-click for settings | Doris — 拖动可移动 · 右键打开设置 |
| Open Main Window | 打开主窗口 |
| Sync Now | 立即同步 |
| Settings… | 设置… |
| Quit Doris | 退出 Doris |

### `MenuBarAvatarWindow.swift`

| English | 中文 |
|---|---|
| Open Main Window | 打开主窗口 |
| Sync Now | 立即同步 |
| Settings… | 设置… |
| Quit Doris | 退出 Doris |

### `SettingsWindow.swift`

| English | 中文 |
|---|---|
| Doris · Settings | Doris · 设置 |
| Couldn't change the integration | 没能完成接入设置 |
| OK | 好 |
| Sync | 同步 |
| Use iCloud sync | 使用 iCloud 同步 |
| Auto-sync every minute | 每分钟自动同步 |
| Sync Now saves your changes and checks that iCloud is reachable; "Last synced" only updates when both succeed. Restart Doris after turning iCloud on or off. | 「立即同步」会保存改动并确认 iCloud 可以连上，两步都成功才会更新「上次同步」时间。开关 iCloud 后需重启 Doris 才能生效。 |
| App integrations | 应用集成 |
| Route task-completion notifications from Claude Code and Codex through Doris instead of the system Notification Center. | 把 Claude Code 和 Codex 的「任务完成」通知改走 Doris，绕过系统通知中心。 |
| Agents (MCP) | Agent 接入(MCP) |
| Let AI agents on this Mac read and update your tasks — "add a to-do", "what's left today", ticking off steps as they work. Nothing can be deleted, and every change shows in the notch. | 让这台 Mac 上的 AI agent 读写你的任务：「记一个待办」「今天还剩什么」，边干活边勾掉步骤。不能删除任何东西，每次改动都会在刘海提示。 |
| Agents can change tasks | 允许 agent 修改任务 |
| Off: agents can only read your tasks. | 关闭后 agent 只能查看，不能新建或修改。 |
| Tell agents when to use Doris | 告诉 agent 何时用 Doris |
| Adds a short, marked section to CLAUDE.md / AGENTS.md so agents think of Doris when you say "remind me…". Removed when you turn this off. | 在 CLAUDE.md / AGENTS.md 里加一小段带标记的说明，让 agent 听到「记一下」时想到 Doris。关闭即移除。 |
| Copy config for other apps | 复制配置（给其他应用） |
| Copied | 已复制 |
| Claude Desktop, Cursor, LM Studio and others: paste it into their MCP settings. | Claude Desktop、Cursor、LM Studio 等：粘贴到它们的 MCP 设置里。 |
| Doris CLI not installed — finish the install wizard first. | Doris CLI 还没装，请先完成安装向导。 |
| It points at a doris that's gone (\(path)). | 指向的 doris 已不存在(\(path))。 |
| The hook can't run doris (\(path)) — notifications aren't arriving. | 钩子无法运行 doris(\(path))，通知收不到。 |
| Auto-write a Stop hook into ~/.claude/settings.json. | 自动写入 Stop 钩子到 ~/.claude/settings.json。 |
| Auto-wire Codex's notify hook in ~/.codex/config.toml. | 自动接入 ~/.codex/config.toml 的 notify 钩子。 |
| Adds Doris to ~/.claude.json. Reopen running Claude Code sessions to use it. | 写入 ~/.claude.json。正在运行的 Claude Code 会话重开后生效。 |
| Adds Doris to ~/.codex/config.toml. New Codex sessions can use it. | 写入 ~/.codex/config.toml。新开的 Codex 会话即可使用。 |
| Connected | 已接入 |
| Registered | 已注册 |
| Disconnect | 断开 |
| Unregister | 取消注册 |
| Install CLI… | 安装 CLI… |
| Connect | 接入 |
| Register | 注册 |
| Repair | 修复 |
| Retry | 重试 |
| Manual | 手动配置 |
| Tutorial → | 查看教程 → |
| Not supported | 暂不支持 |
| Theme | 主题 |
| Mode | 模式 |
| Dark is the neon cyber look. Light is a bright version with white cards and deeper, readable accents. Colours follow the character you pick, and the sun/moon button flips between them anywhere in the app. | 深色是霓虹赛博风格；浅色是明亮版本，白色卡片，强调色加深以保证清晰可读。配色随所选形象变化，随处可点太阳/月亮按钮一键切换。 |
| Language | 语言 |
| Display | 显示 |
| Switch the interface between English and Chinese. | 在英文和中文之间切换界面。 |
| Voice | 语音 |
| Enabled | 启用 |
| Add binding | 添加绑定 |
| Hold a trigger key, speak, release. Doris transcribes locally with Apple Speech, then activates the chosen app and pastes (with optional auto-submit). Press Esc anytime to abort. First use prompts for Microphone, Speech Recognition, Input Monitoring, and Accessibility. | 按住触发键说话，松开后 Doris 用 Apple Speech 本地转写，自动前置目标 App 并粘贴（可选自动回车）。任何时候按 Esc 可终止录音。首次使用会逐步请求麦克风、语音识别、输入监听及辅助功能权限。 |
| Trigger | 触发键 |
| Send to | 发送给 |
| Submit | 回车 |
| Window | 窗口 |
| Avatar placement | 助手位置 |
| Screen edge | 贴边 |
| Desktop pet | 桌面 |
| Pet size | 桌宠大小 |
| Small | 小 |
| Medium | 中 |
| Large | 大 |
| Desktop panel | 桌面面板 |
| The desktop panel floats your pinned and today's tasks on the desktop. To stick a single task there, right-click it → Stick to desktop. | 桌面面板会在桌面上浮出「置顶 + 今日」的任务汇总。想把单个任务贴到桌面：右键该任务 →「贴到桌面」。 |
| Appearance | 外观 |
| Character | 形象 |
| Pick the character Doris uses — its animation, portrait, menu-bar mark and colour theme switch with it. | 选择 Doris 的形象 —— 动画、头像、刘海图标与配色主题随之切换。 |
| Background opacity | 背景不透明度 |
| On the notch extension (top edge of a notched display) the avatar always renders as solid black so it fuses with the real notch — this slider has no effect there. On every other edge, the avatar background uses this opacity. | 在刘海扩展形态（带刘海屏幕的顶部）下，头像始终渲染为纯黑以与真刘海融合，此滑块无效。其它边缘下，头像背景采用该不透明度。 |
| Remove this binding | 删除此绑定 |
| Sync failed | 同步失败 |
| iCloud sync is off | iCloud 同步未开启 |
| Not synced yet | 尚未同步 |
| In sync with iCloud | 已与 iCloud 同步 |
| Your tasks stay on this Mac. Turn on iCloud below to sync them to your other devices. | 任务仅保存在本机。在下方开启 iCloud 即可与其他设备同步。 |
| Click Sync Now below to start syncing. | 点击下方「立即同步」开始第一次同步。 |
| Last synced  | 上次同步  |
| Syncing… | 同步中… |
| Sync Now | 立即同步 |
| Never synced | 尚未同步 |

### `AppDelegate.swift`

| English | 中文 |
|---|---|
| Break over | 休息结束 |
| Focus done | 专注结束 |

### `InstallCLIWizardView.swift`

| English | 中文 |
|---|---|
| Install the `doris` CLI | 安装 `doris` 命令行工具 |
| This will symlink the CLI bundled inside Doris.app to /usr/local/bin/doris so you can run `doris notify ...` from any shell. | 这会把 Doris.app 内置的 CLI 符号链接到 /usr/local/bin/doris，这样你在任意 shell 里都能跑 `doris notify ...`。 |
| Install to /usr/local/bin | 安装到 /usr/local/bin |
| Install to ~/.local/bin | 安装到 ~/.local/bin |
| Skip | 跳过 |
| Could not locate the bundled CLI. | 找不到 app 内置的 CLI。 |
| Could not create \(parent). You may need to run: sudo mkdir -p \(parent) | 无法创建 \(parent)。可能需要手动运行：sudo mkdir -p \(parent) |
| Installed to \(dest) | 已安装到 \(dest) |
| Failed: \(error.localizedDescription). You may need to install manually: ln -s \(bundleCLI.path) \(dest) | 失败：\(error.localizedDescription)。可手动安装：ln -s \(bundleCLI.path) \(dest) |

### `DorisCommands.swift`

| English | 中文 |
|---|---|
| New Task | 新建任务 |
| Sync Now | 立即同步 |

### `MainTodayView.swift`

| English | 中文 |
|---|---|
| Pinned | 置顶 |
| Long-term | 长期 |
| Upcoming | 日程 |
| All clear | 今日清净 |
| Pin a task or give it a due date to see it here. | 置顶任务或设定截止日期，就会出现在这里。 |

### `MainTokensView.swift`

| English | 中文 |
|---|---|
| Token monitoring unavailable | Token 监控不可用 |
| Token usage | Token 用量 |
| updated  | 更新于  |
| Rescan | 重新扫描 |
| Last 30 days | 近 30 天 |
| By tool | 按工具 |
| By model | 按模型 |
| Sources | 数据源 |
| coming soon | 即将支持 |
| off | 已关闭 |
| connected | 已连接 |
| no logs | 无日志 |
| No data in this range yet. | 该区间暂无数据。 |
| Today | 今日 |
| 7 days | 7 天 |
| 30 days | 30 天 |
| All | 全部 |

### `MainWindowView.swift`

| English | 中文 |
|---|---|
| Today | 今日 |
| To-dos | 待办 |
| Events | 事件 |
| Tokens | Token |
| Settings | 设置 |
| Close window | 关闭窗口 |
| No events yet | 暂无事件 |
| Notifications from Claude Code, Codex, the CLI and your other devices show up here. | Claude Code、Codex、命令行和其他设备发来的通知都会出现在这里。 |
| Pick a task on the left | 在左侧选择一个任务 |
| Active | 未归档 |
| Archived | 已归档 |
| Trash | 回收站 |
| Empty trash? | 清空回收站？ |
| Empty (\(trashCount)) | 清空 (\(trashCount)) |
| Cancel | 取消 |
| Items in the trash will be permanently deleted and can't be recovered. | 回收站中的任务将被彻底删除，无法恢复。 |
| Archive done (\(doneActiveCount)) | 归档已完成 (\(doneActiveCount)) |
| Move all completed tasks to archive | 把所有已完成任务移到归档 |
| Permanently delete every item in trash | 彻底删除回收站中所有任务 |
| Show one column | 改为单列显示 |
| Show the list and the task side by side | 列表和任务左右两列显示 |
| Add task | 添加任务 |
| No tasks yet | 暂无任务 |
| No archived tasks | 暂无归档任务 |
| Trash is empty | 回收站为空 |
| Click "+ Add task" below to start. | 点击下方「+ 添加任务」开始。 |
| Tasks you archive show up here. Use the box icon on a row, or the bulk button on the Active list. | 归档的任务会出现在这里。点行尾的箱子图标，或在「未归档」列表里用批量按钮。 |
| Deleted tasks stay here for 24 hours — restore them before then. | 删除的任务会在这里保留 24 小时，期间随时可以恢复。 |

### `SettingsView.swift`

| English | 中文 |
|---|---|
| General | 通用 |
| Avatar | 形象 |
| Sync | 同步 |
| Tokens | Token |
| Archived | 已归档 |
| Sidebar | 侧栏 |
| Shortcuts | 快捷键 |
| CLI | 命令行 |
| Theme | 主题 |
| Desktop panel | 桌面面板 |
| Version | 版本 |
| Monitor token usage | 监控 Token 用量 |
| Tallies token consumption by reading AI tools' local logs. macOS only — data stays on this Mac. | 通过读取 AI 工具的本地日志统计 Token 消耗。仅 macOS，数据只保存在本机。 |
| Tools | 工具 |
| coming soon | 即将支持 |
| Rescan now | 立即扫描 |
| Last scan | 上次扫描 |
| Character | 形象 |
| Pick the character Doris uses — its animation and portrait switch with it. | 选择 Doris 的形象 —— 动画与头像随之切换。 |
| Avatar activity | 助手活跃度 |
| Quiet | 安静 |
| Standard | 标准 |
| Lively | 活泼 |
| Controls how often the avatar reacts to task events and notifications. | 控制助手对任务和通知的反应频率。 |
| Placement | 显示位置 |
| Screen edge | 贴边 |
| Desktop pet | 桌面 |
| Edge: docked to the menu bar / notch. Desktop: a free-floating pet you can drag anywhere, on top of all windows. | 贴边：停靠在菜单栏/刘海。桌面：可随意拖动的桌宠，浮于所有窗口之上。 |
| Pet size | 桌宠大小 |
| Small | 小 |
| Medium | 中 |
| Large | 大 |
| Edge | 边缘 |
| Left | 左 |
| Right | 右 |
| Width | 宽度 |
| Pinned across spaces | 跨桌面置顶 |
| Notch behavior | 刘海行为 |
| Toggle sidebar | 切换侧栏 |
| Toggle notch | 切换刘海 |
| Open events | 打开事件 |
| CLI installed at | CLI 安装位置 |
| (not installed) | （未安装） |
| Allowed source app IDs | 允许的来源应用 ID |
| Use iCloud sync | 使用 iCloud 同步 |
| Syncs your tasks and events through your iCloud account, so your other devices stay up to date. | 通过你的 iCloud 账号同步任务和事件，让其他设备保持一致。 |
| Database | 数据库 |
| Not the Production database — this build syncs with a separate dataset your other devices don't read. | 不是 Production 数据库 —— 此构建同步到一份独立数据，其他设备读不到。 |
| Restart Doris after turning iCloud on or off. | 开关 iCloud 后需重启 Doris 才能生效。 |
| Local only. Your tasks stay on this Mac. | 仅本地存储，任务不会离开本机。 |
| Auto-sync every minute | 每分钟自动同步 |
| When on, Doris sends your changes to iCloud every minute. Turn it off to sync only when you click Sync Now. | 开启后，Doris 每分钟把改动同步到 iCloud；关闭则只在点「立即同步」时同步。 |
| Auto-sync | 自动同步 |
| Syncing… | 同步中… |
| Sync Now | 立即同步 |
| Manual sync | 手动同步 |
| Sync Now saves your changes and checks that iCloud is reachable; "Last synced" only updates when both succeed. | 「立即同步」会保存改动并确认 iCloud 可以连上，两步都成功才会更新「上次同步」时间。 |
| Sync failed | 同步失败 |
| iCloud sync is off | iCloud 同步未开启 |
| Not synced yet | 尚未同步 |
| In sync with iCloud | 已与 iCloud 同步 |
| Your tasks stay on this Mac. Turn on iCloud below to sync them to your other devices. | 任务仅保存在本机。在下方开启 iCloud 即可与其他设备同步。 |
| Click Sync Now below to start syncing. | 点击下方「立即同步」开始第一次同步。 |
| Never synced | 尚未同步 |
| Last synced  | 上次同步  |
| No archived tasks. | 暂无归档任务。 |
| Tasks archived on any of your devices appear here and are kept until you delete them. | 在任意设备上归档的任务都会出现在这里，一直保留到你手动删除。 |
| \(archived.count) archived | 已归档 \(archived.count) 个任务 |
| Delete All | 全部删除 |
| Untitled | 无标题 |
| Restore | 恢复 |
| Delete | 删除 |

### `TokenSummaryCard.swift`

| English | 中文 |
|---|---|
| TOKEN USAGE · TODAY | TOKEN 用量 · 今日 |
| Open token dashboard | 打开 Token 看板 |

### `SidebarRootView.swift`

| English | 中文 |
|---|---|
| Events | 事件 |
| To-dos | 待办 |
| Today | 今日 |
| Quick captures and recent items show up here. | 快速记录和最近的内容会出现在这里。 |

### `DesktopPanelView.swift`

| English | 中文 |
|---|---|
| Pinned | 置顶 |
| Long-term | 长期 |
| Upcoming | 日程 |
| Doris · Today | Doris · 今日 |
| Open main window · right-click for options | 打开主窗口 · 右键查看更多选项 |
| Add task | 添加任务 |
| Focus | 专注 |
| New task for today… | 添加今日任务… |
| Cancel | 取消 |
| Untitled | 无标题 |
| Just focus | 自由专注 |
| \(m) min | \(m) 分钟 |
| Stop | 停止 |
| Open Main Window | 打开主窗口 |
| Always on Top | 总在最前 |
| Background Opacity | 背景不透明度 |
| Hide Desktop Panel | 隐藏桌面面板 |
| Later · \(laterNotes.count) | 之后 \(laterNotes.count) 项 |
| Mark as not done | 标为未完成 |
| Mark as done | 标为已完成 |
| Edit task | 编辑任务 |
| All clear | 今日清净 |
| Nothing pinned or due today. | 没有置顶或今天到期的任务。 |

### `StickyNoteView.swift`

| English | 中文 |
|---|---|
| Remove from desktop | 从桌面移除 |
| Title | 标题 |

### `VoiceController.swift`

| English | 中文 |
|---|---|
| Doris needs Accessibility permission to paste. | Doris 需要辅助功能权限来粘贴。 |
| Requesting permission… answer the system prompt, then press the hotkey again. | 正在请求权限，请在系统弹窗中选择，然后再次按下热键。 |
| Doris needs microphone access. | Doris 需要麦克风权限。 |
| Doris needs Speech Recognition access. | Doris 需要语音识别权限。 |
| Speech recognition is restricted on this Mac. | 本机已限制语音识别。 |

### `VoiceFloater.swift`

| English | 中文 |
|---|---|
| Listening… | 正在聆听… |
| speak now | 请说话 |
| → \(target) | → \(target) |
| Voice error | 语音错误 |

### `VoiceSettings.swift`

| English | 中文 |
|---|---|
| Left Shift | 左 Shift |
| Right Shift | 右 Shift |
| Left Control | 左 Control |
| Right Control | 右 Control |
| Fn | Fn |
| ChatGPT | ChatGPT |
| Claude | Claude |
| Frontmost app | 当前 App |
| Auto | 自动 |
| Chinese | 中文 |
| English | 英文 |
| Cantonese | 粤语 |

## Shared (iOS + macOS)

### `RelativeTime.swift`

| English | 中文 |
|---|---|
| Just now | 刚刚 |
| \(mins) min ago | \(mins) 分钟前 |
| \(hrs) h ago | \(hrs) 小时前 |
| \(days) d ago | \(days) 天前 |

### `SyncNowToolbarButton.swift`

| English | 中文 |
|---|---|
| Open Sync Settings | 打开同步设置 |
| Retry | 重试 |
| Syncing… | 同步中… |
| iCloud off | iCloud 未开启 |
| Never synced | 尚未同步 |
| Sync error: \(err)\nClick for details. | 同步错误：\(err)\n点击查看详情。 |
| iCloud sync is off. Click for details. | iCloud 同步未开启，点击查看详情。 |
| Sync Now | 立即同步 |
| Last synced  | 上次同步  |
| Sync failed | 同步失败 |
| iCloud sync is off | iCloud 同步未开启 |
| In sync | 已同步 |
| Your tasks only live on this Mac. Open Sync Settings and turn on "Use iCloud sync" to sync them across your devices. | 任务仅保存在本机。打开「同步设置」并开启「使用 iCloud 同步」，即可在多台设备间同步。 |

### `AvatarHero.swift`

| English | 中文 |
|---|---|
| Paused | 已暂停 |
| Break over | 休息结束 |
| Focus done | 专注结束 |
| Break | 休息 |
| Done | 完成 |
| Exit | 退出 |
| \(m) min | \(m) 分钟 |
| Keep going | 再续 |

### `FocusFullScreenView.swift`

| English | 中文 |
|---|---|
| Close | 关闭 |
| Break over | 休息结束 |
| Focus done | 专注结束 |
| Paused | 已暂停 |
| \(s.durationMin) min | \(s.durationMin) 分钟 |
| Keep going | 再续 |
| \(m) min | \(m) 分钟 |
| Exit | 退出 |
| Complete | 完成任务 |
| Resume | 继续 |
| Pause | 暂停 |
| End | 结束 |

### `FocusReturnChip.swift`

| English | 中文 |
|---|---|
| Focus done | 专注结束 |

### `FocusRingBadge.swift`

| English | 中文 |
|---|---|
| Set duration | 调整时间 |
| Resume | 继续 |
| Pause | 暂停 |
| Stop focus | 停止专注 |

### `FocusTimer.swift`

| English | 中文 |
|---|---|
| Break | 休息 |

### `DayCollapsibleEventList.swift`

| English | 中文 |
|---|---|
| Today | 今天 |
| No events today. | 今天暂无事件。 |
| No events. | 暂无事件。 |
| Loading… | 加载中… |
| Yesterday | 昨天 |

### `EventsListView.swift`

| English | 中文 |
|---|---|
| All | 全部 |
| Dismiss | 忽略 |
| Done | 完成 |
| Events | 事件 |

### `ChecklistEditorView.swift`

| English | 中文 |
|---|---|
| Drag to reorder | 拖动排序 |
| Image | 图片 |
| \(m) min | \(m) 分钟 |
| Focus on this item | 专注此条 |
| Delete this item | 删除此条 |
| Add item | 添加条目 |
| Turn into a task | 转为独立任务 |
| Mark as done | 标为已完成 |
| Mark as not done | 标为未完成 |

### `DueDateChipButton.swift`

| English | 中文 |
|---|---|
| Schedule | 排期 |
| Schedule… | 排期… |
| Set due date | 设置截止日期 |
| Done | 完成 |
| Today | 今天 |
| \(days)d overdue | 逾期 \(days) 天 |
| Tomorrow | 明天 |
| Due date | 截止日期 |
| Not set | 未设定 |
| Weekend | 周末 |
| Next wk | 下周 |
| Clear | 清除 |
| Clear due date | 清除截止日期 |

### `NoteBodyEditor+iOS.swift`

| English | 中文 |
|---|---|
| Format | 格式 |
| Highlight | 高亮 |
| Remove Highlight | 清除高亮 |
| Bold | 加粗 |
| Underline | 下划线 |
| Highlight Yellow | 黄色高亮 |
| Highlight Colour | 高亮颜色 |
| Hide Keyboard | 收起键盘 |
| Image | 图片 |
| View Full Size | 查看大图 |
| Delete Image | 删除图片 |

### `NoteBodyEditor+macOS.swift`

| English | 中文 |
|---|---|
| Bold | 加粗 |
| Underline | 下划线 |
| Highlight Yellow | 黄色高亮 |
| Highlight Green | 绿色高亮 |
| Highlight Red | 红色高亮 |
| Remove Highlight | 清除高亮 |
| Format | 格式 |

### `NoteImageLoader.swift`

| English | 中文 |
|---|---|
| Small | 小 |
| Medium | 中 |
| Large | 大 |
| Full width | 全宽 |
| Image syncing… | 图片同步中… |

### `NoteImageView.swift`

| English | 中文 |
|---|---|
| Size | 尺寸 |
| View Full Size | 查看大图 |
| Delete Image | 删除图片 |

### `NoteImageViewer.swift`

| English | 中文 |
|---|---|
| Image | 图片 |
| Close | 关闭 |

### `NoteRichText.swift`

| English | 中文 |
|---|---|
| Bold (⌘B) | 加粗 (⌘B) |
| Underline (⌘U) | 下划线 (⌘U) |
| Highlight yellow (⌘⇧H) | 黄色高亮 (⌘⇧H) |
| Remove Highlight | 清除高亮 |
| Highlight | 高亮 |
| Highlight colour | 高亮颜色 |
| Yellow | 黄色 |
| Green | 绿色 |
| Red | 红色 |

### `InlineNoteEditor.swift`

| English | 中文 |
|---|---|
| Title | 标题 |
| Archive this task? | 归档这个任务？ |
| Archive | 归档 |
| Cancel | 取消 |
| It moves to Archived and stays there until you delete it. You can restore it any time. | 任务会移到「已归档」，一直保留到你手动删除，随时可以恢复。 |
| Back to list | 返回列表 |
| Insert images (or paste / drag them in) | 插入图片（也可以直接粘贴或拖进来） |
| Done | 已完成 |
| Complete | 完成 |
| Mark as not done | 标为未完成 |
| Mark as done | 标为已完成 |
| Archive this task | 归档这个任务 |
| Pinned | 置顶 |
| Unpin from top | 取消置顶 |
| Pin to top of list | 置顶到列表顶部 |
| Checklist | 清单 |
| Plain text | 纯文本 |
| Convert to checklist | 转为清单 |
| Insert | 插入 |
| Created \(created)\nUpdated \(updated) | 创建于 \(created)\n更新于 \(updated) |

### `MonthCalendar.swift`

| English | 中文 |
|---|---|
| Today | 今天 |

### `NoteContextMenu.swift`

| English | 中文 |
|---|---|
| Permanently delete? | 彻底删除？ |
| Delete forever | 彻底删除 |
| Cancel | 取消 |
| This task can't be recovered after a permanent delete. | 彻底删除后此任务无法恢复。 |
| Restore | 恢复 |
| Mark as not done | 标为未完成 |
| Mark as done | 标为已完成 |
| Done & archive | 完成并归档 |
| Unpin | 取消置顶 |
| Pin to top | 置顶 |
| Remove long-term | 取消长期 |
| Long-term | 长期 |
| Open editor | 打开编辑器 |
| Stick to desktop | 贴到桌面 |
| Unarchive | 取消归档 |
| Archive | 归档 |
| Move to trash | 移到回收站 |
| Stop focus | 停止专注 |
| \(m) min | \(m) 分钟 |
| Start focus | 开始专注 |
| Today | 今天 |
| Tomorrow | 明天 |
| This weekend | 本周末 |
| Next Monday | 下周一 |
| Pick a date… | 选择日期… |
| Clear due date | 清除截止日期 |
| Schedule… | 排期… |
| Scheduled:  | 已排期： |
| \(days)d overdue | 逾期 \(days) 天 |
| Pick a due date | 选择截止日期 |
| Due date | 截止日期 |
| Clear | 清除 |
| Done | 完成 |

### `NoteEditorSheet.swift`

| English | 中文 |
|---|---|
| Archive this task? | 归档这个任务？ |
| Archive | 归档 |
| Cancel | 取消 |
| It moves to Archived and stays there until you delete it. You can restore it any time. | 任务会移到「已归档」，一直保留到你手动删除，随时可以恢复。 |
| Edit | 编辑 |
| Done | 完成 |
| Edit Task | 编辑任务 |
| Title | 标题 |
| Pinned | 置顶 |
| Checklist | 清单 |
| Done | 已完成 |

### `NoteEditorView.swift`

| English | 中文 |
|---|---|
| Checklist | 清单 |
| Pinned | 置顶 |

### `TodoRow.swift`

| English | 中文 |
|---|---|
| Unpin | 取消置顶 |
| Pin to top | 置顶 |
| Mark as not done | 标为未完成 |
| Mark as done | 标为已完成 |
| New task | 新任务 |
| Open editor | 打开编辑器 |
| Permanently delete? | 彻底删除？ |
| Delete forever | 彻底删除 |
| Cancel | 取消 |
| This task can't be recovered after a permanent delete. | 彻底删除后此任务无法恢复。 |
| Stop focus | 停止专注 |
| \(m) min | \(m) 分钟 |
| Start focus | 开始专注 |
| Restore | 恢复 |
| Unarchive | 取消归档 |
| Archive | 归档 |
| Move to trash | 移到回收站 |

### `ThemeSettings.swift`

| English | 中文 |
|---|---|
| Dark | 深色 |
| Light | 浅色 |

### `TodayComponents.swift`

| English | 中文 |
|---|---|
| Rain | 降水 |
| UV | 紫外线 |
| Loading weather… | 加载天气中… |
| Weather unavailable | 天气不可用 |
| Today | 今天 |
| \(days)d overdue | 逾期 \(days) 天 |
| Tomorrow | 明天 |
| Untitled | 无标题 |
| DONE | 已完成 |

### `WeatherService.swift`

| English | 中文 |
|---|---|
| Singapore | 新加坡 |
| Calm | 无风 |
| Light air | 软风 |
| Light breeze | 轻风 |
| Gentle breeze | 微风 |
| Moderate | 和风 |
| Fresh | 清风 |
| Strong | 强风 |
| Near gale | 疾风 |
| Gale | 大风 |
| Strong gale | 烈风 |
| Storm | 狂风 |
| Hurricane | 飓风 |
| Low | 低 |
| Moderate | 中等 |
| High | 高 |
| Very High | 很高 |
| Extreme | 极高 |
| Unlikely | 几乎不会 |
| Possible | 可能 |
| Likely | 很有可能 |
| Very likely | 非常可能 |
| Clear | 晴 |
| Mostly Clear | 晴间多云 |
| Partly Cloudy | 局部多云 |
| Overcast | 阴 |
| Fog | 雾 |
| Drizzle | 毛毛雨 |
| Freezing Drizzle | 冻毛毛雨 |
| Rain | 雨 |
| Freezing Rain | 冻雨 |
| Snow | 雪 |
| Snow Grains | 米雪 |
| Rain Showers | 阵雨 |
| Snow Showers | 阵雪 |
| Thunderstorm | 雷暴 |
