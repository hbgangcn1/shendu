## 事件系统逻辑
## 处理事件触发、选项执行、效果结算

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name EventLogic
extends Node

const EventEnums = preload("res://scripts/core/event_enums.gd")
const EventDefinitionScript = preload("res://scripts/core/event_definition.gd")
const EventChoiceScript = preload("res://scripts/core/event_choice.gd")
const EventOutcomeScript = preload("res://scripts/core/event_outcome.gd")
const EventPreconditionScript = preload("res://scripts/core/event_precondition.gd")

signal event_triggered(event: EventDefinition)
signal event_choice_made(choice_index: int, event_id: String)
signal event_completed(event_id: String)

var _pools: Dictionary = {}
var _global_pool: Array = []
var _triggered_events: Dictionary = {}
var _rng: RandomNumberGenerator

func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value if seed_value > 0 else randi()

func load_events(events: Array) -> void:
	for event_data in events:
		var event := _parse_event(event_data)
		_register_event(event)

func _parse_event(data: Dictionary) -> EventDefinition:
	var event := EventDefinition.new()
	event.id = data.get("id", "")
	event.name = data.get("name", "")
	event.description = data.get("description", "")
	event.realm_restriction = data.get("realm_restriction", ["*"])
	event.weight = data.get("weight", 10)
	event.is_one_shot = data.get("is_one_shot", true)
	event.flavor_tags = data.get("flavor_tags", [])

	var cat_str: String = data.get("category", "叙事型")
	match cat_str:
		"叙事型": event.category = EventEnums.EventCategory.NARRATIVE
		"资源型": event.category = EventEnums.EventCategory.RESOURCE
		"风险型": event.category = EventEnums.EventCategory.RISK

	for choice_data in data.get("choices", []):
		var choice := EventChoice.new()
		choice.text = choice_data.get("text", "")
		choice.is_hidden = choice_data.get("is_hidden", false)

		for outcome_data in choice_data.get("outcomes", []):
			var outcome := EventOutcome.new()
			var res_type_str: String = outcome_data.get("resource_type", "HP")
			match res_type_str:
				"HP": outcome.resource_type = EventEnums.ResourceType.HP
				"MANA": outcome.resource_type = EventEnums.ResourceType.MANA
				"SPIRIT_STONES": outcome.resource_type = EventEnums.ResourceType.SPIRIT_STONES
				"MO_NIAN": outcome.resource_type = EventEnums.ResourceType.MO_NIAN
				"DAO_XING": outcome.resource_type = EventEnums.ResourceType.DAO_XING
				"RANDOM_CARD": outcome.resource_type = EventEnums.ResourceType.RANDOM_CARD
				_: outcome.resource_type = EventEnums.ResourceType.HP
			outcome.value = outcome_data.get("value", 0)
			var dir_str: String = outcome_data.get("direction", "gain")
			outcome.direction = EventEnums.OutcomeDirection.GAIN if dir_str == "gain" else EventEnums.OutcomeDirection.LOSE
			outcome.extra = outcome_data.get("extra", {})
			choice.outcomes.append(outcome)

		var prec_data: Dictionary = choice_data.get("precondition", {})
		if not prec_data.is_empty():
			var prec := EventPrecondition.new()
			var cond_str: String = prec_data.get("condition_type", "")
			match cond_str:
				"HP_ABOVE": prec.condition_type = EventEnums.PreconditionType.HP_ABOVE
				"HP_BELOW": prec.condition_type = EventEnums.PreconditionType.HP_BELOW
				"SPIRIT_STONES": prec.condition_type = EventEnums.PreconditionType.SPIRIT_STONES
				"MO_NIAN": prec.condition_type = EventEnums.PreconditionType.MO_NIAN
				"DAO_XING": prec.condition_type = EventEnums.PreconditionType.DAO_XING
				"HAS_ELEMENT": prec.condition_type = EventEnums.PreconditionType.HAS_ELEMENT
				_: prec.condition_type = EventEnums.PreconditionType.HP_ABOVE
			prec.parameters = prec_data.get("parameters", {})
			prec.description = prec_data.get("description", "")
			choice.precondition = prec

		event.choices.append(choice)

	return event

func _register_event(event: EventDefinition) -> void:
	if event.realm_restriction.has("*"):
		_global_pool.append(event)
	else:
		for realm in event.realm_restriction:
			if not _pools.has(realm):
				_pools[realm] = []
			_pools[realm].append(event)

func get_candidates(realm_id: String, player_state: Dictionary = {}) -> Array:
	var candidates: Array = []
	if _pools.has(realm_id):
		candidates.append_array(_pools[realm_id])
	candidates.append_array(_global_pool)
	candidates = candidates.filter(func(e): return not _triggered_events.has(e.id))
	candidates = candidates.filter(func(e):
		for cond in e.trigger_conditions:
			if not cond.is_satisfied(player_state):
				return false
		return true
	)
	return candidates

func generate_event(realm_id: String, player_state: Dictionary = {}) -> EventDefinition:
	var candidates := get_candidates(realm_id, player_state)
	if candidates.is_empty():
		return _get_fallback_event()
	var total: int = 0
	for e in candidates:
		total += e.weight
	if total <= 0:
		return candidates[0]
	var roll := randi() % total
	var cumulative := 0
	for event in candidates:
		cumulative += event.weight
		if roll < cumulative:
			_triggered_events[event.id] = true
			event_triggered.emit(event)
			return event
	var first: EventDefinition = candidates[0]
	_triggered_events[first.id] = true
	event_triggered.emit(first)
	return first

func execute_choice(event: EventDefinition, choice_index: int, player_state: Dictionary) -> Dictionary:
	if choice_index < 0 or choice_index >= event.choices.size():
		return {"success": false, "reason": "无效选项"}
	var choice: EventChoice = event.choices[choice_index]
	if choice.precondition and not choice.precondition.is_satisfied(player_state):
		return {"success": false, "reason": "条件不满足: %s" % choice.precondition.description}
	var results: Array = []
	for outcome in choice.outcomes:
		outcome.apply(player_state)
		results.append({
			"type": outcome.resource_type,
			"value": outcome.value,
			"direction": outcome.direction,
		})
	event_choice_made.emit(choice_index, event.id)
	event_completed.emit(event.id)
	return {"success": true, "results": results}

func _get_fallback_event() -> EventDefinition:
	var event := EventDefinition.new()
	event.id = "EVT_FALLBACK"
	event.name = "无事发生"
	event.description = "这一路上平安无事，你继续前行。"
	event.category = EventEnums.EventCategory.NARRATIVE
	event.realm_restriction = ["*"]
	event.choices = []
	return event

func reset_run() -> void:
	_triggered_events.clear()
