# Character Packs(形象包)— 设计 + 素材规格

Doris 的可视形象做成**可切换的「形象包」(CharacterPack)**。一个包打包一整套形象:
动画角色、菜单栏头像、刘海像素 logo、品牌图、缩略图。用户在设置里选哪个包,全 App
的形象就整套切换。目前的「小姑娘」是内置的第一个包(`girl`)。

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
  "loopFps": 12
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

## 7. App 图标 / logo 的平台限制

App 桌面图标**不能运行时换任意图**(和上面其它素材不同):

- **iOS**:只能用「备用图标」——构建时预打包 + `Info.plist` 声明,`setAlternateIconName(_:)`
  切换。每个想换图标的包给一张 **1024×1024 `icon.png`**,由构建流程生成备用图标集。
- **macOS**:运行中只能换 Dock 图标(`NSApp.applicationIconImage`)。

所以 `icon.png` 给 **1024×1024 不透明方图** 即可;切换逻辑后续再接。前三样(动画/头像/
刘海 logo)已完全可换。

---

## 8. 准备素材清单(打勾用)

每个新形象包:

- [ ] `pack.json`(§3)
- [ ] `portrait.png` 1024×1024 圆头(§1.2)
- [ ] `notch.png` 96×96 像素 logo(§1.3)
- [ ] `anim/idle/idle_0001.png …`(至少 idle;512×768 透明帧)(§2)
- [ ] 其余情绪动画(greeting/celebrating/alerted/listening/confused/walking)——可后补
- [ ] `fullbody.png` 1024×1536 源图(建议留)
- [ ] `thumb.png` 256×256(可选)
- [ ] `logo.png` / `icon.png`(可选)

做好丢进 `packages/DorisUI/Sources/DorisUI/Characters/<id>/`,告诉我 id,我接上即可切换。
