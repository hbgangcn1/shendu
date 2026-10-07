## 事件前置条件

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name EventPrecondition
extends RefCounted

const EventEnums: GDScript = preload("res://scripts/core/event_enums.gd")

var condition_type  # EventEnums.PreconditionType
var parameters: Dictionary
var description: String

func is_satisfied(player_state: Dictionary) -> bool:
	match condition_type:
		EventEnums.PreconditionType.HP_ABOVE:
			return player_state.get("hp", 80) >= parameters.get("value", 0)
		EventEnums.PreconditionType.HP_BELOW:
			return player_state.get("hp", 80) <= parameters.get("value", 0)
		EventEnums.PreconditionType.SPIRIT_STONES:
			return player_state.get("spirit_stones", 0) >= parameters.get("value", 0)
		EventEnums.PreconditionType.MO_NIAN:
			return player_state.get("mo_nian", 0) >= parameters.get("value", 0)
		EventEnums.PreconditionType.DAO_XING:
			return player_state.get("dao_xing", 0) >= parameters.get("value", 0)
		EventEnums.PreconditionType.HAS_ELEMENT:
			var count: int = 0
			for card in player_state.get("deck", []):
				if card.get("element", "") == parameters.get("element", ""):
					count += 1
			return count >= parameters.get("count", 1)
		EventEnums.PreconditionType.REALM_INDEX:
			return player_state.get("realm_index", 0) >= parameters.get("value", 0)
		EventEnums.PreconditionType.CARD_COUNT:
			return player_state.get("deck", []).size() >= parameters.get("value", 0)
	return true
