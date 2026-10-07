## 卡池加载器 — 管理所有卡牌数据
## 作为 Autoload 单例使用
## 按 design/core-loop/02-card-schema.md + 12-reward-system-spec.md §2.1 设计

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

extends Node

# 加载后的卡牌数据字典 {id: card_data_resource}
var _cards: Dictionary = {}

# 三个境界池（按 12-reward-system-spec.md §2.1 设计意图）
var _mvp_pool: Array[String] = []      # 炼气期 realm 0
var _zhuji_pool: Array[String] = []    # 筑基期 realm 1
var _jindan_pool: Array[String] = []   # 金丹期 realm 2

# 当前激活境界池（默认 mvp，map_generator 加载后切换）
var _active_pool_ids: Array[String] = []

func _ready() -> void:
	_load_cards("res://data/cards/mvp_cards.json", _mvp_pool)
	_load_cards("res://data/cards/zhuji_cards.json", _zhuji_pool)
	_load_cards("res://data/cards/jindan_cards.json", _jindan_pool)
	# 默认激活 mvp 池（map_generator 可通过 set_active_realm 切换）
	_active_pool_ids = _mvp_pool.duplicate()
	print("CardPool: 加载 mvp=%d + zhuji=%d + jindan=%d = 总 %d 张卡" % [
		_mvp_pool.size(), _zhuji_pool.size(), _jindan_pool.size(), _cards.size()
	])

## 从 JSON 文件加载卡牌数据（按 02-card-schema.md §1.1）
func _load_cards(path: String, target_pool: Array) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法加载卡牌数据文件: " + path)
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("JSON 解析失败 %s: %s" % [path, json.get_error_message()])
		return

	for card_dict in json.data:
		var dict := card_dict as Dictionary
		var card = load("res://scripts/core/card_data.gd").new()

		# ===== spec 必填字段 =====
		card.id = dict.get("id", "")
		card.name = dict.get("name", dict.get("card_name", ""))  # 兼容旧字段名
		card.description = dict.get("description", "")
		card.cost = int(dict.get("cost", 0))

		# ===== spec 字符串字段 → int enum =====
		var elem_str = dict.get("element", "metal")
		if typeof(elem_str) in [TYPE_INT, TYPE_FLOAT]:
			card.element = int(elem_str) as WuXing.Element
		else:
			card.set_element_from_string(str(elem_str))

		var kind_str = dict.get("type", dict.get("card_type", "attack"))
		if typeof(kind_str) in [TYPE_INT, TYPE_FLOAT]:
			card.card_kind = int(kind_str)
		else:
			card.set_kind_from_string(str(kind_str))

		var rar_str = dict.get("rarity", "common")
		if typeof(rar_str) in [TYPE_INT, TYPE_FLOAT]:
			card.rarity = int(rar_str)
		else:
			card.set_rarity_from_string(str(rar_str))

		# ===== spec 路径字段 =====
		card.art_path = dict.get("art_path", dict.get("image_path", ""))

		# ===== PCG 命名字段（spec §4） =====
		var prefix_val = dict.get("name_prefix", "")
		card.name_prefix = str(prefix_val) if prefix_val != null else ""
		card.name_core = dict.get("name_core", "")
		var suffix_val = dict.get("name_suffix", "")
		card.name_suffix = str(suffix_val) if suffix_val != null else ""

		# ===== 进阶字段（spec §1.4） =====
		var up_id_val = dict.get("upgrade_id", "")
		card.upgrade_id = str(up_id_val) if up_id_val != null else ""
		var ch_lock_val = dict.get("character_lock", "")
		card.character_lock = str(ch_lock_val) if ch_lock_val != null else ""
		card.engraving_slot_count = int(dict.get("engraving_slot_count", 0))
		card.erosion_tolerance = int(dict.get("erosion_tolerance", 0))
		card.tags = dict.get("tags", [])

		# ===== effects[]（spec §一.1 + 二） =====
		card.effects = dict.get("effects", [])

		# ===== 同步 effects → damage/block/heal/draw_cards =====
		# 按 PROJECT_CONTEXT.md "effects[] 同步到 card.damage/block/draw_cards/heal"
		_sync_effects_to_stats(card)

		# ===== 自动按稀有度补刻印槽/侵蚀耐受 =====
		card.apply_default_advanced_stats()

		# ===== 注入字典 =====
		_cards[card.id] = card
		target_pool.append(card.id)

## 同步 effects[] → damage/block/heal/draw_cards（兼容字段）
func _sync_effects_to_stats(card) -> void:
	for effect in card.effects:
		if not (effect is Dictionary):
			continue
		var action: Dictionary = effect.get("action", {})
		if action.is_empty():
			continue
		var t: String = action.get("type", "")
		var v: int = int(action.get("value", 0))
		var hits: int = int(action.get("hits", 1))
		var total: int = v * hits
		match t:
			"Damage": card.damage += total
			"Block": card.block += total
			"Heal": card.heal += total
			"Draw": card.draw_cards += total

## 根据 ID 获取卡牌
func get_card(id: String):
	return _cards.get(id, null)

## 切换激活境界（map_generator 调用）
func set_active_realm(realm: int) -> void:
	match realm:
		0: _active_pool_ids = _mvp_pool.duplicate()
		1: _active_pool_ids = _zhuji_pool.duplicate()
		2: _active_pool_ids = _jindan_pool.duplicate()
		_: _active_pool_ids = _mvp_pool.duplicate()

## 兼容旧 API：返回当前激活境界的所有卡牌
func get_mvp_pool() -> Array:
	return _get_pool_by_ids(_active_pool_ids)

## 按 realm 切池（12-reward-system-spec.md §6.3.2 准备）
func get_realm_pool(realm: int) -> Array:
	var pool_ids: Array
	match realm:
		0: pool_ids = _mvp_pool
		1: pool_ids = _zhuji_pool
		2: pool_ids = _jindan_pool
		_: pool_ids = _mvp_pool
	return _get_pool_by_ids(pool_ids)

## 按 ID 列表返回 CardData 列表
func _get_pool_by_ids(ids: Array) -> Array:
	var result: Array = []
	for id in ids:
		if _cards.has(id):
			result.append(_cards[id])
	return result

## 兼容旧 API：获取 MVP 卡池
func get_mvp_pool_original() -> Array:
	return _get_pool_by_ids(_mvp_pool)

## 卡池大小
func get_pool_size() -> int:
	return _cards.size()
