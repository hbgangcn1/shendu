# 蜃都 Art Bible v1（2026-07-25）

> **来源**：借鉴磊哥 Cocos Creator × AI skill v1（2026-07-25）的「Art Bible 先行」原则，反推蜃都现有 60+ 资产沉淀而成。
> **作者**：Trace（自动反推）+ Robert 终审
> **强制级别**：所有 shendu-art / shendu-art-design / image_generate 调用必须 cite 本文件章节

---

## 1. 设定基调（Setting Tone）

**一句话**：**「都市夜雨 + 五行修真」的赛博东方**（cyberpunk oriental × wuxing cultivation）。

- 时代背景：现代都市（程序猿、外卖骑手、夜市老板），但灵气复苏
- 视觉张力：霓虹灯 × 水墨晕染 / 玻璃幕墙 × 篆体符箓 / 雨夜街景 × 五行真言
- 故事气质：每个 Boss 都是某个行业 + 五行属性的化身（如地脉真君 = 土 × 房地产；外卖骑手苏晚 = 木 × 城市流动）

**禁止项（Prohibitions）**：
- ❌ 纯古风（无现代元素）
- ❌ 纯赛博朋克（无东方修真符号）
- ❌ 萌系 / Q版 / 表情包风格
- ❌ 西方奇幻（剑与魔法、龙与地下城）
- ❌ 校园日常 / 恋爱题材
- ❌ 任何 emoji 出现在候选交付
- ❌ 占位符：纯色方块、默认 UI、来源不明网图

---

## 2. 色板（Palette）

### 2.1 五行主色（必用五行 ≠ 默认白）

| 行 | 主色 HEX | 辅色 HEX | 命中元素 | 视觉联想 |
|---|----------|----------|----------|----------|
| **金 Metal** | `#C9A86A` 暖金 | `#E8D9A8` 浅金 + `#7A5F2E` 古铜 | 西/收获 | 古币、剑、钢铁、神像 |
| **木 Wood** | `#3F7A3F` 青苔绿 | `#7FB069` 嫩绿 + `#1F3D1F` 深林 | 东/生长 | 藤蔓、丹药、骑手、生命 |
| **水 Water** | `#1B3A5C` 玄青 | `#2E5C8A` 海蓝 + `#B8DCEB` 霜白 | 北/潜藏 | 雨、夜市、外卖、龙 |
| **火 Fire** | `#B22222` 朱砂 | `#E25822` 焰橙 + `#FFB347` 琥珀 | 南/光明 | 厨火、霓虹、丹药、程序员 |
| **土 Earth** | `#8B6F47` 黄土 | `#C19A6B` 沙黄 + `#5C4326` 深棕 | 中/承载 | 楼宇、岩石、地脉、Boss |

> **不混用规则**：每个角色/敌人/Boss/UI 元素只对应 1 个五行主色。混色 = 修真走火入魔视觉暗示（仅限剧情"堕落"角色）。

### 2.2 UI 基础色

| 用途 | HEX | 备注 |
|------|-----|------|
| 背景主色 | `#0E0B08` 墨黑 | 一切 UI panel 默认底色 |
| 文字主色 | `#E8E0D0` 暖白 | 主标题、卡牌名 |
| 文字副色 | `#A89888` 哑金 | 描述、数值、Tooltip |
| 警示色 | `#C53030` 血红 | 伤害、低 HP、debuff |
| 治愈色 | `#2F855A` 翠绿 | 治疗、护盾 |
| 灵气色 | `#4FD1C5` 青蓝霓虹 | 主动技能、能量条 |
| 高亮色 | `#FFD700` 真金 | 稀有卡牌、关键提示 |

### 2.3 反推依据

- `ui_icon_{earth,fire,metal,water,wood}_001.png` — 五行图标主色确认
- `boss_earth_true_lord_001` (review_score 92) — 土系 Boss 标杆色
- `enemy_{earth_rock_guardian,fire_flame_demon,metal_iron_golem,water_frost_assassin,wood_vine_spirit}_001` — 5 个普通敌人五行配色基线

---

## 3. 字体（Typography）

