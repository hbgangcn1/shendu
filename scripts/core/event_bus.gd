## 全局信号总线 — 解耦模块间通信
## 作为 Autoload 单例使用
## 所有模块通过 EventBus 发射/监听信号，不直接引用彼此

extends Node

# ==================== 战斗流程信号 ====================

## 回合开始
signal turn_started(turn_number: int)

## 回合结束
signal turn_ended()

## 玩家打出卡牌
signal card_played(card_data, target: Node)

## 伤害结算完成
signal damage_dealt(amount: int, element: int, source: Node, target: Node)

## 五行相生链触发
signal generation_triggered(chain: Array, bonus_multiplier: float)

## 暴击触发（相生链中的 5% 概率）
signal crit_triggered(card_data, final_damage: int)

## 蓄势标记变化
signal charge_stacks_changed(new_stacks: int)

## 魔念层数变化
signal mo_nian_changed(new_amount: int)

# ==================== 战斗结果信号 ====================

## 战斗胜利
signal battle_won()

## 战斗失败
signal battle_lost()

# ==================== UI 信号 ====================

## 手牌选中
signal hand_card_selected(index: int)

## 手牌取消选中
signal hand_card_deselected()

## 回合结束按钮点击
signal end_turn_requested()

## 蓄势按钮点击
signal charge_requested()
