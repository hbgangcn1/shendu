## 全局地图

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name GameMap
extends RefCounted

var realms: Array = []          ## RealmMap[]
var current_realm_index: int = 0

func initialize_all_realms(seed_value: int) -> void:
	realms.clear()
	var realm_ids := ["liqi", "zhuji", "jindan"]  # EA 范围
	for i in range(realm_ids.size()):
		var generator := MapGenerator.new(seed_value + i)
		var realm_map := generator.generate(realm_ids[i], i)
		realms.append(realm_map)

func get_current_realm() -> RealmMap:
	if current_realm_index < realms.size():
		return realms[current_realm_index]
	return null

func advance_realm() -> bool:
	if current_realm_index < realms.size() - 1:
		current_realm_index += 1
		return true
	return false

func get_current_realm_id() -> String:
	var realm := get_current_realm()
	return realm.realm_id if realm else ""