| 用途 | 字体 | 字号 / 风格 | 备注 |
|------|------|-------------|------|
| 主标题（场景名 / Boss 名） | 思源宋体 Heavy | 32-48pt | 修真感、传统宋韵 |
| 副标题（章节名 / 卡牌名） | 思源宋体 SemiBold | 20-28pt | — |
| 正文 / 描述 / Tooltip | 思源黑体 Regular | 14-18pt | 现代感、可读性优先 |
| 数值（HP / 伤害 / 费用） | 思源宋体 Heavy | 16-24pt | 必须带 `text-shadow: 0 0 4px #C53030`（伤害）/ `#2F855A`（治疗）|
| 按钮文字 | 思源黑体 Medium | 14-18pt | 全大写英文 / 中文正常 |
| 系统提示（debug / dev） | JetBrains Mono | 12-14pt | 程序员专属彩蛋 |

**禁止**：
- ❌ 系统默认字体（系统字体拼凑 = 磊哥红线 #2）
- ❌ 花哨书法体（难读）
- ❌ emoji 充当文字

**反推依据**：项目 AGENTS.md 明确"卡牌构建 Roguelike + 都市修仙 + 五行系统"——修真感 = 思源宋体，都市感 = 思源黑体。

---

## 4. 角色比例（Character Proportions）

### 4.1 基础比例

- **立绘**：6-7 头身高（写实向英雄比例）
- **卡牌头像**：1:1 方版，肩部以上特写
- **敌人**：5-6 头身高（略矮，更压迫）
- **Boss**：7-8 头身高 + 披风/光环（仪式感）

### 4.2 面部特征（强约束）

- **所有人/类人角色**：亚洲面孔（东亚审美基准），但**不锁死国籍**——主角团是程序员（陈默）、外卖骑手（苏晚）、夜市老板（陈老板）这类都市职业身份
- **眼睛**：写实半大（不是 Q 版巨大眼）
- **皮肤**：自然肤色，不允许"全白瓷娃娃"
- **写实度**：Genshin Impact 写实风 × 真人摄影参考，**不是 3D 重渲染**（避免 3D heavy 风格走偏）

### 4.3 服装混搭（关键风格点）

- **底层**：现代都市服装（连帽衫、工装夹克、外卖制服、衬衫西裤）
- **修真元素叠加**：纹身 / 发光经脉 / 符箓袖口 / 腰间玉佩 / 灵气光环
- **五行属性标识**：
  - 金 → 金属配饰（戒指、项链、护腕）
  - 木 → 植物纹样 / 翠绿光点
  - 水 → 雨滴 / 流水波纹
  - 火 → 火焰纹 / 暖光晕
  - 土 → 岩石 / 黄沙背景元素

### 4.4 描边（Outline）

- **统一规格**：2px 暖暗线 `#2A1F18`（**不是纯黑**——纯黑描边会显得太硬）
- **例外**：高对比度场景（雨夜、霓虹背景）可加 0.5px 内描边 `#E8E0D0` 提亮

**反推依据**：
- `card_char_chenmo_001.png` (review 高分) — 人物卡牌基准
- `npc_shopkeeper_chen.png` — NPC 都市感基准
- `enemy_wood_vine_spirit_001.png` — 自然系敌人基准
- `boss_earth_true_lord_001.png` (review_score 92) — Boss 仪式感基准

---

## 5. 材质 / 光照（Material & Lighting）

### 5.1 材质关键词（写 prompt 时必带）

- **金 Metal**：polished metal / engraved bronze / jade inlay
- **木 Wood**：moss-covered bark / glowing veins / fresh leaf
- **水 Water**：rain-slicked surface / frost crystal / dark tide
- **火 Fire**：ember glow / flickering flame / molten lava
- **土 Earth**：cracked stone / yellow dust / mountain granite

### 5.2 光照规则

- **2-3 光源最少**：key light + rim light + (optional) fill light
- **方向性**：左前 30° 主光，背光勾边（cyber 感），暖色 fill
- **氛围光**：
  - 雨夜场景 → 青色 ambient + 霓虹紫/橙点缀
  - 室内场景 → 暖黄 ambient
  - Boss 战 → 单色强光（按五行）+ 大量体积雾
