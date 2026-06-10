# Doris(赛博笔记)最终产品评审报告

**版本基线**:v1.1.2(macOS build 6 / iOS build 16)· 评审日期 2026-06-10
**评审基准**:独立开发者资源约束下,对标 Things 3 / Raycast / Flighty / Finch 级别的同类最佳产品

---

## 1. 执行摘要

**定位判断**:Doris 是一个「地基远好于门面」的产品——HMAC 签名 IPC、CloudKit 墓碑同步、签名 CLI、三端共享组件库、有设计自觉的赛博视觉语言,工程密度超过绝大多数独立应用三年的积累;但它此刻同时背着「任务管理 table stakes 缺一半」(无到期提醒、无重复任务、Mac 无搜索、无全局捕获)和「差异化资产闲置」(头像只是吉祥物不是角色、agent 通知只接了 Stop hook、写完的 Share/Intents 扩展没装进包里、整页死设置在伤害信任)两笔债。**结论:不要在任务管理红海里和 Things/Todoist 拼完整度,而要把 Doris 押注在全市场无人占据的空位上——「有脸的本地 AI Agent 通知中枢 + 二次元桌面伴侣」,同时只补齐让评测者「一票否决」的基础项。**

**最重要的 5 个动作**(按 ROI 排序):

1. **一周「诚实性冲刺」**:修 Enter 双行 bug、嵌入已写完的 Share/Intents 扩展(改 project.yml 即可)、删掉 Cmd+, 里两整页死设置、CLI 版本号对齐——零新功能,但决定评测写「精致」还是「半成品」。
2. **补齐四个「评测即出局」缺口**:到期本地提醒(默认开)、中英双语自然语言日期解析、双模式重复任务、Mac 端 Cmd+F 搜索 + 全局捕获热键。
3. **Agent hub 从 v0.5 升到 v1.0**:加 Notification hook 感知「agent 在等你」、横幅携带项目名 + diff 统计 + 一句话摘要的「验证包」、下拉面板加 Agent 收件箱——这是唯一的护城河,竞品(Omnara/Happy/GitHub Mobile)正在填空。
4. **把她的心情接到任务数据上**:完成任务→小庆祝、清空今日→大庆祝、多项逾期→担忧——三个数据源(时钟/天气/任务)Doris 全有而任何桌宠竞品都拿不到第三个,这是角色从「会动」到「活着」的最便宜一步。
5. **接入 Sparkle 自动更新 + 接通备份/导出**:DMG 分发没有更新通道意味着修好的 bug 永远到不了存量用户;「每日自动备份」开关目前是空头支票——信任债必须先还。

---

## 2. 六维评分卡

| 维度 | 评分 | 一句话现状 | 最大短板 |
|---|---|---|---|
| 功能性 | **4.5/10** | notes-are-tasks 单一模型 + 三端同步 + 三套自动化入口,工程密度惊人,但任务管理核心契约缺失 | 截止日期纯展示,全仓库无一行 UNUserNotificationCenter——任务到期永远不会提醒 |
| 易用性 | **4/10** | 行内键盘语义达到 Things 级细节,同步透明度优秀,但「进门的路」全断 | 无全局捕获热键,从任意 app 落一条任务要 3-4 步,且面板点外即收丢草稿 |
| 美观程度 | **5.5/10** | 罕见的设计自觉(每个像素有理由)+ Calm Focus 小组件已得正确配方,但执行失守 | iOS 图标是 macOS 图标平铺白底直接复用,主屏「图标套图标」,第一印象即翻车 |
| 二次元程度 | **3/10** | 7 段 65 帧动画工艺扎实、克制不尬,但只是「高质量吉祥物」而非角色 | 情绪接在管道上(同步成功才庆祝),用户勾掉任务她毫无反应——aliveness 因果链断裂 |
| 个性化 | **2.5/10** | 位置/尺寸记忆类隐式个性化合格,显式个性化几乎为零 | 唯一不可复制的资产(头像)只有一个不透明度滑杆;Widget 是零配置 StaticConfiguration |
| 专业度 | **4/10** | 签名/公证/隐私结构性优秀,CHANGELOG 诚实,但用户摸得到的信任表面全缺 | DMG 分发却无任何更新通道,修好的 bug 无法触达存量用户 |

**综合:约 4/10。** 内核 7 分,外壳 2 分。好消息是:扣分项里大量是「已写完没接线」「半天能修」的低垂果实。

---

## 3. 战略定位建议

