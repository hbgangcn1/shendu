# 蜃都 — Godot 项目架构文档

> 版本：v1.1 | 日期：2026-05-23
> 引擎：Godot 4.6.3 | 渲染：gl_compatibility

---

## 目录结构

```
shendu/
├── project.godot              ← 项目配置（含 Autoload）
├── GODOT_ARCH.md              ← 本文件
│
├── scenes/                    ← Godot 场景文件 (.tscn)
│   └── main.tscn              ← 主场景入口（含自测）
│
├── scripts/                   ← GDScript 脚本
│   ├── main.gd                ← 主场景脚本（启动自测）
│   ├── core/                  ← 核心系统
│   │   ├── wuxing_manager.gd ← 五行枚举 + 相生相克 + 伤害乘算
│   │   ├── card_data.gd      ← 卡牌数据类（extends Resource）
│   │   ├── card_pool.gd      ← 卡池加载器（JSON → 内存）
│   │   └── event_bus.gd      ← 全局信号总线
│   ├── battle/                ← 战斗系统（待实现）
│   └── ui/                    ← UI 脚本（待实现）
│
├── data/                      ← 数据文件
│   ├── cards/
│   │   └── mvp_cards.json    ← MVP 9 张卡牌
│   └── enemies/               ← 敌人数据（待实现）
│
└── assets/                    ← 资源文件
    ├── fonts/
    └── images/
```

## Autoload 单例

| 名称 | 脚本 | 职责 |
|------|------|------|
| `WuXing` | `scripts/core/wuxing_manager.gd` | 五行枚举、相生相克查询、伤害乘算 |
| `CardPool` | `scripts/core/card_pool.gd` | 加载/管理卡牌数据 |
| `EventBus` | `scripts/core/event_bus.gd` | 全局信号总线 |

## 编码规范

1. **文件命名**：snake_case（如 `wuxing_manager.gd`）
2. **变量命名**：snake_case（如 `current_hp: int`）
3. **常量命名**：UPPER_SNAKE_CASE（如 `const GENERATE := [...]`）
4. **类型标注**：所有变量和函数参数标注类型
5. **注释语言**：中文注释，英文代码
6. **Autoload 脚本**：不使用 `class_name`（与 Autoload 冲突），直接 `extends Node`
7. **数据类**：使用 `extends Resource`，通过 `load("path").new()` 实例化
