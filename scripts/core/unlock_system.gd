## 解锁系统
## 管理角色/功能解锁、解锁条件检查、解锁通知

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name UnlockSystem
extends Node

signal feature_unlocked(feature_id: String, description: String)

## 解锁状态
var _unlocked: Dictionary = {}  ## { feature_id: true }

## 解锁条件定义
const UNLOCK_CONDITIONS := {
	"character_lumingyuan": {
		"type": "dao_xing",
		"value": 60,
		"description": "累计道行达到60解锁陆明远",
		"category": "character",
	},
	"character_alian": {
		"type": "dao_xing",
		"value": 100,
		"description": "累计道行达到100解锁阿莲",
		"category": "character",
	},
	"character_zhouxiaoman": {
		"type": "dao_xing",
		"value": 200,
		"description": "累计道行达到200解锁周小满",
		"category": "character",
	},
	"engrave_system": {
		"type": "dao_xing",
		"value": 140,
		"description": "累计道行达到140解锁刻印系统",
		"category": "system",
	},
	"difficulty_hard": {
		"type": "dao_xing",
		"value": 300,
		"description": "累计道行达到300解锁困难模式",
		"category": "difficulty",
	},
	"daily_challenge": {
		"type": "dao_xing",
		"value": 500,
		"description": "累计道行达到500解锁每日挑战",
		"category": "mode",
	},
}

## 检查所有解锁条件
func check_unlocks(player_state: Dictionary) -> Array:
	var new_unlocks: Array = []
	var total_dx: int = player_state.get("dao_xing", 0)

	for feature_id in UNLOCK_CONDITIONS:
		if is_unlocked(feature_id):
			continue

		var cond: Dictionary = UNLOCK_CONDITIONS[feature_id]
		var met := false

		match cond["type"]:
			"dao_xing":
				met = total_dx >= cond["value"]
			"realm":
				met = player_state.get("realm", 0) >= cond["value"]

		if met:
			_unlocked[feature_id] = true
			new_unlocks.append(feature_id)
			feature_unlocked.emit(feature_id, cond["description"])
			print("Unlock: %s — %s" % [feature_id, cond["description"]])

	return new_unlocks

## 检查单个功能是否已解锁
func is_unlocked(feature_id: String) -> bool:
	return _unlocked.has(feature_id)

## 获取所有已解锁功能
func get_unlocked() -> Array:
	return _unlocked.keys()

## 获取所有可解锁功能及状态
func get_all_features() -> Array:
	var result: Array = []
	for feature_id in UNLOCK_CONDITIONS:
		var cond: Dictionary = UNLOCK_CONDITIONS[feature_id]
		result.append({
			"id": feature_id,
			"description": cond["description"],
			"category": cond["category"],
			"unlocked": is_unlocked(feature_id),
			"requirement_type": cond["type"],
			"requirement_value": cond["value"],
		})
	return result

## 重置（新游戏时调用）
func reset() -> void:
	_unlocked.clear()

## 保存/加载
func save_data() -> Dictionary:
	return {"unlocked": _unlocked.keys()}

func load_data(data: Dictionary) -> void:
	_unlocked.clear()
	for feature_id in data.get("unlocked", []):
		_unlocked[feature_id] = true