### 3.1 红海 vs 蓝海:答案是明确的

**任务管理是死海。** Things 3 打磨了十几年、Todoist 有 16 语种 NL 解析、TickTick 功能矩阵碾压——Doris 以一人之力在「任务管理完整度」上永远追不平,而且追平了也没人换工具。任务管理功能对 Doris 的正确定位是**「及格线工程」:只补会被一票否决的项(提醒/重复/NL 日期/搜索/捕获),补到不丢分为止,一分力气都不要多花**。

**蓝海是真实存在且窗口正在关闭的。** 竞研确认了一个无人占据的形状:

> **「本地 AI Agent 的通知中枢 + 手机桥 + 有人格的状态板」——无服务器、无账号、无中继,Mac 原生,经你自己的 iCloud 推到你自己的 iPhone。**

- Omnara 收 SaaS 月费且数据过它的中继;Happy 需要 QR 配对自家 relay;GitHub Mobile 只覆盖云端 Copilot 会话;Warp/Conductor 没有手机端和个人任务层。
- Doris 已经拥有全部管道:CloudKit 私有库、Stop hook 一键注册、签名 CLI、OutboxZone 静默推送——**别人要从零建的基础设施,Doris 只差产品化的最后一公里**。
- 隐私故事(「我们结构上不可能看到你的数据」)是 Omnara 们抄不了的,应写进官网首屏。

### 3.2 差异化护城河的三层结构

1. **结构护城河(最硬)**:无中继 iCloud 手机桥 + notch 地形(Windows 桌宠永远无法复制刘海)+ 签名 CLI/MCP 入口。
2. **资产护城河(最独特)**:卡通助手。但前提是她从吉祥物升级为角色——有人设、对用户的工作负载有反应、跨设备连续存在。「有脸的多 agent 状态板」是全品类最可营销的 demo 片段。
3. **文化护城河(最便宜)**:赛博美学 + 中文日期解析(西方竞品集体盲区)+ 中英双语完整本地化。二次元 + 开发者的人群交集恰好是跑 agent 最多的人群。

### 3.3 一句话定位

> **「她住在你的刘海里,替你盯着你的 AI agents,顺便管好你的今天。」**
> 任务系统是她服务你的方式,不是产品本体;agent 通知是钩子,角色是留存,任务是日常使用的底盘。

变现路线与定位自洽:**核心功能 + 同步永久免费,卖衣橱不卖工作**(一次性买断的服装包/主题包/Live Activity API,Desktop Mate 模式 90% 好评验证)。拒绝订阅制——目标人群有严重订阅疲劳。

---

## 4. 分维度详细建议

### 4.1 功能性(4.5 → 目标 7)

**① 到期提醒,由她来「递纸条」**
- **做什么**:UNUserNotificationCenter 双平台本地通知,全局设置「到期前 N 分钟提醒」默认 30 分钟(不要做成每任务手动设);通知带「完成 / 推迟15分钟 / 今晚」action 按钮,完成动作复用 iOS Widget 已有的 ToggleTaskIntent 写库逻辑。macOS 上不走系统横幅,复用 anchor banner:她拿着一张 sticky 风格小纸条滑入,过期态用柔光不用红色羞辱。
- **抄谁**:Todoist 默认自动提醒 + TickTick 可操作通知 + Tiimo 无羞耻设计。
- **为什么**:任务管理器的最核心契约;同时是全品类唯一「有人格的提醒」。
- **工作量**:中(2-3 周,与 iOS 推送注册共用授权流程)。

**② 一个双语 NL 解析器,一次投资三处回报**
- **做什么**:标题输入框/捕获卡实时解析「明天3pm / fri 9am / 每周一」,识别片段渲染为发光青色 chip,Enter 确认、点击可撤销还原字面文字。英文走 NSDataDetector,中文手写规则集(今天/明天/后天/下周X/X月X日/晚上8点,几十条规则覆盖九成用法)。同一解析器输出 recurrenceRule 给重复任务。前置:Note.dueDate 从 start-of-day 升级为可带时间。
- **抄谁**:Todoist 行内高亮 + Fantastical 可逆性。
- **为什么**:中文日期解析是西方全部竞品的盲区,对「赛博笔记」是真护城河;没有时间粒度,提醒功能也立不起来。
- **工作量**:中(2 周)。

