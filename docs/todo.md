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

## 2. ~~新建子任务时光标与 checkbox 不对齐~~(已修 · 2026-08-21,未发版)

**现象**:任务详情页新增一个子任务时,输入光标和左侧 checkbox 没有对齐,视觉上是歪的。

**位置**:`packages/DorisUI/Sources/DorisUI/Notes/ChecklistEditorView.swift`
- 行容器:`HStack(alignment: .firstTextBaseline, spacing: 8)`
- checkbox:`Image` + `.font(.system(size: 14, weight: .semibold))` + `.frame(width: 18, height: 18)`
- iOS 输入框:`ChecklistItemFieldIOS`,内部 `textContainerInset = .zero`、`lineFragmentPadding = 0`、`font = UIFont.preferredFont(forTextStyle: .body)`

**待验证的假设**(未确认,修之前先验):
1. 行用 `.firstTextBaseline` 对齐,但 checkbox 是套在固定 `frame(18×18)` 里的 `Image` —— 加了固定 frame 之后它上报的基线未必对应字形的视觉中心。
2. 字号不一致:checkbox 14pt,输入框走 `.body`(默认 17pt),两者基线本就不在同一位置。
3. 只在**新建**时明显 —— 空的 `UITextView` 与有文字时上报的固有高度/基线不同,这最可能是"新建才歪"的直接原因。

**2026-08-20 用户补充的关键观察**:光标不是"歪",而是**上下不居中、偏下**;**一旦开始打字就自动居中了**。这直接证实了上面的假设 3 —— 问题出在空框与有字时的高度/基线差异,而不是 checkbox 那一侧。

**代码层面的具体线索**(读码所得,仍需上机确认):
`ChecklistItemFieldIOS` 是 `UIViewRepresentable`,而行容器是 `HStack(alignment: .firstTextBaseline)`。UIViewRepresentable **不向 SwiftUI 暴露真实的文字基线**,SwiftUI 只能退回用视图底边充当基线。所以对齐的其实是「checkbox 的文字基线 ↔ 输入框的底边」,本身就是近似;而 `sizeThatFits` 在空框与有字时返回的高度不同,底边一动,垂直位置就跟着移。

修的方向(择一,需实测):
- 给 `ChecklistItemFieldIOS` 实现 `alignmentGuide(.firstTextBaseline)`,用 UITextView 的 `font.ascender` 算出真实基线;或
- 行容器改用 `.center` 对齐,并让 checkbox 与输入框的高度稳定一致,不再依赖基线。

**复现**:打开任一清单笔记 → 点「新增条目」→ 观察光标垂直位置(偏下)→ 输入任意字符 → 光标回到居中。

**已修**:给 `ChecklistItemFieldIOS` 加了 `.alignmentGuide(.firstTextBaseline)`,返回 `UIFont.preferredFont(forTextStyle: .body).ascender`。因为 `textContainerInset = .zero` 且 `lineFragmentPadding = 0`,首行基线就在顶边下方 `ascender` 处,而这个值**与是否已有文字无关** —— 这正是原来那个"空框/有字高度不同→底边移动→对齐跟着移"的根因所在。

保留 `.firstTextBaseline` 而没有改成 `.center`:多行子任务时 checkbox 应当对齐**第一行**,`.center` 会让它去对齐整块文字的中心,那是另一种错。

**iPhone 17 模拟器实测(原生像素 @3x)**:

| 场景 | 修复前偏差 | 修复后偏差 |
|---|---|---|
| 新建空行 | 48.5 px = **16.17 pt** | 1.5 px = **0.50 pt** |
| 多行换行(对齐第一行) | — | 0.5 px = **0.17 pt** |

**尚未发布** —— 1.8.0 已上架,这个修复要等下个版本。

---

## 3. ~~天气定位依赖 ipapi.co 免费额度~~(已决定不修 · 2026-08-21)

**现象**:`ipapi.co` 会返回 `HTTP 429 RateLimited`(在开发机出口 IP 上实测到)。命中时「今日」页天气卡显示"天气不可用"。

**说明**:这**不是** 2026-08-16 那次真机录屏里天气不可用的原因 —— 那次是首启尚未授予网络权限,拿到权限后天气正常。两者是不同的问题,别混淆。

**结论:不修。** `WeatherService.swift:110` 请求的是 `https://ipapi.co/json/`,**不带 API key**。ipapi.co 免费层对匿名请求按**来源 IP** 计额度,所以每个用户用自己的 IP、各自一份配额,不会共用开发者的。之前那次 429 只是这台开发机反复测试打满了自己的额度,不代表线上用户会遇到。

**残留的小风险**(不足以现在动手):运营商级 NAT 或公司网络下,大量用户可能共用一个出口 IP,那种情况下仍可能触发限流。真收到用户反馈再考虑加"失败时按系统时区推断城市"的兜底。届时注意:隐私政策和 App Store 隐私声明里都写了 `ipapi.co`,更换数据源需同步更新这两处。
