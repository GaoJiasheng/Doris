# 待修

已确认、暂缓处理的问题。都不影响 1.8.0 送审,计划随后续版本一起修。

---

## 1. 置顶卡片拖拽后留下虚线空框

**现象**:在「今日」页左右拖动置顶卡片,松手后原位变成一个空的虚线框,卡片消失,要等一段时间才恢复。

**根因**:`.onDrag` 没有取消回调,卡片松在任何非投放区(天气卡、分区标题、屏幕边缘)时 `finishDrop()` 不会触发,只能靠看门狗兜底。而看门狗原本计时基准是 `draggingID` —— 这个值在抬起卡片时设一次就不再变,所以计的是"拖拽开始至今",必须给到 20 秒才不会打断一次慢速拖拽。代价全由失败路径承担:虚线框僵 20 秒,看起来就是坏了。

**位置**:`packages/DorisUI/Sources/DorisUI/Today/ReorderableNoteGrid.swift`

**状态**:**修复已写好,未提交,未随任何构建发布。**
计时基准改为 `lastDragActivity`(每次 `isTargeted` 悬停刷新),含义变成"距上次拖拽活动多久",于是超时可以缩到 2.5 秒而不会打断真实拖拽。iOS + macOS 均已编译通过。

**遗留**:录屏里还观察到**两张置顶卡片消失**(不只是一个虚线框)。仅凭视频帧无法确认成因,本机也未复现。可能是 `items` 半途重排没回滚导致,也可能是另一个问题。**修复上机后要再拖几次验证**,若仍有卡片消失需另查。

**复现**:今日页 → 置顶区有 ≥2 张卡片 → 按住一张横向拖动 → 松手在天气卡或分区标题上。

---

## 2. 新建子任务时光标与 checkbox 不对齐

**现象**:任务详情页新增一个子任务时,输入光标和左侧 checkbox 没有对齐,视觉上是歪的。

**位置**:`packages/DorisUI/Sources/DorisUI/Notes/ChecklistEditorView.swift`
- 行容器:`HStack(alignment: .firstTextBaseline, spacing: 8)`
- checkbox:`Image` + `.font(.system(size: 14, weight: .semibold))` + `.frame(width: 18, height: 18)`
- iOS 输入框:`ChecklistItemFieldIOS`,内部 `textContainerInset = .zero`、`lineFragmentPadding = 0`、`font = UIFont.preferredFont(forTextStyle: .body)`

**待验证的假设**(未确认,修之前先验):
1. 行用 `.firstTextBaseline` 对齐,但 checkbox 是套在固定 `frame(18×18)` 里的 `Image` —— 加了固定 frame 之后它上报的基线未必对应字形的视觉中心。
2. 字号不一致:checkbox 14pt,输入框走 `.body`(默认 17pt),两者基线本就不在同一位置。
3. 只在**新建**时明显 —— 空的 `UITextView` 与有文字时上报的固有高度/基线不同,这最可能是"新建才歪"的直接原因。

**复现**:打开任一清单笔记 → 点「新增条目」→ 看光标与 checkbox 的垂直关系。

---

## 3. 天气定位依赖 ipapi.co 免费额度(优先级低)

**现象**:`ipapi.co` 会返回 `HTTP 429 RateLimited`(在开发机出口 IP 上实测到)。命中时「今日」页天气卡显示"天气不可用"。

**说明**:这**不是** 2026-08-16 那次真机录屏里天气不可用的原因 —— 那次是首启尚未授予网络权限,拿到权限后天气正常。两者是不同的问题,别混淆。

**方向**:换一个不限额的粗略定位来源,或在失败时回退(例如按系统时区推断城市),而不是直接显示不可用。注意隐私政策和 App Store 隐私声明里都写了 `ipapi.co`,更换数据源需要同步更新这两处。
