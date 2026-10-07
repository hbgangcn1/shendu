## 奖励统一结算逻辑
## 处理战斗奖励领取、卡牌选择、道行结算

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

extends Node

const BattleReward = preload("res://scripts/core/reward_data.gd")

signal reward_completed(reward: BattleReward)
signal card_selected(card_data: Dictionary)
signal breakthrough_completed(choice: int)

## 领取战斗奖励
func claim_reward(reward: BattleReward, player_state: Dictionary, selected_card_index: int = -1) -> void:
	# 灵石
	if reward.spirit_stones > 0:
		player_state["spirit_stones"] = player_state.get("spirit_stones", 0) + reward.spirit_stones
		print("Reward: 灵石 +%d → %d" % [reward.spirit_stones, player_state.get("spirit_stones", 0)])

	# 道行
	if reward.dao_xing > 0:
		player_state["dao_xing"] = player_state.get("dao_xing", 0) + reward.dao_xing
		print("Reward: 道行 +%d → %d" % [reward.dao_xing, player_state.get("dao_xing", 0)])

	# 卡牌选择（三选一）
	if selected_card_index >= 0 and selected_card_index < reward.card_choices.size():
		var card: Dictionary = reward.card_choices[selected_card_index]
		var deck: Array = player_state.get("deck", [])
		deck.append(card)
		player_state["deck"] = deck
		player_state["deck_size"] = deck.size()
		card_selected.emit(card)
		var display_name: String = card.get("name", card.get("card_name", "?"))
		print("Reward: 卡牌「%s」加入卡组" % display_name)

	reward_completed.emit(reward)

## 执行境界突破
func execute_breakthrough(choice, player_state: Dictionary) -> void:
	BattleReward.apply_breakthrough(choice, player_state)
	breakthrough_completed.emit(choice)

## 获取奖励摘要
func get_reward_summary(reward: BattleReward) -> String:
	var parts: Array = []
	if reward.spirit_stones > 0:
		parts.append("灵石+%d" % reward.spirit_stones)
	if reward.dao_xing > 0:
		parts.append("道行+%d" % reward.dao_xing)
	if reward.card_choices.size() > 0:
		parts.append("卡牌三选一")
	return " + ".join(parts) if parts.size() > 0 else "无奖励"
