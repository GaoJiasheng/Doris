# 形象包模板 (`_template`)

把这个文件夹整份复制成 `Characters/<你的id>/`,改 `pack.json`、丢素材,即成一个新形象包。
`_` 开头的文件夹**不会**被发现(不会出现在选择器里),所以本模板只作样板,不影响运行。

完整规格见 [`docs/character-packs.md`](../../../../../../docs/character-packs.md)。

## 一套 = 5 类素材

| 类 | 文件 | 必需 | 规格速记 |
|---|---|---|---|
| App logo | `icon.png` | 可选 | 1024×1024 不透明方图;不给则用默认图标 |
| 形象 / 视频 | `anim/<mood>/<mood>_0001.png …` | idle 必做 | 512×768 透明帧,2:3 竖 |
| 头像 | `portrait.png` | 建议 | 1024×1024,脸居中(会圆裁) |
| 主题 | `pack.json` 里 `theme` | 可选 | 见下,任意单色可省 |
| 刘海 mark | `notch.png` | 可选 | 96×96 像素图,硬边透明;不给则圆裁 portrait |

外加:`thumb.png`(选择缩略,可选)、`logo.png`(App 内品牌位,可选)、
`fullbody.png`(1024×1536 设计源图,建议留着不入包也行)。

## `pack.json` 字段

- `id` ✅ 必须等于文件夹名(小写英数+连字符)
- `displayName` ✅ 中文名 · `displayNameEN` 英文名(缺省同中文)
- `moods` 本包做了的情绪;省掉则自动扫 `anim/` 子文件夹
- `fps` 一次性帧率(默认 16)· `loopFps` 循环帧率(默认 12)
- `theme` 主题配色,**整块或任意单色可省**,省的回退小姑娘色:
  - 每色写法二选一:`"#RRGGBB"`(深浅同色)或 `{ "light": "#…", "dark": "#…" }`
  - `accentPrimary` 主品牌色 · `accentSecondary` 次品牌色 · `done` 完成态 ·
    `backdropTop` / `backdropBottom` 背景渐变顶/底

最省力起步:`pack.json`(`moods` 只写 `["idle"]`)+ `portrait.png` + `anim/idle/` 几帧。