- **禁止**：纯白高光、扁平无影（3D heavy 路线反过来）

**反推依据**：60+ 资产都是 1-4MB 高质量 PNG，体积允许复杂光影；`bg_battle.png` (1.1MB) 是战斗场景光照标杆。

---

## 6. UI 层级（Z-Index Hierarchy）

| Z 层 | 内容 | 备注 |
|------|------|------|
| 0-100 | 游戏世界：背景、人物、敌人、动画特效 | 永远在最底 |
| 100-200 | 战斗 HUD：HP 条、手牌、能量珠 | 半透明，不遮挡 |
| 200-300 | 卡牌选择 / 战斗结算弹窗 | 半透明黑遮罩 |
| 300-400 | 商店 / 事件 modal | 全屏 |
| 400-500 | 系统：暂停 / 设置 / debug | 顶层 |
| 500+ | 错误 / Loading | 全屏遮罩 |

**反推依据**：项目已用 `z_index` + Control 节点嵌套，符合 Godot 4 CanvasLayer 规范。

---

## 7. 动效节奏（Animation Rhythm）

| 动效 | 时长 | 缓动 |
|------|------|------|
| 卡牌打出 | 0.30s | ease-out + 0.10s 屏震 |
| 伤害数字弹出 | 0.50s | ease-out + 0.20s 角色闪烁 |
| 治疗数字弹出 | 0.50s | ease-out + 0.20s 翠绿光环 |
| 敌人死亡 | 1.20s | fade + collapse + 0.30s 余光 |
| Boss 死亡 | 2.00s | 慢动作 + 大量粒子 + 全屏震动 |
| 场景切换 | 0.40s | linear + 黑屏过渡 |
| 按钮 hover | 0.15s | ease-in-out |
| 按钮 click | 0.10s | ease-out + 0.05s 缩放 |

**节奏原则**：**慢入快出**（修真仪式感）+ **即时反馈**（都市快节奏）—— 两套节奏混合，不允许统一死板。

---

## 8. 命名规范（Naming）

所有资产文件名必须遵循：

```
{asset_type}_{element/subject}_{specific_name}_{NNN}.png
```

- `asset_type`: `card / enemy / boss / npc / bg / ui / icon / element / event`
- `element`: `metal / wood / water / fire / earth / neutral / chenmo / suwan`
- `specific_name`: 英文小写蛇形（`true_lord` / `flame_demon` / `rock_guardian`）
- `NNN`: 3 位序号（`001` / `002` / ...）

**示例**：
- ✅ `boss_earth_true_lord_001.png`（地脉真君）
- ✅ `enemy_fire_flame_demon_001.png`（烈焰魔）
- ✅ `card_char_chenmo_001.png`（陈默卡牌）
- ❌ `IMG_1234.png`（无结构）
- ❌ `最终版本-2-真的.png`（中英混杂）

**反推依据**：现有 60+ 资产已严格遵循此规范。

---

## 9. 元数据必填字段（meta.yaml Required）

```yaml
asset_id: enemy_fire_flame_demon_001       # 必须 = 文件名（去 .png）
asset_type: enemy                          # 见 §8
display_name: 烈焰魔                        # 中文名
element: fire                              # 五行属性
target_size: "1024x1024"                   # 目标分辨率
aspect_ratio: "1:1"                        # 长宽比
usage: 战斗单位、图鉴                        # 用途描述
prompt: |                                   # 生成 prompt（必填）
  ...
implements_philosophy: [rule_1_core_loop_first]  # 哲学映射（必填）
minimax_attempts: 0                        # 生成尝试计数
qwen_attempts: 0
current_model: minimax-portal/image-01     # 当前生成 model
review_status: pending                     # pending / pass / reject
review_score: 0                            # 0-100
review_date: ""                            # ISO date
version: v001                              # v001 / v002 ...
```

**新增必填**（Art Bible v1 起强制）：
```yaml
art_bible_ref:                             # 引用本文档章节
  palette_section: "2.1"
  character_proportion_section: "4.1"
  outline_section: "4.4"
  lighting_section: "5.2"
```

---

## 10. 必测清单（Maker Acceptance）

