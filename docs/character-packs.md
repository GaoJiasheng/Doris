# Character Packs(形象包)— 设计 + 素材规格

Doris 的可视形象做成**可切换的「形象包」(CharacterPack)**。一个包打包了一套
完整形象:动画角色、菜单栏头像、品牌 logo、选择缩略图。用户在设置里选哪个包,
全 App 的形象就整套切换。目前的「小姑娘」是内置的第一个包(`girl`)。

加一个新形象 = 按下面的目录结构丢一个文件夹进 `Characters/<id>/` + 一个
`pack.json`,重新构建即可被发现,无需改代码。

---

## 1. 目录结构(每个包一个文件夹)

放在 `packages/DorisUI/Sources/DorisUI/Characters/<packID>/`:

```
Characters/
  robot/                      # packID:小写英数 + 连字符,全局唯一
    pack.json                 # 清单(见 §3)—— 必需
    portrait.png              # 菜单栏圆形头像 —— 必需
    anim/                     # 动画帧 —— 必需(至少 idle)
      idle/        idle_0001.png … idle_0065.png
      greeting/    greeting_0001.png … _0065.png
      alerted/     …
      listening/   …
      celebrating/ …
      walking/     …
      confused/    …
    logo.png                  # 包内品牌图 —— 可选
    icon.png                  # App 图标源图 1024×1024 —— 可选(见 §5)
    thumb.png                 # 设置里的选择缩略图 —— 可选(缺省用 portrait)
```

`packID` 是文件夹名;清单里的 `id` 必须与之一致。

---

## 2. 各类素材的硬性规格

### 2.1 动画角色 + 动画(必需)

- **格式**:PNG 序列帧,**透明底(alpha 通道)**。背景必须抠干净——角色之外
  全透明,这样 App 的赛博背景(白天/夜间天空 + 星空)能透出来,无缝。
- **尺寸**:建议 **418×628 px**(竖向,约 1:1.5),与现有「小姑娘」一致即可。
  可以更大(等比即可),渲染时按 `.fill` 裁切到卡片;只要每个情绪内部帧尺寸一致。
- **帧数**:每个情绪 **65 帧**(现有标准)。可不同,但同一情绪内帧数一致;
  加载器按文件名排序播放。
- **命名**:**`<mood>_0001.png` … `<mood>_NNNN.png`**,四位零填充,从 0001 起。
  前缀必须等于情绪名(文件夹名)。
- **帧率**:源 16fps(循环情绪回放 12fps、一次性情绪 16fps)。可在 `pack.json`
  覆盖。
- **情绪清单**(7 个,与代码 `HeroMood` 对应):
  | 情绪 | 类型 | 用途 |
  |---|---|---|
  | `idle` | 循环 | 默认待机(**必需**) |
  | `listening` | 循环 | 语音输入中 |
  | `walking` | 循环 | (备用循环) |
  | `greeting` | 一次性 | 每日首次打开 / 点击打招呼 |
  | `celebrating` | 一次性 | 完成任务 |
  | `alerted` | 一次性 | Agent 通知 / 提醒 |
  | `confused` | 一次性 | 被连续戳(彩蛋) |
  - **至少提供 `idle`**;缺的情绪自动回退到 `idle`(所以可以先只做 idle 跑通,
    再逐步补)。

### 2.2 头像(菜单栏圆头,必需)

- **文件**:`portrait.png`
- **尺寸**:**正方形**,建议 **544×544 px**(与现有一致)。会被裁成圆形显示在
  ~26pt 的菜单栏图标里,所以**主体居中、留点边距**,别贴边。
- **背景**:透明或纯色都行(圆形裁切后边缘外不可见)。

### 2.3 选择缩略图(可选)

- **文件**:`thumb.png`,正方形,256×256 足够。设置里形象选择器用。缺省回退 `portrait.png`。

### 2.4 包内品牌图 / logo(可选)

- **文件**:`logo.png`,透明底,横向或方形皆可(建议高度 ≥ 128px)。
  用于 App 内品牌位(启动页 / 关于页等)。**不是** App 图标(见 §5)。

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
| `id` | ✅ | 与文件夹名一致,小写英数+连字符 |
| `displayName` | ✅ | 中文显示名(设置里展示) |
| `displayNameEN` | — | 英文名;缺省用 `displayName` |
| `moods` | — | 本包提供的情绪;缺省自动探测 `anim/` 下的子文件夹 |
| `fps` | — | 一次性情绪帧率,缺省 16 |
| `loopFps` | — | 循环情绪帧率,缺省 12 |

---

## 4. 选择与持久化

- 选中的 packID 存在 `UserDefaults`(键 `doris.character.selectedPack`),跨重启保留。
  (头像形象只在主 App 进程里用到,不需要进 App Group;若以后小组件也要换形象再改。)
- 设置页提供形象选择器(缩略图 + 名字),即时切换——动画角色、头像整套换掉,
  无需重启。
- 默认值:`girl`(内置「小姑娘」)。

---

## 5. App 图标 / logo 的平台限制(重要)

App 图标**不能在运行时随意换成任意图片**,这点和上面其它素材不同:

- **iOS**:支持「备用图标(Alternate Icons)」——但必须在**构建时**预先打包,
  并在 `Info.plist` 的 `CFBundleIcons → CFBundleAlternateIcons` 声明,运行时用
  `setAlternateIconName(_:)` 切换。所以每个想换图标的包,需要提供一套
  **App 图标源图 1024×1024**(`icon.png`),由构建流程生成备用图标集。不能用任意
  用户图片。
- **macOS**:Finder 里的文件图标构建时固定;但**运行中**可以用
  `NSApp.applicationIconImage` 换 Dock 上的图标(随包切换)。

**建议**:先把「动画角色 + 头像 + 包内 logo」三项做成完全可换(框架已支持);
App 图标按需为每个包提供一张 `icon.png` 1024×1024,后续我接 iOS 备用图标 +
macOS Dock 图标切换。你准备 `icon.png` 时只要给 1024×1024 不透明方图即可。

---

## 6. 准备素材清单(给你打勾用)

每个新形象包:

- [ ] `pack.json`(§3)
- [ ] `portrait.png` 544×544 正方形头像(§2.2)
- [ ] `anim/idle/idle_0001.png …`(至少 idle;每情绪 65 帧,418×628,透明底)(§2.1)
- [ ] 其余情绪动画(greeting / celebrating / alerted / listening / walking / confused)——可后补
- [ ] `thumb.png` 256×256(可选,缺省用 portrait)
- [ ] `logo.png` 透明底品牌图(可选)
- [ ] `icon.png` 1024×1024 App 图标源图(可选,做可换图标时需要)

做好后丢进 `packages/DorisUI/Sources/DorisUI/Characters/<id>/`,告诉我,我接上选择器
就能在设置里切换。
