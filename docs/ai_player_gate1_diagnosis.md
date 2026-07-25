# AI Player gate_1 FAIL 诊断（2026-07-25 P1-2）

> **背景**：借鉴磊哥 Cocos skill v1 后的硬门禁 #1（核心循环可玩通）当前 FAIL。
> **症状**：AI Player 跑了 16 个 session 累计 824s，**0 战斗胜利 / 0 失败 / 0 完整 run**。
> **本文档**：诊断 + 候选修复方案 + 决策依据。

---

## 1. 症状描述

**profile.json 数字**（不可粉饰）：
```json
{
  "sessions_count": 16,
  "total_playtime_sec": 824,
  "battles_won": 0,
  "battles_lost": 0,
  "runs_completed": 0,
  "lessons": [],
  "strategies": []
}
```

**典型 session 行为**（取自 `memory/ai_player_sessions/20260725_100950.jsonl`）：
```
tick 1 (ts=163s):  click_640_640   → 截图显示 character_select，未推进
tick 2 (ts=656s):  click_960_1824  → y=1824 超出 viewport（1280x720），无效
tick 3 (ts=1054s): end_turn        → VLM 超时，fallback
tick 4 (ts=1654s): end_turn        → VLM 超时
tick 5 (ts=1714s): wait
tick 6 (ts=1870s): click_640_685   → gap 区，未命中
tick 7 (ts=2192s): end_turn
tick 8 (ts=2793s): end_turn        → VLM 超时
tick 9 (ts=3394s): end_turn        → VLM 超时
```
全程卡在 character_select，永远到不了 map → battle。

---

## 2. 根因（State Desync + Click Misfire 双因素）

### 2.1 Click 命中率低

LLM 返回的 click 坐标经常落在无效区域：

| tick | action | 落点 | viewport (1280x720) 内？ | 命中区域 |
|---|---|---|---|---|
| 1 | click_640_640 | 屏幕中心 | ✓ | **gap 区**（ChenmoCard 190-610 / SuwanCard 670-1090 / 中间 60px gap）|
| 2 | click_960_1824 | 右下角 | ✗（y 超界）| 无效 |
| 6 | click_640_685 | 屏幕中心偏下 | ✓ | 仍 gap 区 |

LLM 缺乏对 character_select 布局的精确知识，**盲目点击屏幕中心或随机坐标**。

### 2.2 State Desync

`scripts/agent_inspector.gd._write_state()`：
- 每 500ms 写 `.agent_state.json`
- `_write_battle_state()` 仅在 `current.name in ["BattleScene", "BattleDemo"]` 时触发
- 所以 character_select 阶段 state.json **没有 battle_turn / enemy.hp 等字段**

但 AI Player 读 state.json 时看到 `"scene": "res://scenes/battle_demo.tscn"`：
- 原因：`scene_file_path` 来自上一次战斗（残留 state.json）
- 或：`change_scene_to_file` 已经执行但 BattleManager 还没销毁
- AI Player 的 thought 里出现 "state=battle but screen=角色选择" 反复确认

**这是 shendu-debug skill 应该处理的 7 类失败模式之一**（state-resource desync）。

### 2.3 Auto-select Timer 被反复重置

`scripts/character_select.gd._on_card_gui_input`：
```gdscript
func _on_card_gui_input(event: InputEvent, index: int) -> void:
    if event is InputEventMouseButton:
        ...
        if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
            auto_select_timer.stop()    # ← 每次点击都重置 timer
            ...
            auto_select_timer.start()    # ← 然后重启
```

**问题**：每次 AI Player 错误点击（命中 gap 区），auto_select_timer 被 stop + start。10 秒倒计时永远不会走完。

---

## 3. 候选修复方案

### 方案 A：缩短 Auto-Select Timer（最小改动）

**改动**：`scripts/character_select.gd` 第 43 行
```gdscript
auto_select_timer.wait_time = 10.0  # ← 改为 2.0
```

**优点**：
- 1 行改动
- 即使 click miss，2 秒后 auto-confirm 也能推进

**缺点**：
- 真玩家也可能误触自动确认
- 没解决 click miss 本身

**评估**：作为 quick win，**推荐 P1-2 立即实施**。

---

### 方案 B：增加 Click-Anywhere 确认（全屏命中区）