提交 `review_hermes` 前，maker 自查：

- [ ] 文件名遵循 §8
- [ ] meta.yaml 含 `art_bible_ref`（§9）
- [ ] 颜色严格遵循 §2.1 五行主色（不混色）
- [ ] 描边遵循 §4.4（2px `#2A1F18`）
- [ ] 光照至少 2 光源（§5.2）
- [ ] 无 emoji / 占位 / 默认 UI（§1 禁止项）
- [ ] 长宽比符合 `target_size`（§9）
- [ ] 生成 prompt 含五行材质关键词（§5.1）
- [ ] 输出 PNG ≥ 500KB（高分辨率证据；低质 = 重做）
- [ ] 与同 archetype 的现有资产视觉一致（card 与 card / boss 与 boss / 五行 icon 之间）

**任何一项不过 → 打回 maker 重做**，不进入 checker 阶段。

---

## 11. 一页纸总结（One-Pager）

```
设定：都市夜雨 + 五行修真 = 赛博东方
色板：五行主色必用 + UI 暖白/墨黑/血朱
字体：思源宋体（修真）+ 思源黑体（都市）+ 思源宋体 Heavy（数值）
角色：6-7 头身高 / 亚洲面孔 / 现代服装 + 修真元素 / 2px 暖暗线
光照：2-3 光源 / 霓虹背光 + 暖 fill / 体积雾
动效：慢入快出 + 即时反馈 / 双重节奏混合
元数据：meta.yaml 必填 art_bible_ref
禁忌：emoji / Q版 / 萌系 / 纯古风 / 纯赛博 / 来源不明网图
```

---

## 12. 修订历史

| 版本 | 日期 | 变更 | 作者 |
|------|------|------|------|
| v1 | 2026-07-25 | 初版（借鉴磊哥 skill + 反推现有 60+ 资产） | Trace + Robert 终审 |

---

## 附录 A：参考资产清单（Art Bible v1 沉淀依据）

> 已复制到 `~/.openclaw/workspace/memory/inbox/shendu-art-samples/` 供 AI 反推参考

| 类别 | 文件 | 备注 |
|------|------|------|
| 背景 | `bg_battle.png` | 战斗场景光照标杆 |
| 背景 | `bg_main_menu.png` | 主菜单氛围标杆 |
| 角色卡 | `card_chenmo.png` (= `card_char_chenmo_001.png`) | 人物卡牌基准 |
| NPC | `chen.png` (= `npc_shopkeeper_chen.png`) | 都市 NPC 基准 |
| Boss | `boss_earth.png` (= `boss_earth_true_lord_001.png`) | 土系 Boss 标杆（review_score 92）|
| 敌人 | `enemies/enemy_fire_flame_demon_001.png` | 火系敌人基准 |
| 敌人 | `enemies/enemy_metal_iron_golem_001.png` | 金系敌人基准 |
| 敌人 | `enemies/enemy_water_frost_assassin_001.png` | 水系敌人基准 |
| 敌人 | `enemies/enemy_wood_vine_spirit_001.png` | 木系敌人基准 |
| 敌人 | `enemies/enemy_earth_rock_guardian_001.png` | 土系敌人基准 |
| 敌人 | `enemies/elite_neutral_shifting_puppet_001.png` | 精英敌人基准 |
| 事件 | `events/event_black_market.png` | 黑市场景基准 |
| 事件 | `events/event_medicine_shop.png` | 药铺场景基准 |
| 事件 | `events/event_rooftop_garden.png` | 屋顶花园基准 |
| UI | `rarity_frames.png` | 稀有度框样式 |
| UI | `buttons/btn_sheet.png` | 按钮基准 |
| UI | `buttons/btn_hover_sheet.png` | 按钮 hover 基准 |

**总计 17 个代表性样本，覆盖背景 / 卡牌 / NPC / Boss / 敌人（5 行）/ 精英 / 事件 / UI 全类型。**

---

**执行**：所有未来 asset 生成（image_generate / shendu-art 调用）必须显式 cite 本文件章节到 prompt。
**监督**：`shendu-loop` 的 loop-check.mjs 应扫 meta.yaml 是否含 `art_bible_ref` 字段。