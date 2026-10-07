# 蜃都 (Shendu) - 项目文档

## 项目概述

**名称**：蜃都 (Shendu)
**类型**：卡牌构建 Roguelike（类 Slay the Spire）
**引擎**：Godot 4.6
**主题**：都市修仙 + 五行系统
**当前阶段**：MVP 开发

## 核心玩法

### 游戏循环
```
玩家回合开始
    ↓
抽牌 (5 张) + 重置能量 (3 点)
    ↓
打出卡牌（消耗能量，触发五行效果）
    ↓
触发五行相生链？→ 伤害加成 + 特效
    ↓
结束回合
    ↓
敌人行动（意图系统）
    ↓
回合结束检查
    ↓
胜负判定
```

### 五行系统

**相生链**：金→水→木→火→土→金
- 连续打出相生元素卡牌触发 1.5× 伤害加成

**相克关系**：
- 金克木、木克土、土克水、水克火、火克金
- 克制伤害 ×2，被克伤害 ×0.5

### MVP 内容

**卡牌**：9 张（金木水火土各 1-2 张）
**敌人**：5 种小怪（巷灵、藤蔓尸、水滴妖、灶火精、墙皮怪）

## 技术栈

| 层级 | 技术 |
|------|------|
| 引擎 | Godot 4.6 |
| 语言 | GDScript |
| 数据格式 | JSON（卡牌配置） |
| 测试 | 内置 assert + GUT |
| Linter | gdtoolkit |

## 项目结构

```
shendu/
├── assets/                 # 游戏资源
│   ├── anchors/
│   ├── fonts/
│   └── images/
├── data/                   # 数据配置
│   └── cards/
│       └── mvp_cards.json  # 卡牌数据
├── scenes/                 # 场景文件
│   ├── main_menu.tscn      # 主菜单
│   ├── battle.tscn         # 战斗 UI
│   ├── battle_demo.tscn   # 战斗演示
│   ├── card.tscn           # 卡牌组件
│   └── main.tscn           # 测试入口
├── scripts/                # 代码
│   ├── core/               # 核心系统（Autoload）
│   │   ├── wuxing_manager.gd    # 五行系统
│   │   ├── card_pool.gd         # 卡池管理
│   │   ├── card_data.gd         # 卡牌数据
│   │   └── event_bus.gd         # 事件总线
│   ├── battle/             # 战斗系统
│   │   ├── battle_manager.gd    # 战斗状态机
│   │   ├── battle_state.gd      # 状态枚举
│   │   ├── actor.gd             # 战斗单位基类
│   │   ├── player.gd            # 玩家
│   │   └── enemy.gd             # 敌人 AI
│   ├── ui/                 # UI 组件
│   │   ├── battle_ui.gd         # 战斗界面
│   │   ├── card_ui.gd           # 卡牌组件
│   │   └── feedback_effects.gd  # 视觉反馈
│   ├── main.gd             # 主场景/测试入口
│   ├── main_menu.gd        # 主菜单
│   ├── main_battle.gd      # 战斗演示控制器
│   └── test_battle.gd      # 端到端测试
├── AGENTS.md               # AI 代理开发规范
├── project.godot           # Godot 项目配置
└── export_presets.cfg      # 导出配置
```

## 架构模式

### 三层架构

```
┌─────────────────────────────────────┐
│            Autoload 单例层           │
│  WuXing  │  CardPool  │  EventBus   │
└─────────────────────────────────────┘
                   │
┌─────────────────────────────────────┐
│             战斗系统层              │
│         BattleManager               │
│     ┌─────────┬─────────┐           │
│     │ Player  │ Enemy[] │           │
│     └─────────┴─────────┘           │
└─────────────────────────────────────┘
                   │
┌─────────────────────────────────────┐
│               UI 层                 │
│  BattleUI  │  CardUI  │  Feedback   │
└─────────────────────────────────────┘
```

### 关键设计模式

| 模式 | 应用 | 说明 |
|------|------|------|
| 状态机 | BattleManager | 8 个战斗状态流转 |
| 单例 | Autoload | 全局可访问系统 |
| 继承 | Actor → Player/Enemy | 战斗单位层次 |
| 工厂 | Enemy.create_*() | 5 种小怪创建 |
| 观察者 | EventBus + 信号 | 模块间解耦 |
| 资源 | CardData | 数据与逻辑分离 |

## 运行说明

### 启动游戏
1. 在 Godot 编辑器中打开项目
2. 按 F5 或点击"运行项目"
3. 主菜单场景：`scenes/main_menu.tscn`

### 运行测试
1. 运行 `main.tscn` 场景执行自测
2. 或查看输出日志中的测试结果

### 导出
- 配置：`export_presets.cfg`
- 目标：`build/shendu.exe` (Windows)

## 开发规范

详见 [AGENTS.md](./AGENTS.md)

## 依赖

- Godot 4.6+
- gdtoolkit (开发工具)
- GUT (可选，测试框架)

## 贡献

1. 阅读 [AGENTS.md](./AGENTS.md) 了解规范
2. 创建功能分支
3. 编写测试 → 实现 → 检查
4. 提交 PR

## 版权

© 2026 蜃都开发团队