**改动**：`scripts/character_select.gd._ready()`
```gdscript
# 在 VBox 之上一层加全屏透明 Button 作为"确认"快捷入口
var quick_confirm := Button.new()
quick_confirm.name = "QuickConfirm"
quick_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
quick_confirm.modulate = Color(1, 1, 1, 0)   # 完全透明
quick_confirm.focus_mode = Control.FOCUS_NONE
quick_confirm.pressed.connect(_confirm_selection)
add_child(quick_confirm)
quick_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
# 确保 quick_confirm 在 Background/VBox 之上但 confirm_button 之下
```

**优点**：
- AI Player 任意位置点击都能确认
- 解决 click miss 根本问题
- 不影响真玩家（按钮透明，行为不变）

**缺点**：
- 改了 UI 结构
- 测试需要重跑 character_select 流程

**评估**：作为结构性修复，**推荐 P1-3 实施**。

---

### 方案 C：改进 ai_player_client.py 坐标提取

**改动**：在 AI Player decision 加"scene 坐标映射表"
```python
SCENE_CLICK_TARGETS = {
    "res://scenes/character_select.tscn": [
        {"label": "陈默 card", "x": 400, "y": 400, "viewport": (1280, 720)},
        {"label": "苏晚 card", "x": 880, "y": 400, "viewport": (1280, 720)},
        {"label": "确认选择", "x": 640, "y": 760, "viewport": (1280, 720)},
    ],
    "res://scenes/main_menu.tscn": [
        {"label": "开始游戏", "x": 640, "y": 500, "viewport": (1280, 720)},
    ],
    # ... 更多场景
}
```

**优点**：
- LLM 直接选"目标名"而非猜坐标
- 避免 coord extraction 噪声

**缺点**：
- 维护成本高（每加一个场景都要更新映射表）
- 抽象泄露场景布局

**评估**：作为长期方案，**P2 实施**。

---

### 方案 D：state desync 修复（独立 bug）

**改动**：`scripts/agent_inspector.gd._write_state()`
- 在 `change_scene_to_file` 后立即清空 `.agent_state.json` 的 battle 字段
- 或在 BattleManager._exit_tree() 钩子触发 state 清理

**评估**：必须做，但**与 gate_1 修复独立**，可单独 workboard 卡。

---

## 4. 推荐实施序列

| 顺序 | 方案 | 工作量 | 期望效果 |
|---|---|---|---|
| 1 | A（缩短 timer） | 1 行 .gd | quick win，AI Player 2s 自动推进 |
| 2 | B（click-anywhere） | ~30 行 .gd | 结构性解决 click miss |
| 3 | 跑 AI Player baseline 验证 | 10 分钟 | gate_1 FAIL → PASS |
| 4 | D（state desync）独立卡 | ~20 行 .gd | 防止 state 残留污染 |

**预期**：方案 A + B 后，AI Player 应该能在 30 秒内推进到 map → battle，触发完整战斗循环。

---

## 5. 实施记录

| 日期 | 实施 | 结果 |
|---|---|---|
| 2026-07-25 | 诊断 + 文档（本文件） | DONE |
| _TODO_ | 方案 A | _PENDING_ |
| _TODO_ | 方案 B | _PENDING_ |
| _TODO_ | 验证 | _PENDING_ |

---

## 6. 附录：相关文件清单

- `scripts/character_select.gd` — 角色选择场景脚本（含 _on_card_gui_input / _confirm_selection）
- `scenes/character_select.tscn` — 角色选择场景结构
- `scripts/agent_inspector.gd` — 写 .agent_state.json 的 autoload
- `scripts/agent_socket.gd` — 读 .agent_input.json 执行 click 的 autoload
- `memory/ai_player_sessions/profile.json` — 当前 baseline（16 sessions / 0 battles）
- `memory/ai_player_sessions/20260725_100950.jsonl` — 典型 stuck session 行为日志

---

## 7. 决策点（Robert 拍板）

- [ ] **同意方案 A**（quick win）？预计 5 分钟实施，10 分钟验证
- [ ] **同意方案 B**（结构性）？预计 30 分钟实施 + 10 分钟验证
- [ ] **同意方案 D**（state desync）独立卡？预计 30 分钟
- [ ] **要 spawn maker session 实施**？预计 30+ 分钟，依赖 minimax token 额度
- [ ] **先暂停 P1-2，先做 P1-3**（sessions_spawn role 调研）？

---

**执行人**：Trace（诊断 + 文档）
**下一步**：等 Robert 决策 → 实施 / spawn maker / 调整优先级