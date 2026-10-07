## 地图节点

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name MapNode
extends RefCounted

enum NodeType { COMBAT, ELITE, EVENT, SHOP, REST, BOSS, SECRET_ROOM }

const NODE_TYPE_NAMES := {
	NodeType.COMBAT: "战斗",
	NodeType.ELITE: "精英",
	NodeType.EVENT: "事件",
	NodeType.SHOP: "商店",
	NodeType.REST: "休息",
	NodeType.BOSS: "Boss",
	NodeType.SECRET_ROOM: "秘境",
}

const NODE_WEIGHTS := {
	NodeType.COMBAT: 50,
	NodeType.ELITE: 10,
	NodeType.EVENT: 15,
	NodeType.SHOP: 10,
	NodeType.REST: 10,
	NodeType.SECRET_ROOM: 5,
}

var id: String
var type: NodeType
var column: int
var layer: int
var x: float = 0.0
var y: float = 0.0
var connections: Array = []
var metadata: Dictionary = {}
var is_visited: bool = false
var is_reachable: bool = false

func _init(p_id: String, p_type: NodeType, p_column: int, p_layer: int) -> void:
	id = p_id
	type = p_type
	column = p_column
	layer = p_layer

func add_connection(target: MapNode) -> void:
	if target not in connections:
		connections.append(target)

func get_connection_count() -> int:
	return connections.size()

func is_terminal() -> bool:
	return type == NodeType.BOSS or connections.is_empty()

func get_type_name() -> String:
	return NODE_TYPE_NAMES.get(type, "未知")
