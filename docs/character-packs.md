# Character Packs(形象包)— 设计 + 素材规格

Doris 的可视形象做成**可切换的「形象包」(CharacterPack)**。一个包打包一整套形象:
**App 图标、动画角色、视频帧、头像、主题配色**(再加刘海像素 logo、品牌图、缩略图)。
用户在设置里选哪个包,全 App 的形象 + 配色就整套切换。目前的「小姑娘」是内置的第一个
包(`girl`)。

> 一套包 = `icon.png`(App logo) + `anim/`(形象/视频帧) + `portrait.png`(头像) +
> `pack.json` 里的 `theme`(主题配色) + `notch.png`(刘海 mark)。下面逐项给规格。

加一个新形象 = 按下面的结构丢一个文件夹进 `Characters/<id>/` + 一个 `pack.json`,
**重新构建**即可被发现,无需改代码。

---

## 1. 素材总表

放在 `packages/DorisUI/Sources/DorisUI/Characters/<id>/`(`<id>` = 小写英数+连字符):

| # | 素材 | 文件名 | 长宽比 | **制作尺寸** | 透明 | 关键要求 |
|---|---|---|---|---|---|---|
| 1 | 全身母图 | `fullbody.png` | 2:3 竖 | **1024×1536** | 可透明可纯底 | 设计源头;可不入包但建议留着 |
| 2 | 头像(圆头) | `portrait.png` | 1:1 | **1024×1024** | 任意(会圆裁) | 脸/上半身**居中留边** |
| 3 | 刘海像素 logo | `notch.png` | 1:1 | **96×96**(24 或 32 网格) | **必须透明** | **硬边、关抗锯齿**;最近邻渲染、不裁圆 |
| 4 | 成品动画帧 | `anim/<情绪>/<情绪>_0001.png …` | 2:3 竖 | **512×768** | **必须透明** | 角色居中留边(卡片会裁成更窄的 ~1:1.9) |
| 5 | 表情 MP4 源 | (临时,不入包) | 竖屏 9:16 或 2:3 | **1080×1920** | 生成时**纯底**(白/绿)好抠 | 抠背景+抽帧 → 变成 #4 |
| 6 | 选择缩略图 | `thumb.png` | 1:1 | 256×256 | 任意 | 可选;缺省用 #2 |
| 7 | 包内 logo | `logo.png` | 任意 | 高 ≥256 | 透明 | 可选;App 内品牌位 |
| 8 | App 图标源 | `icon.png` | 1:1 | 1024×1024 | 不透明 | 可选;桌面图标(见 §5) |

**`notch.png` 为什么是像素图**:它实际只显示 22–26pt(Mac @2x ≈ 44–52 像素),拿细致头像
缩到这么小会糊。所以单独做一张**像素 logo**:24×24 或 32×32 网格、硬边、导出 96×96,
框架用最近邻渲染且不裁圆,小尺寸下最清晰、也最搭赛博风。**没有 `notch.png` 时**自动回退
到圆形裁切的 `portrait.png`(小姑娘就是这样)。

---

## 2. 动画(#4 / #5)补充

- **7 个情绪**:`idle`(**必做**) · `greeting` · `celebrating` · `alerted` · `listening` · `confused` · `walking`
  - 缺的情绪自动回退到 `idle`,所以可以先只做 idle 跑通,再逐步补。
- **帧率**:一次性 16fps、循环 12fps(在 `pack.json` 设,按包可调)
- **帧数 / 时长**:一次性反应 **24–36 帧(1.5–2.2 秒)** · 循环(idle 等)**48–65 帧**
- **命名**:`<情绪>_0001.png`、`_0002.png`…(四位补零,前缀=情绪名=文件夹名)
- **背景**:**必须透明**(去背干净);生成 MP4 时用纯底,后期抠掉

| 情绪 | 类型 | 什么时候播 |
|---|---|---|
| `idle` | 循环 | 待机默认(**必需**) |
| `greeting` | 一次性 | 每日首次打开 / 点击打招呼 |
| `celebrating` | 一次性 | 完成任务 |
| `alerted` | 一次性 | 来通知 / 提醒 |
| `listening` | 循环 | 语音输入中 |
| `confused` | 一次性 | 被连续戳(彩蛋) |
| `walking` | 循环 | 备用 |

---

## 3. 清单 `pack.json`

```json
{
  "id": "robot",
  "displayName": "小机器人",
  "displayNameEN": "Robo",
  "moods": ["idle", "greeting", "celebrating", "alerted", "listening", "confused", "walking"],
  "fps": 16,
  "loopFps": 12,
  "theme": {
    "accentPrimary":   "#FF4DBF",
    "accentSecondary": { "light": "#008CBF", "dark": "#00D9FF" },
    "done":            "#9AA0A6",
    "backdropTop":     { "light": "#F0EEF9", "dark": "#1A0F2E" },
    "backdropBottom":  { "light": "#FDF8FF", "dark": "#05050D" }
  }
}
```

| 字段 | 必需 | 说明 |
|---|---|---|
| `id` | ✅ | 与文件夹名一致 |
| `displayName` | ✅ | 中文显示名 |
| `displayNameEN` | — | 英文名;缺省用 `displayName` |
| `moods` | — | 本包做了哪些情绪;缺省自动探测 `anim/` 子文件夹 |
| `fps` | — | 一次性帧率,缺省 16 |
| `loopFps` | — | 循环帧率,缺省 12 |
| `theme` | — | 主题配色;整块或任意单色可省,省的回退小姑娘色(见 §3.1) |

### 3.1 主题配色 `theme`(可选)

