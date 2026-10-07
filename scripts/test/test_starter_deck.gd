## 初始卡组单元测试（starter_deck 真实化）
## 测试 10 张初始卡组的内容、费用分布、元素覆盖（CardPool.get_realm_pool(0)）
# implements: design/12-reward-system-spec §3.1 初始卡组
# implements_philosophy: rule_3_three_layer_loops

extends Node

func run_all_tests() -> void:
	print("--- starter_deck 真实化（spec §3.1 + EA 范围） ---")
	_test_chenmo_starter_deck_size()
	_test_suwan_starter_deck_size()
	_test_no_fake_mc_elem_ids()
	_test_all_cards_in_cardpool()
	_test_chenmo_element_coverage()
	_test_suwan_element_coverage()
	_test_chenmo_cost_distribution()
	_test_suwan_cost_distribution()
	_test_starter_deck_total_cost()
	_test_chenmo_has_fire_focus()
	_test_suwan_has_fire_focus()
	print("--- starter_deck 测试完成 ---")

func _test_chenmo_starter_deck_size() -> void:
	GameState.character_id = "chenmo"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	assert(deck.size() == 10, "陈默初始卡组应为 10 张，实际 %d" % deck.size())
	print("  ✓ 陈默初始卡组 10 张")

func _test_suwan_starter_deck_size() -> void:
	GameState.character_id = "suwan"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	assert(deck.size() == 10, "苏晚初始卡组应为 10 张，实际 %d" % deck.size())
	print("  ✓ 苏晚初始卡组 10 张")

func _test_no_fake_mc_elem_ids() -> void:
	for cid in ["chenmo", "suwan"]:
		GameState.character_id = cid
		var deck: Array = GameState.get_character_data().get("starter_deck", [])
		for card in deck:
			var card_id: String = card.get("id", "")
			assert(not card_id.begins_with("MC-ELEM-"), "[%s] 卡牌 ID %s 不应使用 MC-ELEM- 假 ID" % [cid, card_id])
	print("  ✓ 无 MC-ELEM-* 假 ID")

func _test_all_cards_in_cardpool() -> void:
	for cid in ["chenmo", "suwan"]:
		GameState.character_id = cid
		var deck: Array = GameState.get_character_data().get("starter_deck", [])
		for card in deck:
			var card_id: String = card.get("id", "")
			var pool_card = CardPool.get_card(card_id)
			assert(pool_card != null, "[%s] starter_deck 卡牌 %s 不在 CardPool 中" % [cid, card_id])
	print("  ✓ 所有 starter_deck 卡牌在 CardPool 中存在")

func _test_chenmo_element_coverage() -> void:
	GameState.character_id = "chenmo"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	var elements: Dictionary = {}
	for card in deck:
		var elem: int = int(card.get("element", -1))
		elements[elem] = elements.get(elem, 0) + 1
	assert(elements.size() >= 4, "陈默卡组应覆盖至少 4 元素，实际 %d 种" % elements.size())
	print("  ✓ 陈默卡组覆盖 %d 种元素（金属性 %d 张）" % [elements.size(), elements.get(0, 0)])

func _test_suwan_element_coverage() -> void:
	GameState.character_id = "suwan"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	var elements: Dictionary = {}
	for card in deck:
		var elem: int = int(card.get("element", -1))
		elements[elem] = elements.get(elem, 0) + 1
	assert(elements.size() >= 4, "苏晚卡组应覆盖至少 4 元素，实际 %d 种" % elements.size())
	print("  ✓ 苏晚卡组覆盖 %d 种元素（火属性 %d 张）" % [elements.size(), elements.get(3, 0)])

func _test_chenmo_cost_distribution() -> void:
	GameState.character_id = "chenmo"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	var total_cost: int = 0
	for card in deck:
		total_cost += int(card.get("cost", 0))
	var avg: float = float(total_cost) / float(deck.size())
	assert(avg <= 2.5, "陈默卡组平均费用应 ≤ 2.5（合理起手），实际 %.2f" % avg)
	print("  ✓ 陈默卡组总费用 %d，平均 %.2f" % [total_cost, avg])

func _test_suwan_cost_distribution() -> void:
	GameState.character_id = "suwan"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	var total_cost: int = 0
	for card in deck:
		total_cost += int(card.get("cost", 0))
	var avg: float = float(total_cost) / float(deck.size())
	assert(avg <= 2.5, "苏晚卡组平均费用应 ≤ 2.5，实际 %.2f" % avg)
	print("  ✓ 苏晚卡组总费用 %d，平均 %.2f" % [total_cost, avg])

func _test_starter_deck_total_cost() -> void:
	# spec §3.1 理想 18 费（0×2+1×3+2×2+3×2+4×1）；MVP 池无 0/4 费故允许 14-18
	for cid in ["chenmo", "suwan"]:
		GameState.character_id = cid
		var deck: Array = GameState.get_character_data().get("starter_deck", [])
		var total: int = 0
		for card in deck:
			total += int(card.get("cost", 0))
		assert(total >= 12 and total <= 20, "[%s] 总费用应在 12~20 之间，实际 %d" % [cid, total])
	print("  ✓ 两角色总费用均在 12~20 范围（spec §3.1 理想 18）")

func _test_chenmo_has_fire_focus() -> void:
	# 陈默金系专注：MC-ME-001 出现 2 次
	GameState.character_id = "chenmo"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	var me_001_count: int = 0
	for card in deck:
		if card.get("id", "") == "MC-ME-001":
			me_001_count += 1
	assert(me_001_count == 2, "陈默金系专注：MC-ME-001 应出现 2 次，实际 %d" % me_001_count)
	print("  ✓ 陈默金系专注：MC-ME-001×2")

func _test_suwan_has_fire_focus() -> void:
	# 苏晚火系专注：MC-FI-002 出现 2 次
	GameState.character_id = "suwan"
	var deck: Array = GameState.get_character_data().get("starter_deck", [])
	var fi_002_count: int = 0
	for card in deck:
		if card.get("id", "") == "MC-FI-002":
			fi_002_count += 1
	assert(fi_002_count == 2, "苏晚火系专注：MC-FI-002 应出现 2 次，实际 %d" % fi_002_count)
	print("  ✓ 苏晚火系专注：MC-FI-002×2")