## 事件选项

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name EventChoice
extends RefCounted

var text: String
var outcomes: Array = []             ## EventOutcome[]
var precondition: EventPrecondition  ## 前置条件（可选）
var is_hidden: bool = false

func get_available_outcomes() -> Array:
	return outcomes
