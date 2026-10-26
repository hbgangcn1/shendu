# 蜃都 Shendu

卡牌构建 Roguelike 游戏，都市修仙题材，以五行相生相克为核心战斗机制。Godot 4.7 + GDScript，当前处于 MVP 开发阶段。

## 玩法核心

回合制战斗：每回合抽牌、获得能量、出牌，敌方按意图行动。

五行系统见 `scripts/core/wuxing_manager.gd`：

- 五行：金、木、水、火、土
- 相生：金生水、水生木、木生火、火生土、土生金。连续打出相生元素触发伤害加成
- 相克：金克木、木克土、土克水、水克火、火克金。克制伤害加倍，被克伤害减半

## 运行

需要 Godot 4.7 或更高版本。

1. 用 Godot 打开本目录下的 `project.godot`
2. 按 F5 运行，主场景为 `scenes/main.tscn`

## 测试

```bash
godot --headless --scene res://scenes/test_runner.tscn --quit
```

测试用例位于 `scripts/test/`，由 `scripts/test_runner.gd` 汇总执行。仓库的 GitHub Actions 会跑 gdtoolkit 静态检查、headless 单元测试和 Windows 导出。

## 目录结构

| 路径 | 内容 |
|---|---|
| `assets/` | 美术资源，清单与来源见 `design/ART_ASSETS.md` |
| `data/cards/` | 卡牌数据，MVP 17 张、筑基 15 张、金丹 13 张 |
| `scenes/` | 14 个场景，含主菜单、战斗、地图、商店、结算 |
| `scripts/` | 核心系统、战斗逻辑、UI 组件与测试用例 |
| `tools/` | 内容流水线与校验脚本 |
| `docs/` `design/` | 设计规范、美术圣经、任务契约等文档 |
| `project.md` | 完整的项目文档 |
| `AGENTS.md` | 开发规范 |

## 架构

全局单例以 Autoload 注册：`UITheme`、`NodeTooltip`、`GameState`、`WuXing`、`CardPool`、`EventBus`。

战斗层由 `scripts/battle/battle_manager.gd` 驱动状态机，`player.gd` 与 `enemy.gd` 继承自 `actor.gd`。UI 层通过 `EventBus` 与战斗层解耦。

## 许可

MIT，见 [LICENSE](./LICENSE)。
