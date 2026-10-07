## 单层境界地图

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name RealmMap
extends RefCounted

var realm_id: String            ## "liqi"/"zhuji"/"jindan"
var realm_index: int            ## 0/1/2
var nodes: Array = []           ## MapNode[]
var columns: Array = []         ## Array[Array[MapNode]] — 按列分组
var boss_node: MapNode = null

func _init(p_realm_id: String = "", p_realm_index: int = 0) -> void:
	realm_id = p_realm_id
	realm_index = p_realm_index

func get_start_nodes() -> Array:
	if columns.is_empty():
		return []
	return columns[0]

func get_boss_node() -> MapNode:
	return boss_node

func get_node_by_id(node_id: String) -> MapNode:
	for node in nodes:
		if node.id == node_id:
			return node
	return null

func get_reachable_nodes(from: MapNode) -> Array:
	return from.connections
