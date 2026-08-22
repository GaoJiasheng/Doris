# 待修

已确认、暂缓处理的问题。都不影响 1.8.0 送审,计划随后续版本一起修。

---

## 1. ~~置顶卡片拖拽后留下虚线空框~~(已修并经真机验证 · 2026-08-22,随 1.8.2 发布)

**现象**:在「今日」页拖动置顶卡片,松手后原位变成空的虚线框,卡片消失,约 2–3 秒后才恢复。

**位置**:`packages/DorisUI/Sources/DorisUI/Today/ReorderableNoteGrid.swift`

### 真正的根因(与最初记录的不同)

最初(以及 build 34/35)把问题归为"看门狗超时太长",这是**错的** —— 超时只是遮住了真病因。真机上的屏幕读数(build 36)显示:**每一次拖拽,无论成败,放下动作都从未执行过**,全靠 2.5s 超时收尾。

放下动作不触发,是三层问题叠在一起:

1. **`DropDelegate` 缺 `dropUpdated`** —— 没有它,SwiftUI 用默认提议,在真机上等于拒收:`validateDrop` 通过、`dropEntered` 触发(所以悬停重排一直正常,这恰恰掩盖了问题),但 `performDrop` 永远不调。显式返回 `.move` 后 `CELL-DROP` 才第一次出现。(build 38)
2. **兜底投放区只覆盖网格自身** —— 松在天气卡、分区标题、空白处时,落在任何投放区之外。把它向外扩 600pt 后 `BG-DROP` 才出现。(build 39)
3. **放下落地后还有一次淡入动画** —— 卡片自抬起就处于 `opacity 0`,系统飞回预览(~400ms)之后我们又用弹簧把它淡回来(~300ms)。超时在时这一层看不见;超时去掉后它就成了"放下成功但卡片空白"。改为禁用动画的事务瞬时切换。(build 41)

另有第三类:长按触发了拖拽但手指没动就松开,系统直接取消会话,任何投放区都收不到。只能靠超时,但现在用 `dropUpdated` 当心跳(拖拽经过兜底区时持续触发,而兜底区已近乎整屏),超时可以安全压到 0.6s。(build 40)

### 真机读数(build 40)

| 路径 | 耗时 |
|---|---|
| 松在卡片上 → `CELL-DROP` | ~470–510 ms |
| 松在卡片外 → `BG-DROP` | ~250–300 ms |
| 长按原地松开 → `WATCHDOG` | ~610–640 ms |

build 41 再去掉 ~300ms 淡入。

### 走过的弯路

| build | 改动 | 结果 |
|---|---|---|
| 34 | 看门狗 20s → 2.5s | ❌ 超时从来不是病因 |
| 35 | 加 `sessionDidEnd` observer | ❌ 且被自己的 `hitTest` 覆写写成死代码 |
| 36 | **屏幕读数** | 定位到真凶 |
| 37 | 放下侧换 `DropDelegate` | ❌ "两代 API 不匹配"的判断是错的 |
| 38 | 补 `dropUpdated → .move` | ✅ CELL-DROP 通 |
| 39 | 兜底区扩到网格外 | ✅ BG-DROP 通 |
| 40 | `dropUpdated` 当心跳,超时 0.6s | ✅ |
| 41 | 去淡入,撤探针 | ✅ **真机验证通过**,三种松手方式均无可见空白 |

**教训**:前四版全在改"什么时候清状态",真问题是"放下动作没执行"。悬停重排一直正常,让拖拽看起来是好的。遇到看不见内部状态的 bug,**先花一版做可观测性**,比连着凭推断改快得多 —— build 36 之后每一版都有确定收获。

**遗留已解释**:早期录屏里"两张卡片同时消失"是同一问题的表现 —— 一张是被拖卡片的占位框,另一张是放下后淡入动画中的卡片。

---

## 2. ~~新建子任务时光标与 checkbox 不对齐~~(已修并发布 · 1.8.1)

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

**已随 1.8.1 发布**(macOS build 19 / iOS build 34)。

---

## 3. ~~天气定位依赖 ipapi.co 免费额度~~(已决定不修 · 2026-08-21)

**现象**:`ipapi.co` 会返回 `HTTP 429 RateLimited`(在开发机出口 IP 上实测到)。命中时「今日」页天气卡显示"天气不可用"。

**说明**:这**不是** 2026-08-16 那次真机录屏里天气不可用的原因 —— 那次是首启尚未授予网络权限,拿到权限后天气正常。两者是不同的问题,别混淆。

**结论:不修。** `WeatherService.swift:110` 请求的是 `https://ipapi.co/json/`,**不带 API key**。ipapi.co 免费层对匿名请求按**来源 IP** 计额度,所以每个用户用自己的 IP、各自一份配额,不会共用开发者的。之前那次 429 只是这台开发机反复测试打满了自己的额度,不代表线上用户会遇到。

**残留的小风险**(不足以现在动手):运营商级 NAT 或公司网络下,大量用户可能共用一个出口 IP,那种情况下仍可能触发限流。真收到用户反馈再考虑加"失败时按系统时区推断城市"的兜底。届时注意:隐私政策和 App Store 隐私声明里都写了 `ipapi.co`,更换数据源需同步更新这两处。
