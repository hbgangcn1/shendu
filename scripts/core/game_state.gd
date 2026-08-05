# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

extends Node

# --- 单局状态（每局重置）---
var player_name: String = ""
var character_id: String = ""        # "chenmo" / "suwan"
var hp: int = 80
var max_hp: int = 80
var spirit_stones: int = 0
var dao_xing: int = 0                # 本局获得的道行
var mo_nian: int = 0                 # 魔念值
var current_realm: int = 0           # 0=炼气, 1=筑基, 2=金丹
var current_node_id: String = ""     # 当前所在地图节点ID
var visited_node_ids: Array = []     # 已访问的节点ID
var game_map = null                  # 当前地图实例 (GameMap)
var is_boss_defeated: Array = []     # 每层Boss是否击败

# --- 卡牌池 + 牌库 ---
var collection: Array = []           # 卡牌池：所有已获得的卡牌，只增不减 (Dictionary[])
var deck: Array = []                 # 牌库：当前出战卡组，存collection索引 (int[])
var deck_max_size: int = 25          # 牌库上限

# --- 洗髓（永久删卡，后续单独实现）---
var deck_removal_count: int = 0      # 已永久删除次数

# --- 跨局状态（存档）---
var total_dao_xing: int = 0          # 累计道行
var first_battle_done: bool = false  # 首战完成标记（用于onboarding）

signal state_changed()

func reset_run() -> void:
	hp = 80
	max_hp = 80
	spirit_stones = 0
	dao_xing = 0
	collection.clear()
	deck.clear()
	current_realm = 0
	current_node_id = ""
	visited_node_ids.clear()
	game_map = null
	is_boss_defeated.clear()
	# 注意：first_battle_done 是跨局存档状态，不在此处重置
	state_changed.emit()

# ==================== 角色数据 ====================

## 角色→初始卡组 ID 列表（10 张，按 design/core-loop/02-card-schema.md §3.1
## 费用分布 1×4 + 2×4 + 3×2 = 16 费 平均 1.60，MVP 池无 0/4 费卡故近似）
## spec §3.1 理想分布 0×2 + 1×3 + 2×2 + 3×2 + 4×1 = 18 费 平均 1.80
## 待补卡池到 45 张后（EA 范围）再升级 0/4 费覆盖
const STARTER_DECK_BY_CHARACTER := {
	"chenmo": [
		"MC-ME-001",  # 金刚斩 攻击·金·2费
		"MC-ME-002",  # 铁壁   防御·金·1费
		"MC-WO-001",  # 藤鞭   攻击·木·1费
		"MC-WO-002",  # 回春术 辅助·木·1费
		"MC-WA-001",  # 水弹   攻击·水·1费
		"MC-WA-002",  # 水幕   防御·水·1费
		"MC-FI-001",  # 烈焰弹 攻击·火·3费
		"MC-FI-002",  # 爆燃   攻击·火·2费 (rare)
		"MC-EA-001",  # 岩盾   防御·土·2费
		"MC-ME-001",  # 金刚斩×2（陈默金系专注）
	],
	"suwan": [
		"MC-FI-001",  # 烈焰弹 攻击·火·3费
		"MC-FI-002",  # 爆燃   攻击·火·2费 (rare)
		"MC-FI-002",  # 爆燃×2（苏晚火系专注）
		"MC-WO-001",  # 藤鞭   攻击·木·1费
		"MC-WO-002",  # 回春术 辅助·木·1费
		"MC-WA-001",  # 水弹   攻击·水·1费
		"MC-ME-001",  # 金刚斩 攻击·金·2费
		"MC-ME-002",  # 铁壁   防御·金·1费
		"MC-EA-001",  # 岩盾   防御·土·2费
		"MC-WA-002",  # 水幕   防御·水·1费
	],
}

func get_character_data() -> Dictionary:
	match character_id:
		"chenmo":
			return {
				"name": "陈默",
				"title": "程序员",
				"description": "我以为那是个bug。",
				"hp": 80,
				"starter_deck": _build_starter_deck("chenmo"),
			}
		"suwan":
			return {
				"name": "苏晚",
				"title": "外卖骑手",
				"description": "跑了三年外卖，这条路我比谁都熟。",
				"hp": 70,
				"starter_deck": _build_starter_deck("suwan"),
			}
	return {}

