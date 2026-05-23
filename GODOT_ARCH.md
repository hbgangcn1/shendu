# 蜃都 — Godot 项目架构文档

> 版本：v1.0 | 日期：2026-05-23
> 引擎：Godot 4.6.3 | 渲染：gl_compatibility

---

## 目录结构

```
shendu/
├── project.godot              ← 项目配置
├── GODOT_ARCH.md              ← 本文件
│
├── scenes/                    ← Godot 场景文件 (.tscn)
│   ├── main.tscn              ← 主场景入口
│   └── battle/                ← 战斗相关场景
│
├── scripts/                   ← GDScript 脚本
│   ├── core/                  ← 核心系统（五行、卡牌数据、通用工具）
│   │   ├── wuxing_manager.gd ← 五行枚举 + 相生相克 + 伤害乘算
│   │   ├── card_data.gd      ← 卡牌数据资源类
│   │   └── card_pool.gd      ← 卡池加载器
│   ├── battle/                ← 战斗系统
│   │   ├── battle_state_machine.gd  ← 战斗状态机
│   │   ├── actor.gd          ← Actor 基类（HP、护盾）
│   │   ├── player.gd         ← Player（手牌、牌堆、能量）
│   │   ├── enemy.gd          ← Enemy（意图队列）
│   │   ├── enemy_ai.gd       ← 敌人 AI
│   │   └── card_resolver.gd  ← 卡牌打出 + 伤害结算
│   └── ui/                    ← UI 脚本
│       ├── hand_display.gd   ← 手牌显示与交互
│       └── battle_hud.gd     ← 战斗 HUD（HP、能量、意图）
│
├── data/                      ← 数据文件
│   ├── cards/                 ← 卡牌 JSON 数据
│   │   └── mvp_cards.json    ← MVP 9 张卡牌
│   └── enemies/               ← 敌人数据
│       └── mvp_enemies.json  ← MVP 小怪数据
│
└── assets/                    ← 资源文件
    ├── fonts/                 ← 字体
    └── images/                ← 图片（MVP 用色块占位）
```

## 核心架构决策

### 1. Autoload 单例

| 名称 | 脚本 | 职责 |
|------|------|------|
| `WuXing` | `scripts/core/wuxing_manager.gd` | 五行枚举、相生相克查询、伤害乘算 |
| `CardPool` | `scripts/core/card_pool.gd` | 加载/管理卡牌数据 |
| `EventBus` | `scripts/core/event_bus.gd` | 全局信号总线（解耦模块间通信） |

### 2. 信号总线模式（EventBus）

模块间不直接引用，通过 EventBus 广播信号：

```gdscript
# EventBus.gd 定义的信号
signal card_played(card: CardData)
signal damage_dealt(amount: int, element: int, target: Node)
signal generation_triggered(chain: Array[int])  # 相生链触发
signal turn_started(turn_number: int)
signal turn_ended()
signal battle_won()
signal battle_lost()
```

### 3. 五行系统（查表法）

```gdscript
# 相生表：GENERATE[from] = to
# 木(0)→火(1)→土(2)→金(3)→水(4)→木(0)
const GENERATE := [1, 2, 3, 4, 0]

# 相克表：COUNTER[attacker] = defender（被克制的元素）
# 木克土、土克水、水克火、火克金、金克木
const COUNTER := [2, 3, 4, 0, 1]

# 伤害倍率
const COUNTER_MULTIPLIER := 2.0    # 克制 ×2
const COUNTERED_MULTIPLIER := 0.5  # 被克 ×0.5
const GENERATION_BONUS := 1.5      # 相生 +50%
```

### 4. 战斗状态机

```
PLAYER_TURN_START
    ↓
PLAYER_ACTION（选牌/打出/蓄势/结束回合）
    ↓ (循环直到结束回合)
RESOLVE_ROUND
    ↓
ENEMY_TURN
    ↓
ROUND_END（检查枯竭/互斥层/胜负）
    ↓
PLAYER_TURN_START（下一回合）
```

### 5. AI 辅助开发 Prompt 模板

当使用 Codex/Copilot 生成代码时，使用以下前缀：

```
你正在为《蜃都》Godot 4.6.3 项目编写 GDScript。
项目使用：
- Godot 4.x GDScript 语法（不是 3.x）
- Autoload 单例模式（WuXing、CardPool、EventBus）
- 信号总线解耦（不要直接 get_node 引用其他模块）
- 查表法处理五行相生相克（见 wuxing_manager.gd）
- 类型化变量（var x: int = 0，不是 var x = 0）
- 所有脚本继承自 Node 或其子类
```

---

## 编码规范

1. **文件命名**：snake_case（如 `wuxing_manager.gd`）
2. **类名命名**：PascalCase（如 `class_name WuXingManager`）
3. **变量命名**：snake_case（如 `current_hp: int`）
4. **常量命名**：UPPER_SNAKE_CASE（如 `const GENERATE := [...]`）
5. **信号命名**：snake_case（如 `signal card_played`）
6. **类型标注**：所有变量和函数参数必须标注类型
7. **注释语言**：中文注释，英文代码
