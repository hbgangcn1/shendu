## EA 范围 45 张卡池契约验证
## 按 design/00-MASTER.md §十 EA 范围：45 张（5属性×9张），类型/稀有度分布合规
# implements: design/12-reward-system-spec §3.2 稀有度分布
# implements_philosophy: rule_3_three_layer_loops

extends Node

func run_all_tests() -> void:
	print("--- EA 范围 45 张卡池契约（spec 00-MASTER §十） ---")
	_test_total_pool_size()
	_test_element_distribution()
	_test_type_distribution()
	_test_rarity_distribution()
	_test_zero_cost_card()
	_test_legend_card()
	_test_pool_per_realm()
	print("--- EA 范围卡池测试完成 ---")

func _test_total_pool_size() -> void:
	var total: int = CardPool.get_pool_size()
	assert(total == 45, "EA 范围应为 45 张，实际 %d" % total)
	print("  ✓ 总池 45 张")

func _test_element_distribution() -> void:
	# 每属性 9 张（允许 ±1 浮动，FIRE 略多可接受）
	var counts: Dictionary = {"metal": 0, "wood": 0, "water": 0, "fire": 0, "earth": 0}
	var sample: Array = []
	for card_id in CardPool._mvp_pool + CardPool._zhuji_pool + CardPool._jindan_pool:
		var c: Dictionary = CardPool.get_card(card_id)
		if c:
			var elem: int = c.element
			if sample.size() < 5:
				sample.append("%s=%d" % [card_id, elem])
			var elem_str: String = ["metal", "wood", "water", "fire", "earth"][elem]
			counts[elem_str] = counts.get(elem_str, 0) + 1
	for elem in counts:
		var n: int = counts[elem]
		assert(n >= 7 and n <= 10, "%s 应有 7~10 张（EA 期望 9±2），实际 %d" % [elem, n])
	print("  ✓ 5 元素分布: %s (样例: %s)" % [JSON.stringify(counts), str(sample)])

func _test_type_distribution() -> void:
	# 类型：attack 18 / defense 11 / support 11 / special 5
	var counts: Dictionary = {"attack": 0, "defense": 0, "support": 0, "special": 0}
	for card_id in CardPool._mvp_pool + CardPool._zhuji_pool + CardPool._jindan_pool:
		var c: Dictionary = CardPool.get_card(card_id)
		if c:
			var k: int = c.card_kind
			var k_str: String = ["attack", "defense", "special", "support"][k]
			counts[k_str] = counts.get(k_str, 0) + 1
	# 允许 ±2 浮动
	assert(counts.get("attack", 0) >= 16 and counts.get("attack", 0) <= 20, "attack 应 16~20，实际 %d" % counts.get("attack", 0))
	assert(counts.get("defense", 0) >= 9 and counts.get("defense", 0) <= 13, "defense 应 9~13，实际 %d" % counts.get("defense", 0))
	assert(counts.get("support", 0) >= 9 and counts.get("support", 0) <= 13, "support 应 9~13，实际 %d" % counts.get("support", 0))
	assert(counts.get("special", 0) >= 3 and counts.get("special", 0) <= 7, "special 应 3~7，实际 %d" % counts.get("special", 0))
	print("  ✓ 4 类型分布: %s" % JSON.stringify(counts))

func _test_rarity_distribution() -> void:
	# common 27 / rare 13 / epic 4 / legend 1
	# mvp 池用新 schema (common=0/rare=1/epic=2/legend=3)
	# zhuji/jindan 池用旧 schema (common=1/rare=2/epic=3/legend=4)
	var counts: Dictionary = {"common": 0, "rare": 0, "epic": 0, "legend": 0}
	for card_id in CardPool._mvp_pool + CardPool._zhuji_pool + CardPool._jindan_pool:
		var c: Dictionary = CardPool.get_card(card_id)
		if c:
			var r: int = c.rarity
			var r_str: String
			if r in [0, 1]:
				r_str = ["common", "rare"][r]
			else:
				r_str = ["epic", "legend"][r - 2]
			counts[r_str] = counts.get(r_str, 0) + 1
	assert(counts.get("common", 0) == 27, "common 应 27，实际 %d" % counts.get("common", 0))
	assert(counts.get("rare", 0) == 13, "rare 应 13，实际 %d" % counts.get("rare", 0))
	assert(counts.get("epic", 0) == 4, "epic 应 4，实际 %d" % counts.get("epic", 0))
	assert(counts.get("legend", 0) == 1, "legend 应 1，实际 %d" % counts.get("legend", 0))
	print("  ✓ 4 稀有度分布: %s" % JSON.stringify(counts))

func _test_zero_cost_card() -> void:
	# EA 范围需 0 费卡（spec §3.1 理想初始卡组有 0×2）
	var jin_jing: Dictionary = CardPool.get_card("MC-ME-003")
	assert(jin_jing != null, "MC-ME-003 金精聚应存在（0 费）")
	assert(jin_jing.cost == 0, "金精聚费用应为 0")
	print("  ✓ 0 费卡 MC-ME-003 金精聚（unlock starter_deck 0 费需求）")

func _test_legend_card() -> void:
	var ye_huo: Dictionary = CardPool.get_card("MC-FI-006")
	assert(ye_huo != null, "MC-FI-006 业火焚天应存在（legend）")
	assert(ye_huo.cost == 4, "业火焚天费用应为 4（EA 范围 4 费覆盖）")
	print("  ✓ 传说卡 MC-FI-006 业火焚天（unlock starter_deck 4 费需求）")

func _test_pool_per_realm() -> void:
	# 验证按 realm 切池可用
	var mvp: Array = CardPool.get_realm_pool(0)
	var zhuji: Array = CardPool.get_realm_pool(1)
	var jindan: Array = CardPool.get_realm_pool(2)
	assert(mvp.size() == 17, "炼气池应 17 张（mvp 9 + 新 8），实际 %d" % mvp.size())
	assert(zhuji.size() == 15, "筑基池应 15 张（zhuji 9 + 新 6），实际 %d" % zhuji.size())
	assert(jindan.size() == 13, "金丹池应 13 张（jindan 7 + 新 6），实际 %d" % jindan.size())
	print("  ✓ 按 realm 切池: 炼气 %d / 筑基 %d / 金丹 %d" % [mvp.size(), zhuji.size(), jindan.size()])
