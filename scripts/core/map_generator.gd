## 地图生成器

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name MapGenerator
extends RefCounted

var _rng: RandomNumberGenerator
var _seed: int

const COLUMNS: int = 5          ## 5列（0-4）
const MIN_NODES_PER_COL: int = 2
const MAX_NODES_PER_COL: int = 4

## 战斗地点名池（按境界 × 列）
## 列：0=起点 / 1-3=中段 / 4=Boss
const LOCATION_NAMES := {
	0: [  ## 炼气期
		"城中村·公寓楼道",
		"张记面后巷",
		"济民大药房仓库",
		"隆棋牌室",
		"通天河地下道",
	],
	1: [  ## 筑基期
		"牛大碗地窖",
		"利民快递分拣中心",
		"老刘烧烤天台",
		"废弃印刷厂",
		"城中村牌坊下",
	],
	2: [  ## 金丹期
		"蜃都灵脉交汇点",
		"霓虹灯塔顶层",
		"都市废墟最深处",
		"人间烟火的尽头",
		"幻境与现实的裂缝",
	],
}

func _init(p_seed: int) -> void:
	_seed = p_seed
	_rng = RandomNumberGenerator.new()
	_rng.seed = _seed

func generate(realm_id: String, realm_index: int) -> RealmMap:
	var realm_map := RealmMap.new(realm_id, realm_index)

	# 1. 确定每列节点数
	var column_sizes := _determine_column_sizes()

	# 2. 生成节点
	var columns: Array = []  # Array[Array[MapNode]]
	var realm_locations: Array = LOCATION_NAMES.get(realm_index, LOCATION_NAMES[0])
	for col in range(COLUMNS):
		var col_nodes: Array = []
		for i in range(column_sizes[col]):
			var node_type := _roll_node_type(col)
			var node_id := "R%d_L%d_N%d" % [realm_index, col, i]
			var node := MapNode.new(node_id, node_type, col, i)
			# 设置战斗地点名（按列共享）
			var loc_idx: int = mini(col, realm_locations.size() - 1)
			node.metadata["location_name"] = realm_locations[loc_idx]
			col_nodes.append(node)
			realm_map.nodes.append(node)
		columns.append(col_nodes)

	realm_map.columns = columns

	# 3. 生成连接
	_generate_connections(columns)

	# 4. 设置 Boss 节点
	if columns[COLUMNS - 1].size() > 0:
		realm_map.boss_node = columns[COLUMNS - 1][0]
		realm_map.boss_node.type = MapNode.NodeType.BOSS

	# 5. 连通性验证
	var validation := ConnectivityValidator.validate(columns, COLUMNS - 1)
	if not validation.is_valid:
		print("MapGenerator: 连通性验证失败，自动修复")
		ConnectivityValidator.auto_fix(columns, COLUMNS - 1)

	return realm_map

func _determine_column_sizes() -> Array:
	var sizes: Array = []
	for col in range(COLUMNS):
		if col == 0:
			sizes.append(_rng.randi_range(2, 3))  # 第1列：2-3个
		elif col == COLUMNS - 1:
			sizes.append(1)  # 最后列：1个（Boss）
		else:
			sizes.append(_rng.randi_range(MIN_NODES_PER_COL, MAX_NODES_PER_COL))
	return sizes

func _roll_node_type(column: int) -> MapNode.NodeType:
	if column == 0:
		return MapNode.NodeType.COMBAT if _rng.randf() < 0.7 else MapNode.NodeType.EVENT

	if column == COLUMNS - 1:
		return MapNode.NodeType.COMBAT

	var total: int = 0
	for w in MapNode.NODE_WEIGHTS.values():
		total += w

	var roll := _rng.randi() % total
	var cumulative := 0
	for node_type in MapNode.NODE_WEIGHTS:
		cumulative += MapNode.NODE_WEIGHTS[node_type]
		if roll < cumulative:
			return node_type

	return MapNode.NodeType.COMBAT

func _generate_connections(columns: Array) -> void:
	for col in range(COLUMNS - 1):
		var from_col: Array = columns[col]
		var to_col: Array = columns[col + 1]
		_generate_bipartite_connections(from_col, to_col)

func _generate_bipartite_connections(from_col: Array, to_col: Array) -> void:
	# Phase 1: 保证每个 from 节点至少有1条出边
	var uncovered_to := to_col.duplicate()
	for node in from_col:
		if node.connections.is_empty():
			var target_idx := _rng.randi_range(0, to_col.size() - 1)
			var target: MapNode = to_col[target_idx]
			node.add_connection(target)
			uncovered_to.erase(target)

	# Phase 2: 保证每个 to 节点至少有1条入边
	for node in to_col:
		var has_incoming := false
		for from_node in from_col:
			if node in from_node.connections:
				has_incoming = true
				break
		if not has_incoming:
			var source_idx := _rng.randi_range(0, from_col.size() - 1)
			from_col[source_idx].add_connection(node)

	# Phase 3: 额外分支（随机1-2条）
	for node in from_col:
		if _rng.randf() < 0.4 and node.connections.size() < 2:
			var target_idx := _rng.randi_range(0, to_col.size() - 1)
			var target: MapNode = to_col[target_idx]
			if target not in node.connections:
				node.add_connection(target)