**③ 重复任务:双模式,完成即克隆**
- **做什么**:Note 加 recurrenceRule 字段({mode, interval, unit, weekday/monthday}),固定周期 + 完成后重复两种模式都要(只做固定模式会制造过期噪音);完成时克隆该行盖新 due chip,完全契合 notes-are-tasks,无需调度器。注意走 docs/cloudkit-schema.md 的 Development→Production 部署流程——拖越久迁移成本越高。
- **抄谁**:Things 3 的 fixed / after-completion 双模式。
- **工作量**:中(1-2 周,含 schema 部署)。

**④ Agent hub 升级为「验证包 + 等待感知」**
- **做什么**:(a) 一键注册里追加 Claude Code 的 Notification hook,渲染为「Claude 在等你」专属横幅并常驻 fix 卡——直击「agent 卡 40 分钟没人知道」的最痛点;(b) hook 富化 payload:cwd 项目名、Codex last-assistant-message / Claude transcript 尾部一句话摘要、`git diff --stat` ±行数,横幅显示「Codex 完成 · 3 files +120 −14 · "加了重试逻辑"」,点击聚焦终端;(c) 下拉面板加「Agent 收件箱」分区(数据已在 MessagesZone 流动,只缺按 agent 过滤的视图),avatar 挂运行中/待处理计数角标。
- **抄谁**:Warp 通知邮箱 + Conductor 完成摘要 + Omnara/Happy 的等待推送。
- **为什么**:「Done」是大宗商品,「改了什么 + 安不安全 + 下一步」才是产品;这是护城河战场的正面阵地。
- **工作量**:中(2-3 周)。

**⑤ doris mcp:任务清单与 agent 队列合一**
- **做什么**:签名 CLI 加 `doris mcp` 子命令(stdio JSON-RPC),暴露 notify(title, body, project) 和 note_add(title, due, checklist) 两个工具——任何 agent(Cursor/Gemini CLI/Copilot)一段配置即接入,且 agent 收尾时能自动建「剩余工作」笔记带 checklist。顺手对齐 CLI 版本号 0.1.0 → app 版本。
- **抄谁**:Bark/agent-notifier 的 MCP 通知工具 + Vibe Kanban 的任务↔agent 联动。
- **为什么**:成为「你的 TODO 列表就是你的 agent 队列」的唯一产品——Omnara 无任务系统、Vibe Kanban 无个人层无手机端,都跨不过来。
- **工作量**:中(ArgumentParser 骨架与 IPC 写入路径全部现成)。

### 4.2 易用性(4 → 目标 7)

**① 全局捕获热键 + 从 notch 落下的捕获卡**
- **做什么**:默认 Option+D(KeyboardShortcuts 已是声明依赖,废物利用),从 avatar 位置垂落无边框霓虹捕获卡,覆盖全屏 app 之上:Enter 存任务、Shift+Enter 续写正文、Esc 零成本取消;失焦不丢稿——缩成 notch 旁小 chip,再唤起恢复草稿;预热面板,目标 <100ms 可交互;输入中即时吃 NL 日期解析。
- **抄谁**:Things Quick Entry + Raycast 单热键浮窗 + Todoist pin-on-blur。
- **为什么**:每一个 2024-26 获胜的 Mac 工具共享这一个模式;这是把 Doris 从「要去拜访的面板」变成「条件反射」的单点最高杠杆改动。
- **工作量**:中(2 周)。

**② 修 Enter 双行 bug + 键盘流全审计(一个工作包)**
- **做什么**:修 TodoTitleField 的 @Query 异步刷新与 deferred-focus 竞态(插入操作加幂等 token 或 onSubmit 去重),补 XCUITest 防回归;同一冲刺补齐:↑↓ 选行、Space 勾选、Cmd+1/2/3 切 tab、Cmd+F 聚焦搜索、Cmd+P 置顶、Delete 入回收站。验收标准一条:「新建→录入5条→勾完2条→置顶1条→归档」全程手不碰鼠标。
- **抄谁**:Things Type Travel + Godspeed「速度即产品」。
- **工作量**:中(1-2 周)。

**③ Mac 端全局搜索(Cmd+F)**
- **做什么**:主窗口和下拉面板列表头部加搜索框,标题+正文实时过滤——iOS NotesScreen 的过滤逻辑(含中文输入法适配)已写好,搬进 DorisUI 双端复用;结果中 Enter 直接打开第一条编辑器。
- **为什么**:修复「iOS 有、Mac 没有」的体验倒挂,是全清单最便宜的高收益项。
- **工作量**:小(2-3 天)。

