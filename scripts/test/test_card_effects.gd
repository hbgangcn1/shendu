## 卡牌效果结构单元测试
## 测试 effects[] 的 trigger/action 结构化格式、card_pool 加载逻辑与兼容字段同步
# implements: design/07-combat-system-spec §五 战斗效果
# implements_philosophy: rule_1_core_loop_first, rule_6_flow_channel

extends Node

const CardDataResource := preload("res://scripts/core/card_data.gd")

func run_all_tests() -> void:
	print("\n=== 卡牌效果结构测试 ===")
	test_new_card_ids()
	test_effects_structure()
	test_single_effect_card()
	test_multi_effect_card()
	test_compat_fields_synced()
	test_all_cards_have_effects()
	test_damage_effect_values()
	test_block_effect_values()
	test_heal_effect_values()
	test_draw_effect_values()
	print("=== 卡牌效果结构测试完成 ===\n")

func test_new_card_ids() -> void:
	print("\n--- 测试新 ID 格式 (MC-ELEM-SEQ) ---")
	var expected_ids := [
		"MC-ME-001", "MC-ME-002",
		"MC-WO-001", "MC-WO-002",
		"MC-WA-001", "MC-WA-002",
		"MC-FI-001", "MC-FI-002",
		"MC-EA-001",
	]
	for id in expected_ids:
		var card = CardPool.get_card(id)
		assert(card != null, "卡牌 %s 应存在" % id)
	print("  ✓ 新 ID 格式正确")

func test_effects_structure() -> void:
	print("\n--- 测试 effects 使用 trigger/action 结构 ---")
	var card = CardPool.get_card("MC-ME-001")
	assert(card != null, "MC-ME-001 应存在")
	assert(card.effects.size() == 1, "MC-ME-001 应有 1 个 effect")
	var effect = card.effects[0]
	assert(effect.has("trigger"), "effect 应有 trigger 字段")
	assert(effect.has("action"), "effect 应有 action 字段")
	var action = effect.get("action", {})
	assert(action.has("type"), "action 应有 type 字段")
	assert(action.has("value"), "action 应有 value 字段")
	assert(effect.get("trigger") == "on_attack", "trigger 应为 on_attack")
	assert(action.get("type") == "Damage", "action type 应为 Damage")
	assert(int(action.get("value")) == 8, "damage value 应为 8")
	print("  ✓ effects 结构正确")

func test_single_effect_card() -> void:
	print("\n--- 测试单效果卡牌 ---")
	var card = CardPool.get_card("MC-ME-001")
	assert(card != null)
	assert(card.effects.size() == 1, "金刚斩应有 1 个 effect")
	assert(card.effects[0].get("trigger") == "on_attack")
	print("  ✓ 单效果卡牌正确")

func test_multi_effect_card() -> void:
	print("\n--- 测试多效果卡牌（水弹 = 伤害+抽牌） ---")
	var card = CardPool.get_card("MC-WA-001")
	assert(card != null)
	assert(card.effects.size() == 2, "水弹应有 2 个 effect，实际为 %d" % card.effects.size())
	# 第一个 effect: Damage
	var e1 = card.effects[0]
	assert(e1.get("trigger") == "on_attack", "第 1 个 trigger 应为 on_attack")
	assert(e1.get("action", {}).get("type") == "Damage", "第 1 个 action type 应为 Damage")
	# 第二个 effect: Draw
	var e2 = card.effects[1]
	assert(e2.get("trigger") == "on_play", "第 2 个 trigger 应为 on_play")
	assert(e2.get("action", {}).get("type") == "Draw", "第 2 个 action type 应为 Draw")
	print("  ✓ 多效果卡牌正确")

func test_compat_fields_synced() -> void:
	print("\n--- 测试兼容字段从 effects 同步 ---")
	# 金刚斩: damage=8, block=0, draw=0, heal=0
	var card1 = CardPool.get_card("MC-ME-001")
	assert(card1.damage == 8, "金刚斩 damage 应为 8，实际为 %d" % card1.damage)
	assert(card1.block == 0, "金刚斩 block 应为 0")
	assert(card1.draw_cards == 0, "金刚斩 draw_cards 应为 0")
	assert(card1.heal == 0, "金刚斩 heal 应为 0")
	# 铁壁: block=6
	var card2 = CardPool.get_card("MC-ME-002")
	assert(card2.block == 6, "铁壁 block 应为 6，实际为 %d" % card2.block)
	assert(card2.damage == 0, "铁壁 damage 应为 0")
	# 水弹: damage=5, draw_cards=1
	var card3 = CardPool.get_card("MC-WA-001")
	assert(card3.damage == 5, "水弹 damage 应为 5，实际为 %d" % card3.damage)
	assert(card3.draw_cards == 1, "水弹 draw_cards 应为 1，实际为 %d" % card3.draw_cards)
	# 回春术: heal=5
	var card4 = CardPool.get_card("MC-WO-002")
	assert(card4.heal == 5, "回春术 heal 应为 5，实际为 %d" % card4.heal)
	print("  ✓ 兼容字段同步正确")

func test_all_cards_have_effects() -> void:
	print("\n--- 测试所有卡牌都有 effects 数组 ---")
	var pool = CardPool.get_mvp_pool()
	for card in pool:
		assert(card.effects is Array, "%s effects 应为数组" % card.id)
		assert(card.effects.size() > 0, "%s effects 不应为空" % card.id)
	print("  ✓ 所有卡牌都有 effects")

func test_damage_effect_values() -> void:
	print("\n--- 测试伤害效果数值 ---")
	var test_cases := {
		"MC-ME-001": 8,   # 金刚斩
		"MC-WO-001": 6,   # 藤鞭
		"MC-WA-001": 5,   # 水弹
		"MC-FI-001": 10,  # 烈焰弹
		"MC-FI-002": 14,  # 爆燃
	}
	for id in test_cases:
		var card = CardPool.get_card(id)
		assert(card != null, "%s 应存在" % id)
		assert(card.damage == test_cases[id], "%s 伤害应为 %d，实际为 %d" % [id, test_cases[id], card.damage])
	print("  ✓ 伤害数值正确")

func test_block_effect_values() -> void:
	print("\n--- 测试格挡效果数值 ---")
	var test_cases := {
		"MC-ME-002": 6,   # 铁壁
		"MC-WA-002": 5,   # 水幕
		"MC-EA-001": 8,   # 岩盾
	}
	for id in test_cases:
		var card = CardPool.get_card(id)
		assert(card != null, "%s 应存在" % id)
		assert(card.block == test_cases[id], "%s 格挡应为 %d，实际为 %d" % [id, test_cases[id], card.block])
	print("  ✓ 格挡数值正确")

func test_heal_effect_values() -> void:
	print("\n--- 测试治疗效果数值 ---")
	var card = CardPool.get_card("MC-WO-002")
	assert(card.heal == 5, "回春术治疗应为 5，实际为 %d" % card.heal)
	print("  ✓ 治疗数值正确")

func test_draw_effect_values() -> void:
	print("\n--- 测试抽牌效果数值 ---")
	var card = CardPool.get_card("MC-WA-001")
	assert(card.draw_cards == 1, "水弹抽牌应为 1，实际为 %d" % card.draw_cards)
	print("  ✓ 抽牌数值正确")
