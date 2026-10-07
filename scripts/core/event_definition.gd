## 事件定义

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name EventDefinition
extends RefCounted

const EventEnums: GDScript = preload("res://scripts/core/event_enums.gd")

var id: String
var name: String
var description: String
var realm_restriction: Array = []
var category  # EventEnums.EventCategory
var choices: Array = []              ## EventChoice[]
var weight: int = 10
var trigger_conditions: Array = []
var is_one_shot: bool = true
var flavor_tags: Array = []

func get_choice_text(choice_index: int) -> String:
	if choice_index >= 0 and choice_index < choices.size():
		return choices[choice_index].text
	return ""