每个颜色都可省;省掉的自动回退到小姑娘默认色。颜色写法二选一:
**单串 `"#RRGGBB"`**(深浅模式同色,品牌色通常这样)或
**`{ "light": "#…", "dark": "#…" }`**(深浅模式各一)。支持 `#RRGGBB` 与 `#RRGGBBAA`。

| 键 | 作用(对应 `CyberPalette`) | 建议 |
|---|---|---|
| `accentPrimary`   | 主品牌色 `neonPink` — 高亮、激活态、进度、描边渐变之一 | 形象的标志色 |
| `accentSecondary` | 次品牌色 `neonCyan` — 链接、次高亮、描边渐变之二 | 与主色对比的另一色 |
| `done`            | 完成态 `doneAccent` — 划线 / DONE 药丸 / 完成卡描边 | 冷中性色,别和品牌色打架 |
| `backdropTop`     | 页面背景渐变**顶**色 | 深色模式深、浅色模式浅 |
| `backdropBottom`  | 页面背景渐变**底**色 | 同上 |

> 卡片玻璃面(`surfaceTop/Bottom`)目前仍是全局色,不随包变——保留通用毛玻璃质感。
> 想让某色也可换时告诉我,扩一行即可(`CharacterTheme` + `ThemeManifest` 各加一个字段)。

**作用范围**:配色由 `CharacterPackStore` 在启动时和切包时写入 `CyberPalette.activeTheme`,
全 App 205 处 `CyberPalette.X` 调用点不变就跟着换色。切包时观察 store 的界面立即变色,
**重启可保证每个界面都一致**。

---

## 4. 目录结构(以 `robot` 为例)

```
Characters/robot/
  pack.json
  fullbody.png        1024×1536  (源图, 建议留着)
  portrait.png        1024×1024
  notch.png           96×96  像素图
  anim/
    idle/        idle_0001.png …        (512×768, 透明)
    greeting/    celebrating/    alerted/
    listening/   confused/       walking/
  thumb.png   (可选 256×256)
  logo.png    (可选)
  icon.png    (可选 1024×1024)
```

**最省力起步版**:`pack.json`(moods 只写 `["idle"]`)+ `portrait.png` + `notch.png` +
`anim/idle/`(哪怕几帧)。这样就能在设置里切到新形象看效果。

---

## 5. 制作流程

```
①fullbody 1024×1536
   ├─ 裁脸 → ②portrait 1024×1024
   ├─ 做像素 → ③notch 96×96(24/32 网格, 硬边)
   └─ 当参考图喂 AI → ⑤MP4 1080×1920(纯底)
                        └─ 抠背景 + 抽帧 → ④anim 512×768 透明
```

- 抠视频背景:unscreen.com / rembg / RVM,或绿幕用 ffmpeg `chromakey`
- 抽帧:`ffmpeg -i clip.mp4 -vf fps=16 idle_%04d.png`

---

## 6. 选择与持久化

- 选中的 packID 存 `UserDefaults`(键 `doris.character.selectedPack`),跨重启保留。
- 设置页「形象」选择器即时切换——动画角色、头像、刘海 logo 整套换掉,无需重启。
  (选择器在装了**第 2 个包**后才出现。)
- 默认 `girl`。

---

## 7. App 桌面图标(按包切换 — 已接框架)

切换逻辑已由 `AppIconManager` 实现,跟随所选形象自动切换。两端机制不同:

- **macOS**:**纯运行时**。用包里的 `icon.png` 直接设 Dock 图标(`NSApp.applicationIconImage`)。
  **丢一张 `icon.png` 进包就生效**,无需额外步骤。(Finder 里的文件图标构建时固定,改不了;
  用户看到的是运行中的 Dock 图标。)
- **iOS**:**必须构建时预埋**。iOS 只能切换「编译进资源目录的备用图标」。所以每个要换图标的包,
  除了 `icon.png`,还要在 `Assets.xcassets` 里加一个名为 **`AppIcon-<id>`** 的「iOS App Icon」集
  (iOS target 已开 `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`)。运行时框架会
  `setAlternateIconName("AppIcon-<id>")` 自动切;没预埋则静默跳过(不崩)。
  > iOS 切换时系统会弹一句「已更改图标」——这是系统行为,改不掉。

**你要准备的**:每个包一张 **1024×1024 不透明方图 `icon.png`**。
- macOS 端:放进包就行。
- iOS 端:我拿这张 `icon.png` 在资源目录里建 `AppIcon-<id>` 图标集(可写个脚本从 1024 源图
  生成各尺寸)。你只管给 1024 方图。

不给 `icon.png` 的包,自动用 App 默认图标(小姑娘即如此)。

---

## 8. 准备素材清单(打勾用)

每个新形象包:

- [ ] `pack.json`(§3),含 `theme` 配色(§3.1)——主题:**App logo / 形象 / 视频 / 头像 / 主题**这一套里的「主题」
- [ ] `icon.png` 1024×1024 不透明方图(App logo,§7;不给则用默认)
- [ ] `portrait.png` 1024×1024 圆头(头像,§1.2)
- [ ] `notch.png` 96×96 像素 logo(§1.3)
- [ ] `anim/idle/idle_0001.png …`(至少 idle;512×768 透明帧)(形象/视频,§2)
- [ ] 其余情绪动画(greeting/celebrating/alerted/listening/confused/walking)——可后补
- [ ] `fullbody.png` 1024×1536 源图(建议留)
- [ ] `thumb.png` 256×256(可选)/ `logo.png`(可选)

做好丢进 `packages/DorisUI/Sources/DorisUI/Characters/<id>/`,告诉我 id,我接上即可切换。
内置 `Characters/_template/pack.json` 是带注释的清单模板,照着填最省事。