**④ 60 秒首启引导,由她本人带路**
- **做什么**:3-4 步 coach mark:她指向自己「右键我有菜单,拖我可以去任何屏幕边缘」→ 演示右键菜单高亮「贴到桌面」→ 提示捕获热键并让用户当场录入第一条任务(完成时播 celebrating 形成第一次奖励回路)→ 一行「语音和应用集成在设置里」带跳转。静态 overlay 即可,无需新动画素材。
- **抄谁**:CleanShot X 分步引导。
- **为什么**:LSUIElement 无 Dock 图标的 app 不自我介绍 = 赌用户自己摸索;引导决定所有已建好功能的被发现率。
- **工作量**:小(3-4 天)。

**⑤ avatar「交互契约」:吃满顶边 Fitts 红利**
- **做什么**:hover = 单行 peek(「15m → 站会 · 今天 3 项」);Option+click = 唤起捕获卡;拖文本/链接到她身上 = 接住动画 + 建任务(正文带来源);长按 = 摸头(见 4.4)。每种手势配轻量角色反馈,让语义可被试探发现。同时把隐藏功能提到一级界面:编辑器顶栏加「贴到桌面」按钮、avatar 右键菜单加「桌面面板」开关、icon-only 按钮全部补 .help() tooltip。
- **抄谁**:Alcove 的 interaction parity + SideNotes 拖放即建。
- **工作量**:中(与 4.4 的角色互动合并实施)。

### 4.3 美观程度(5.5 → 目标 7.5)

**① 重做 iOS 图标(一天能修的最高 ROI)**
- **做什么**:1024 图全出血重排——人物铺满方形画布,去掉烘焙进图的圆角矩形/白边,由系统打 squircle 蒙版;Contents.json 补 iOS 18 dark(深底霓虹描边)和 tinted(灰阶)变体;mac 图标补一笔品牌粉(如耳机灯一粉一青)。验收:真机主屏三种模式无白框、无双圆角。
- **抄谁**:Lumy(ADA 入围作品 day-one 适配 tinted/dark)。
- **工作量**:小(1 天)。