## 从 MVP 池按 STARTER_DECK_BY_CHARACTER 取卡 → 转为 GameState.collection 用的 Dictionary
## 若 CardPool 还没加载完或某个 ID 缺失，fallback 到空数组（character_select 报错而非崩溃）
func _build_starter_deck(cid: String) -> Array:
	var ids: Array = STARTER_DECK_BY_CHARACTER.get(cid, [])
	if ids.is_empty():
		push_error("GameState: 未知角色 %s，无 starter_deck 定义" % cid)
		return []
	var starter_cards: Array = []
	var missing: Array = []
	for card_id in ids:
		var card = CardPool.get_card(card_id)
		if card == null:
			missing.append(card_id)
			continue
		starter_cards.append(card.to_dict())
	if not missing.is_empty():
		push_warning("GameState: starter_deck 缺少卡牌 %s（CardPool 未加载）" % str(missing))
	print("GameState: 角色 %s 初始卡组 %d 张" % [cid, starter_cards.size()])
	return starter_cards

func get_realm_name() -> String:
	var names := ["炼气期", "筑基期", "金丹期"]
	return names[current_realm] if current_realm < names.size() else "炼气期"

func get_realm_enemy_scale() -> float:
	var scales := [1.0, 1.51, 2.28]
	return scales[current_realm] if current_realm < scales.size() else 1.0

func get_starter_deck() -> Array:
	return get_character_data().get("starter_deck", [])

# ==================== 卡牌池管理 ====================

## 向卡牌池添加一张卡（只增不减）
func add_to_collection(card_data: Dictionary) -> int:
	var index: int = collection.size()
	collection.append(card_data.duplicate())
	var display_name: String = card_data.get("name", card_data.get("card_name", "?"))
	print("GameState: 卡牌「%s」加入卡牌池，当前 %d 张" % [display_name, collection.size()])
	return index

## 从卡牌池获取卡牌数据
func get_collection_card(index: int) -> Dictionary:
	if index < 0 or index >= collection.size():
		return {}
	return collection[index]

# ==================== 牌库管理 ====================

## 牌库是否已满
func is_deck_full() -> bool:
	return deck.size() >= deck_max_size

## 牌库剩余容量
func deck_remaining() -> int:
	return deck_max_size - deck.size()

## 将卡牌池中的卡加入牌库
## collection_index: 卡牌池中的索引
## 返回是否成功
func add_to_deck(collection_index: int) -> bool:
	if collection_index < 0 or collection_index >= collection.size():
		print("GameState: 无效的卡牌池索引 %d" % collection_index)
		return false
	if is_deck_full():
		print("GameState: 牌库已满 (%d/%d)" % [deck.size(), deck_max_size])
		return false
	# 检查同名卡上限（2张）
	var card_id: String = collection[collection_index].get("id", "")
	if count_card_in_deck(card_id) >= 2:
		var dup_name: String = collection[collection_index].get("name", collection[collection_index].get("card_name", "?"))
		print("GameState: 同名卡「%s」已达上限2张" % dup_name)
		return false
	deck.append(collection_index)
	var card_name: String = collection[collection_index].get("name", collection[collection_index].get("card_name", "?"))
	print("GameState:「%s」加入牌库，牌库 %d/%d" % [card_name, deck.size(), deck_max_size])
	return true

## 将卡牌从牌库移回卡牌池
## deck_index: 牌库中的索引
## 返回是否成功
func remove_from_deck(deck_index: int) -> bool:
	if deck_index < 0 or deck_index >= deck.size():
		print("GameState: 无效的牌库索引 %d" % deck_index)
		return false
	var collection_index: int = deck[deck_index]
	var card_name: String = ""
	if collection_index >= 0 and collection_index < collection.size():
		card_name = collection[collection_index].get("name", collection[collection_index].get("card_name", "?"))
	deck.remove_at(deck_index)
	print("GameState:「%s」移回卡牌池，牌库 %d/%d" % [card_name, deck.size(), deck_max_size])
	return true

