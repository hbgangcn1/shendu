## 事件结果

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name EventOutcome
extends RefCounted

const EventEnums: GDScript = preload("res://scripts/core/event_enums.gd")

var resource_type  # EventEnums.ResourceType
var value: int
var direction  # EventEnums.OutcomeDirection
var extra: Dictionary

func apply(player_state: Dictionary) -> void:
	match resource_type:
		EventEnums.ResourceType.HP:
			if direction == EventEnums.OutcomeDirection.GAIN:
				player_state["hp"] = mini(player_state.get("max_hp", 80), player_state.get("hp", 80) + value)
			else:
				player_state["hp"] = maxi(0, player_state.get("hp", 80) - value)
		EventEnums.ResourceType.SPIRIT_STONES:
			if direction == EventEnums.OutcomeDirection.GAIN:
				player_state["spirit_stones"] = player_state.get("spirit_stones", 0) + value
			else:
				player_state["spirit_stones"] = maxi(0, player_state.get("spirit_stones", 0) - value)
		EventEnums.ResourceType.DAO_XING:
			if direction == EventEnums.OutcomeDirection.GAIN:
				player_state["dao_xing"] = player_state.get("dao_xing", 0) + value
		EventEnums.ResourceType.MO_NIAN:
			if direction == EventEnums.OutcomeDirection.GAIN:
				player_state["mo_nian"] = player_state.get("mo_nian", 0) + value
			else:
				player_state["mo_nian"] = maxi(0, player_state.get("mo_nian", 0) - value)