**② 浅色模式对比度专项 + 调色板收口**
- **做什么**:立硬规则——霓虹原色只用于描边/辉光/徽章等装饰层,文本一律用加深变体;CyberPalette 加 neonCyanText(浅色 ≈#0099B8)/neonPinkText(≈#D6258F)token,批量替换 43 处 neonCyan 文本用法;同一冲刺把 78 处 Color(red:) 字面量归还 CyberPalette(4 个漂移的品牌粉统一到 #FF4DBF),加 SwiftLint custom rule 锁死防回归。Accessibility Inspector 过 4.5:1。
- **为什么**:色值不收敛,后续一切主题化工作(Calm Mono、皮肤系统)都不可能;浅色模式目前是「关了灯的深色」。
- **工作量**:小+中(收口半天,浅色调校 1 周)。

**③ 动效系统化 + 修 banner 瞬切的根因**
- **做什么**:建 DorisMotion 三档曲线——brand spring(0.30, 0.80)/quick 0.18s/settle 0.25s,全库 easeInOut 杂牌军归位;banner 改不透明合成底色修掉「半透明混色」根因,把 .identity 瞬切换成从 notch 滑出 + brand spring 落位;任务完成做收尾编排:打勾→粉青粒子微爆→划掉停留 0.3s→下一行 spring 滑入补位(widget 端用 .invalidatableContent() 复刻同一节奏)。
- **抄谁**:Things 3「完成后下一项滑入」+ Alcove「动效物理与系统一致」。
- **为什么**:通知是旗舰场景,值得一条有签名感的动效;目前旗舰场景零动效。
- **工作量**:中(1-2 周)。

**④ 层级减法:让发光稀缺化**
- **做什么**:CyberCard 默认描边降为中性 hairline(primary 0.08),pink→cyan 渐变描边只留三处——当前 banner、置顶区第一张卡、正在编辑的卡;扫描线和呼吸 halo 强度挂到 ambientIntensity 参数(标准/低/关,「关」同时停掉 repeatForever 计时器,把 idle CPU 做成可宣传数字)。
- **抄谁**:Flighty 的信息克制;NotchNook 是反面教材(8-12% idle CPU 毁掉口碑)。
- **工作量**:小(2-3 天)。

**⑤ Widget 渲染语境补课 + EventsWidget 升级**
- **做什么**:hero 计数/LED 点/进度环加 .widgetAccentable(),非 fullColor 模式去掉 plusLighter 霓虹层;处理 showsWidgetContainerBackground(StandBy/CarPlay);新增 accessoryCircular(Gauge 环复用 16pt trim ring 代码);EventsWidget 按「出发板行文法」重做(来源 logo 点 + 单行标题 + 等宽 HH:mm),与 TasksWidget 共用 token;TasksProvider 在 startOfDay(+1) 发显式 entry,让过期/日期翻转精确到午夜。
- **抄谁**:Flighty 出发板 + Streaks 的 accessoryCircular。
- **工作量**:中(1 周)。

### 4.4 二次元程度(3 → 目标 7)——**这是战略投资区**

**① mood = f(时间, 天气, 任务负载)**
- **做什么**:HeroEvents 总线新增任务事件:勾掉一个任务→小庆祝(复用 celebrating 短播);勾掉今日最后一项→大庆祝 + 从 checkbox 飞出霓虹能量粒子落到菜单栏头像(粒子系统已有);多项逾期→担忧姿态(先用 confused + 低饱和滤镜过渡)。永远不愤怒、不死亡——Finch 证明温和梯度才是 $30M ARR 的留存配方。
- **为什么**:「因为我做了事所以她高兴」是所有成功桌宠的 aliveness 第一原理;任务数据是 Doris 相对纯桌宠的独家输入源。**全清单杠杆最高的一条,且是 small 工作量。**
- **工作量**:小(3-5 天)。

**② 一页角色圣经,先有人设再谈 AI**
- **做什么**:定稿名字(与 app 同名与否,做决定并贯彻)、生日、口头禅、一个可爱缺陷(建议:对自己的天气预报蜜汁自信,报错了闹小别扭——天气功能已有,零成本联动);全 app「她说的话」(问候/通知文案/空状态)改写成她的口吻,EN/中文,存成用户可编辑的 JSON 语料文件(直接成为未来社区台词包的 mod 入口)。
- **抄谁**:Neuro-sama 研究结论——依恋绑定在稳定怪癖人格上,与 LLM 智能无关,一行 AI 都不用写。
- **工作量**:小(2-3 天写作 + 字符串替换)。

**③ 仪式三件套:早安、晚结、清晨小礼物**
- **做什么**:(a) 接 macOS 解锁事件(LSUIElement 常驻零新基建),当日首次解锁→挥手 +「早上好,今天 3 件事,有雨带伞」(天气+任务数全有);(b) 晚 6 点后清空今日→「今天辛苦了」;(c) 模板字符串今日小结卡(「今天完成 5 件,最棒的是搞定了『发布 v1.2』!」)——纯模板无 AI;(d) 昨日有完成记录→她「夜里出门探险」,次日首开带回金币/低概率配饰 + 一句明信片。
- **抄谁**:Gatebox 回家问候 + Finch 清晨探险归来。
- **为什么**:仪式把「每天打开」从习惯升级为期待;同时是对抗胡桃日记式「4-6 周互动衰减」的内容锚点。
- **工作量**:中(1-2 周)。

**④ 她夺回信使位 + notch 地形**
- **做什么**:agent 横幅到达时她做「接住/递出」动作,品牌 logo 变成她手里的信封而非替换她的头像;agent 运行中(SessionStart hook)她在 notch 旁打字,被阻塞时举手;notch-as-terrain 微行为 2-3 个起步(倚着刘海、坐在刘海边晃腿、从刘海后探头);长按 = 摸头(闭眼、脸红、心形粒子,按羁绊等级递进)。
- **抄谁**:Desktop Goose「角色亲手递送内容」+ Shimeji 地形行为 + Desktop Mate 摸头。
- **为什么**:「有脸的 agent 状态板」全市场无人做,是最可营销的 demo;刘海地形是 Windows 桌宠永远无法复制的独占资产。
- **工作量**:中(与新动画素材排期绑定)。

**⑤ 活跃度滑杆 + 勿扰静默:先装安全阀**
- **做什么**:设置加「助手活跃度」三档(安静/标准/活泼),macOS 专注模式开启时自动降到安静档。上面所有仪式/自发行为必须挂在这个旋钮下。
- **为什么**:Desktop Goose 被爱而 Clippy 被恨的全部区别就是这一个滑杆;现在做是一个枚举,行为多了再补是返工。
- **工作量**:小(1-2 天)。

### 4.5 个性化(2.5 → 目标 6)

**① 先做减法:清死设置,重建可信的「微调」区**
- **做什么**:删 Cmd+, 的 Sidebar/Shortcuts 死 Tab 及 hex 预览开关(连同 Sidebar/、Notch/ 死代码与 DynamicNotchKit 依赖,ClickActionRouter 先迁出),两个设置入口合并为一个;新增「微调」分组只放真实生效项:列表密度、周起始日、12/24 小时制、横幅时长全局覆盖(0.5x-2x)、头像活跃度。
- **抄谁**:Itsycal 微偏好深度 + Things「每一项都生效」。
- **工作量**:小(3-4 天)。**这是该维度 ROI 最高的一步:先让每个开关说真话。**

**② Widget 迁移 AppIntentConfiguration**
- **做什么**:TasksWidget 暴露三配置:分桶过滤(全部/置顶/日程/长期)、显示已完成开关、主题(Neon/Calm Mono/Paper);hero 行和空状态加 doris://new 的「+」Link。一个小组件变成一个目录,用户可并排摆「粉色置顶板 + 青色日程表」。
- **抄谁**:Fantastical per-widget 筛选 + Widgetsmith 主题即产品。
- **工作量**:中(与 4.3-⑤ 渲染审计合并一次做)。

**③ per-source 通知偏好 + 「添加自定义来源」**
- **做什么**:集成页每个来源行挂展开式偏好:提醒时机分流(完成时/需要输入时/仅出错/仅运行超 N 分钟)、横幅时长、强调色(粉/青/紫——多 agent 并行靠颜色认人)、完成音效;页底加「+ 自定义来源」:填名称/选图标/选色,生成可复制的 `doris notify --source xxx` 片段 + Gemini CLI/Cursor/GitHub Actions 现成配方,检测到 $HOME 配置文件时主动亮起「可一键接入」;cliSourceAllowlist 从只读变成这个界面的管理面。
- **为什么**:底层零新管道(IPC/HMAC/CLI 全现成),纯 UI 工作,却把 Doris 从「Claude/Codex 专属」升级为「任何终端长任务的通知中枢」。
- **工作量**:小+中(自定义来源 1 周,per-source 偏好 1-2 周)。

**④ 命名主题包 + 头像衣橱 v1**
- **做什么**:CyberPalette 抽象为 ThemePack 协议,首发三套有名字的主题:霓虹(默认不变)、素白 Paper、静音 Mono(灰阶细线版,直接照搬已验证的 widget「Calm Focus」语言,给「开会时不想被看到粉色霓虹」的人群一个出口);衣橱 v1 用单张 PNG 覆盖层做 3-5 个配件(墨镜/猫耳/围巾),成就解锁型(连续 7 天清空→围巾,累计 1000 任务→传说夹克)+ 未来付费包;设置加「衣橱/收藏册」页展示已解锁与剪影。
- **抄谁**:Antinote 命名主题养粉丝文化 + Habitica 装备即成就账本 + Desktop Mate DLC。
- **为什么**:主题包 = 配色 + widget 皮 + 头像配件的可售卖单元,是个性化与变现的合流点。
- **工作量**:中(主题 1-2 周;衣橱依赖覆盖层渲染,2 周)。

**⑤ Today 分桶轻配置**
- **做什么**:三桶允许改名、隐藏、可选「今晚 This Evening」细分(实现上只是 Today 内一条分隔线 + 布尔标记);桌面面板获得「显示哪些桶」多选。刻意不做自定义任意桶——只开放命名权和显隐权。
- **抄谁**:Things 3 的 This Evening。
- **工作量**:小(3-4 天)。

### 4.6 专业度(4 → 目标 7)

**① 接入 Sparkle 2 自动更新(本季度最高优先级)**
- **做什么**:SPM 加 Sparkle 2,Info.plist 配 SUFeedURL + SUPublicEDKey;scripts/release.sh 末尾追加 generate_appcast,appcast.xml 托管 GitHub Pages;头像右键菜单和设置加「检查更新…」,默认后台静默检查;注意 Sandbox 兼容(XPC installer)。
- **抄谁**:CleanShot/Rectangle/Alcove——Developer-ID 分发的事实标准,无一例外。
- **工作量**:中(3-5 天)。

**② 数据安全从谎言变成卖点**
- **做什么**:(a) 已有的 BackupService.snapshot() 接到「每日自动备份」开关(启动时距上次 >24h 即跑,保留 7 份),补 restore(from:) + 设置「备份」页一键恢复;(b) 「导出全部笔记」:Note 转 Markdown(frontmatter 带 due/pin)打包 zip,macOS NSSavePanel / iOS ShareSheet;(c) JSON 全量导出/导入兜底。隐私文案升级:「数据只在你的设备和你的 iCloud,随时整体带走」。
- **抄谁**:Things 本地备份 + Bear 的 Markdown 导出底线。
- **工作量**:中(1-2 周)。

**③ 零成本诊断闭环**
- **做什么**:MetricKit(免费、隐私安全、无第三方 SDK)收崩溃/卡顿;os.Logger 给 Sync/IPC/Integrations 三链路打结构化日志落 Logs/doris-debug.log(环形 5MB 上限——architecture.md 早已规划);设置加「导出诊断信息」打包 zip;CLI 加 `doris doctor` 自检 IPC/签名/CloudKit 状态——对开发者用户群这本身就是专业度展示。
- **工作量**:小(3-5 天)。

**④ 无障碍基线 Pass**
- **做什么**:第一周全部 icon-only 控件补 accessibilityLabel(主题切换/SyncNow/悬停按钮/checkbox 补 Value);第二周 iOS 103 处固定字号换 .system(.body) 或 @ScaledMetric。不求满分,求 VoiceOver 能完整走完「建任务→设日期→完成」。
- **为什么**:App Store 上架 iOS 后免差评的门票;Tiimo 证明无障碍本身可以是独立应用的品牌资产(ADA)。
- **工作量**:中(2 周,可拆散执行)。

**⑤ 一页官网 + 隐私页 + Cmd+/ 快捷键速查 + 空闲性能预算**
- **做什么**:GitHub Pages 单页官网(截图/DMG 带 sha256/TestFlight/changelog/支持邮箱);隐私页一段话讲透「无服务器无账号无埋点」;应用内 Cmd+/ 弹赛博风快捷键速查浮层;Instruments 锁定「空闲 ≤0.1% CPU、<80MB 内存」预算(审计面板收起后 20fps 星空是否仍在跑),数字写上官网——NotchNook 因 8-12% idle CPU 全网差评,Itsycal 把 8MB 内存当卖点夸。
- **工作量**:小(合计 1 周)。

---

## 5. 优先级路线图

### Quick Wins(1-2 周内,并行可做)

| # | 动作 | 预期影响 |
|---|---|---|
| 1 | **嵌入已写完的 Share/Intents 扩展**(改 project.yml dependencies) | 高——已付出的开发成本从零变现,分享菜单/快捷指令/Siri 一天内全通 |
| 2 | **修 Enter 双行 bug** + 补防回归测试 | 高——最高频路径的信任修复,「键盘优先」口碑的前提 |
| 3 | **删死设置**(Sidebar/Shortcuts 死 Tab、hex 预览;auto-backup 改为接通)+ 合并双设置入口 | 高——消灭 hobby-grade 最强信号 |
| 4 | **Mac 端 Cmd+F 搜索**(移植 iOS 过滤逻辑进 DorisUI) | 高——最便宜的体验倒挂修复 |
| 5 | **重做 iOS 图标**(全出血 + dark/tinted 变体) | 高——第一视觉触点,1 天工作量 |
| 6 | **mood 接任务事件**(完成→庆祝、清空→大庆祝、逾期→担忧) | 高——角色从吉祥物到活物的第一步,复用现有动画 |
| 7 | **CLI 版本号对齐** + `doris doctor` 自检 + MetricKit 接入 | 中——开发者用户群的细节信任 |
| 8 | **调色板收口**(78 处字面量归还 token + lint 锁死)+ 霓虹层级减法 | 中——解锁后续一切主题化工作的前置 |

### 中期(1-2 个月,按序)

| # | 动作 | 预期影响 |
|---|---|---|
| 1 | **任务 table stakes 包**:到期提醒(默认开 + action 按钮)+ NL 双语日期解析 + 双模式重复任务(一次 CloudKit schema 部署打包做) | 极高——拔掉全部四个「评测即出局」硬伤中的三个 |
| 2 | **捕获前门**:Option+D 全局捕获卡(失焦保稿、<100ms)+ 键盘流全审计 + 60 秒首启引导 | 极高——「想法到落库 <1 秒」契约 + 已建功能的被发现率 |
| 3 | **Agent hub v1.0**:Notification hook(等待感知)+ 验证包横幅(项目名/diff/摘要)+ Agent 收件箱 + per-source 通知偏好 + 自定义来源入口 | 极高——护城河正面阵地,核心人群感知最强 |
| 4 | **信任基建**:Sparkle 自动更新 + 备份接通/Markdown 导出 + 单页官网/隐私页 | 高——把修 bug 的努力转化为用户信任的唯一管道 |
| 5 | **Widget 升级包**:AppIntentConfiguration(分桶/主题/捕获 Link)+ 渲染语境审计 + 完成编排 + 仪式三件套(早安/晚结/探险) | 高——iOS 端存在感 + 每日打开的期待感 |

### 大赌注(3-6 个月,最多并行两个)

| # | 动作 | 预期影响 |
|---|---|---|
| 1 | **无中继手机桥 + Agent Live Activity**:Mac 空闲检测(CGEventSource)→ 经自己 iCloud 推送 agent 事件到 iPhone(一个开关「人不在时转发到 iPhone」);iOS 17.2+ push-start Live Activity——agent 会话点亮灵动岛(logo + 项目 + 计时),结束变「完成 · 3 files ±N」。**本地 agent 的 Live Activity 是 first-to-market**,隐私故事 Omnara 结构上抄不了 | 极高——定义品类的功能,官网首屏故事,最可传播的 demo |
| 2 | **doris mcp + 任务↔agent 队列融合**:MCP server(notify/note_add)、agent 自动建「剩余工作」checklist、任务关联 agent run(Stop hook 翻「待审查」状态 chip) | 高——「TODO 列表就是 agent 队列」的唯一产品,生态从 2 个集成扩到全部 agent |
| 3 | **角色资产升级 + 衣橱经济**:分层渲染重构(本体剪辑 + 配饰锚点叠层,摆脱 7×65 帧重绘)→ 羁绊等级 → 配饰掉落/荣誉装 → 皮肤 JSON 规范 + `doris skin install` 开放社区 → 一次性付费服装包 | 高——留存底盘 + 唯一变现引擎 + 社区成为内容团队(solo dev 唯一可持续的内容速度) |

> **排期纪律**:每个月度版本至少滴灌一个新反应/配饰/台词包(对抗胡桃日记式 4-6 周衰减);大赌注 1 必须在 GitHub Mobile 们扩展到本地 agent 之前抢落地。

---

## 6. 刻意不做清单

1. **协作 / 多人共享 / 评论 / 权限**——「独立开发者的桌面伴侣」是单人产品,协作意味着账号体系、冲突合并 UI、权限矩阵,是 solo dev 的无底洞,且与「她只属于你」的角色叙事直接冲突。唯一的远期例外:CKShare 共享单条清单(零服务器成本),也要等核心闭环跑通之后。

2. **自建服务器 / 账号体系 / 推送中继**——「无服务器、无账号、数据不过我们的手」是 Doris 对 Omnara/Happy 唯一的结构性优势,任何一台自建服务器都会把它毁掉,还附赠运维成本和隐私合规负担。所有跨设备能力一律走用户自己的 iCloud。

3. **内嵌 LLM 聊天助手 / 「和她对话」的 AI 化**——Neuro-sama 研究的结论是依恋绑定在稳定人格而非智能上;LLM 对话会引入 API 成本、人格漂移、内容风险三重负担,而一页角色圣经 + 模板台词的效果更好且零成本。远期若做,只做 BYO-key/本地模型的可选项,且必须在人设稳定之后。

4. **看板 / 项目管理 / 时间追踪 / 甘特图**——与 Things 3 同样的克制:Doris 的任务模型是「今天的三个桶」,不是项目管理。每加一层结构(文件夹/标签 UI/嵌套项目)都在稀释「打开即懂」的轻盈感——Tag/Folder 孤儿模型宁可先用「智能筛选 chip 行」替代,也不补三套管理 UI。

5. **订阅制 + 短期内 Mac App Store 上架**——目标人群(Apple 系独立开发者/效率用户)订阅疲劳是实锤,Things/Sorted 的一次性买断是被验证的路径;变现只卖衣橱(服装/主题/Live Activity API),永远不把捕获、同步、任务功能关进付费墙。MAS 则与现有 temporary-exception entitlements(~/.claude、~/.codex 写入)直接冲突——为上架阉割 agent 集成等于砍掉护城河,Developer-ID + Sparkle 是正确的家。

---

**结语**:Doris 的危险不在于做得不够多,而在于把力气均匀地撒在红海里。它手里攥着三张全市场独一份的牌——刘海里的女孩、签好名的 agent 管道、用户自己的 iCloud——接下来六个月的全部要义,是把「人人都有而 Doris 没有」的基础补到不丢分,然后把这三张牌打到别人看得见的地方。