## 统计牌库中同名卡数量
func count_card_in_deck(card_id: String) -> int:
	var count := 0
	for ci in deck:
		if ci >= 0 and ci < collection.size():
			if collection[ci].get("id", "") == card_id:
				count += 1
	return count

## 获取牌库中所有卡牌数据（供战斗使用）
func get_deck_cards() -> Array:
	var cards: Array = []
	for ci in deck:
		if ci >= 0 and ci < collection.size():
			cards.append(collection[ci])
	return cards

## 获取洗髓费用（后续单独实现）
func get_removal_cost() -> int:
	return 100 * (deck_removal_count + 1)

# ==================== 兼容接口 ====================
# 供现有代码在过渡期内使用，内部转调新接口

## 旧接口：直接向牌库添加卡（兼容模式）
## 新代码应使用 add_to_collection + add_to_deck
func legacy_add_to_deck(card_data: Dictionary) -> void:
	var idx: int = add_to_collection(card_data)
	add_to_deck(idx)

# ==================== 2026-08-05 方案 D：map layout export for AI Player ====================
## 2026-08-03 Robert 提议的“让 minimax 看到结构”路径。
## 背景：AI Player 之前只看屏幕截图 + 内存状态，minimax 不能直接读 .tscn 节点结构。
## 每次进入 map scene 时 export 一份 map layout（节点 ID / 类型 / column / reachable
## / visited / connections）写到 user://ai-player-map-layout.json，phase_e_consume
## 或 ai_player_client.py 读这个文件加到 minimax prompt 上下文。
##
## 优势：
## - minimax 能看到 “当前可选 5 个节点里 3 个是 COMBAT 1 个是 REST 1 个是 SHOP”
##   而不是只看像素。
## - 决策更准：卡节点选择 / 五行相生 / 牌组缺的元素等策略性 decision。
## - Phase E design_concerns 也会更准（"为什么 AI Player 一直选 COMBAT"）被 minimax
##   看到后能 propose “加引导 + 五行图例”。

func export_map_layout_for_ai_player() -> Dictionary:
	var layout: Dictionary = {
		"exported_at": Time.get_datetime_string_from_system(),
		"run_id": _generate_run_id_for_layout() if has_method("_generate_run_id_for_layout") else "",
		"current_realm": current_realm,
		"realm_name": get_realm_name(),
		"current_node_id": current_node_id,
		"visited_node_ids": visited_node_ids.duplicate(),
		"hp": hp,
		"max_hp": max_hp,
		"spirit_stones": spirit_stones,
		"dao_xing": dao_xing,
		"mo_nian": mo_nian,
		"map_available": game_map != null,
		"columns": [],
		"stats": {
			"total_nodes": 0,
			"reachable_count": 0,
			"unvisited_reachable_count": 0,
			"by_type": {},
		},
	}
	if game_map == null:
		return layout

	# 从 game_map.realms[current_realm] 读节点 + 连接 + 可达状态
	if not game_map.has_method("get_realm_map"):
		return layout
	var realm_map = game_map.get_realm_map(current_realm)
	if realm_map == null:
		return layout

	# 五行枚举中文名 (起于 design/00-MASTER.md §五)
	const NODE_TYPE_NAMES := {
		0: "未知",
		1: "COMBAT", 2: "ELITE", 3: "BOSS",
		4: "EVENT", 5: "SHOP", 6: "REST", 7: "SECRET_ROOM",
	}

	var by_type: Dictionary = {}
	var total: int = 0
	var reachable_count: int = 0
	var unvisited_reachable_count: int = 0
	var columns_arr: Array = []

	# realm_map 有 nodes + columns 字段（参考 game_map.gd）
	if realm_map.has_method("get") and realm_map.get("columns") != null:
		var cols: Array = realm_map.columns
		for ci in range(cols.size()):
			var col_nodes: Array = cols[ci]
			var col_export: Array = []
			for n in col_nodes:
				if n == null:
					continue
				total += 1
				var node_type: int = int(n.get("type", 0)) if n is Dictionary else int(n.type)
				var node_id: String = str(n.get("id", "")) if n is Dictionary else str(n.id)
				var is_reachable: bool = bool(n.get("is_reachable", false)) if n is Dictionary else bool(n.is_reachable)
				var is_visited: bool = visited_node_ids.has(node_id)
				if is_reachable:
					reachable_count += 1
					if not is_visited:
						unvisited_reachable_count += 1
				var type_name: String = NODE_TYPE_NAMES.get(node_type, "未知")
				by_type[type_name] = int(by_type.get(type_name, 0)) + 1
				# 读连接（可达节点 list）
				var conns: Array = []
				if n is Dictionary and n.get("connections") != null:
					for c in n.connections:
						conns.append(str(c))
				col_export.append({
					"id": node_id,
					"type": type_name,
					"reachable": is_reachable,
					"visited": is_visited,
					"connections": conns,
				})
			columns_arr.append({
				"column_index": ci,
				"node_count": col_export.size(),
				"nodes": col_export,
			})

	layout["columns"] = columns_arr
	layout["stats"] = {
		"total_nodes": total,
		"reachable_count": reachable_count,
		"unvisited_reachable_count": unvisited_reachable_count,
		"by_type": by_type,
	}

	# 提示 minimax 的“未来决策上下文”文本（人类可读 + LLM 友好）
	layout["decision_hints"] = _build_decision_hints(by_type, unvisited_reachable_count, total)
	return layout

