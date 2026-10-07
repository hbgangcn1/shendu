## 连通性验证

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name ConnectivityValidator
extends RefCounted

static func validate(columns: Array, _boss_col: int) -> Dictionary:
	var result := {"is_valid": true, "errors": []}

	# 检查1：每个非Boss节点至少有1条出边
	for col in range(columns.size() - 1):
		for node in columns[col]:
			if node.connections.is_empty():
				result.is_valid = false
				result.errors.append("节点 %s 无出边" % node.id)

	# 检查2：每个非首列节点至少有1条入边
	for col in range(1, columns.size()):
		for node in columns[col]:
			var has_incoming := false
			for prev_col in range(col):
				for prev_node in columns[prev_col]:
					if node in prev_node.connections:
						has_incoming = true
						break
				if has_incoming:
					break
			if not has_incoming:
				result.is_valid = false
				result.errors.append("节点 %s 无入边" % node.id)

	# 检查3：所有节点可达Boss
	if columns[_boss_col].size() > 0:
		var boss: MapNode = columns[_boss_col][0]
		var reachable := _find_reachable_from_start(columns)
		if not reachable.has(boss.id):
			result.is_valid = false
			result.errors.append("Boss不可达")

	return result

static func _find_reachable_from_start(columns: Array) -> Dictionary:
	var reachable: Dictionary = {}
	if columns.is_empty() or columns[0].is_empty():
		return reachable

	var queue: Array = columns[0].duplicate()
	for node in queue:
		reachable[node.id] = true

	while not queue.is_empty():
		var current: MapNode = queue.pop_front()
		for next_node in current.connections:
			if not reachable.has(next_node.id):
				reachable[next_node.id] = true
				queue.append(next_node)

	return reachable

static func auto_fix(columns: Array, _boss_col: int) -> void:
	# 自动修复：给无出边的节点添加到下一列第一个节点的连接
	for col in range(columns.size() - 1):
		for node in columns[col]:
			if node.connections.is_empty() and columns[col + 1].size() > 0:
				node.add_connection(columns[col + 1][0])

	# 自动修复：给无入边的节点添加从前一列最后一个节点的连接
	for col in range(1, columns.size()):
		for node in columns[col]:
			var has_incoming := false
			for prev_col in range(col):
				for prev_node in columns[prev_col]:
					if node in prev_node.connections:
						has_incoming = true
						break
			if not has_incoming and columns[col - 1].size() > 0:
				columns[col - 1][-1].add_connection(node)

	print("MapGenerator: 自动修复完成")