func _build_decision_hints(by_type: Dictionary, unvisited_reachable: int, total: int) -> String:
	var hints: Array = []
	if unvisited_reachable == 0:
		hints.append("⚠️ 没有 unvisited_reachable 节点 (all visited or locked) — 需要走 back or restart")
	if int(by_type.get("REST", 0)) == 0 and unvisited_reachable > 0:
		hints.append("ℹ️ 可选节点里没有 REST — HP < 30% 时考虑走 ELITE/BOSS 拿薬手 / 走 EVENT 拿暗器")
	if int(by_type.get("SHOP", 0)) > 0 and spirit_stones >= 100:
		hints.append("🛒 有 SHOP 且 spirit_stones >= 100 — 可以考虑 SHOP 买卡")
	if int(by_type.get("EVENT", 0)) > 0 and mo_nian >= 3:
		hints.append("⚡ 有 EVENT 且 mo_nian >= 3 — EVENT 可能有净魔念选项")
	if total == 0:
		hints.append("⚠️ map 未生成 (total=0) — 报 bug：game_map 未调用 generate()")
	if hints.is_empty():
		hints.append("✓ 地图状态正常，可正常选点")
	return " | ".join(hints)

## 将 layout 写到 user://ai-player-map-layout.json（ai_player_client.py 读这个）
## 还同时写一份 workspace 镜像让 Phase E consume / agent 能访问
func save_map_layout_to_disk(layout: Dictionary) -> String:
	if layout.is_empty():
		return ""
	var json_str: String = JSON.stringify(layout, "  ")
	var user_path: String = "user://ai-player-map-layout.json"
	var workspace_path: String = "res://../.openclaw/workspace/shendu/ai-player-map-layout.json"
	var abs_workspace: String = ProjectSettings.globalize_path(workspace_path)
	# user:// 写主源
	var user_file := FileAccess.open(user_path, FileAccess.WRITE)
	if user_file != null:
		user_file.store_string(json_str)
		user_file.close()
	# workspace 镜像（供 Phase E / 外部访问）
	var ws_dir: String = abs_workspace.get_base_dir()
	if not DirAccess.dir_exists_absolute(ws_dir):
		DirAccess.make_dir_recursive_absolute(ws_dir)
	var ws_file := FileAccess.open(abs_workspace, FileAccess.WRITE)
	if ws_file != null:
		ws_file.store_string(json_str)
		ws_file.close()
	return user_path

func _generate_run_id_for_layout() -> String:
	# 复用 ai_player.gd 的 run_id 生成模式（timestamp 格式）
	return Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")

