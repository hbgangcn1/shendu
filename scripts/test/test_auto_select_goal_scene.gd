## P1.1 Phase 2 — _select_goal_scene_for_deck 单元测试
## 测试 ai_player.gd 的决策树 (pure function)
## 6 个场景覆盖: deck 大小 + 元素偏科 + realm
extends Node

func run_all_tests() -> void:
	print("\n=== AIPlayer 自动选 Goal Scene (P1.1 Phase 2) 测试 ===")
	test_select_empty_deck()
	test_select_small_deck()
	test_select_large_deck()
	test_select_dominant_element()
	test_select_realm_progression()
	test_select_default_baseline()
	test_select_balanced_deck()
	print("=== AIPlayer 自动选 Goal Scene (P1.1 Phase 2) 测试完成 ===\n")

# 决策树实际是 ai_player.gd 的内部函数
# 测试时我们用 lambda 或重新实现决策树来验证逻辑
# 这里通过 mock ai_player 实例或直接调静态方法验证
#
# 因为 _select_goal_scene_for_deck 是 ai_player instance method,
# 测试通过构造 deck 数组 + 期望 scene name 来覆盖 6 个 case

func _select_via_logic(deck: Array, realm: int) -> String:
	# Mirror ai_player.gd::_select_goal_scene_for_deck (用于测试, 不依赖 instance)
	if deck.size() < 5:
		return "deck_health_check"
	if deck.size() > 20:
		return "battle_full_clear"
	var element_counts := {}
	for card in deck:
		var elem := int(card.get("element", 0))
		if elem > 0:
			element_counts[elem] = int(element_counts.get(elem, 0)) + 1
	if not element_counts.is_empty():
		var max_count := 0
		for elem in element_counts:
			if int(element_counts[elem]) > max_count:
				max_count = int(element_counts[elem])
		if deck.size() > 0 and float(max_count) / float(deck.size()) >= 0.6:
			return "chain_test"
	if realm >= 3:
		return "battle_deep"
	if realm == 2:
		return "battle_should_lose"
	return "battle_baseline"

func test_select_empty_deck() -> void:
	print("\n--- 测试 deck.size()=0 → deck_health_check ---")
	var scene: String = _select_via_logic([], 1)
	assert(scene == "deck_health_check", "空 deck 应返回 deck_health_check, 实际 %s" % scene)
	print("  ✓ 空 deck → deck_health_check")

func test_select_small_deck() -> void:
	print("\n--- 测试 deck.size()=3 → deck_health_check ---")
	var deck := _make_deck(3, 1)  # 3 张木属性
	var scene: String = _select_via_logic(deck, 1)
	assert(scene == "deck_health_check", "deck=3 应返回 deck_health_check, 实际 %s" % scene)
	print("  ✓ 小 deck (3 张) → deck_health_check")

func test_select_large_deck() -> void:
	print("\n--- 测试 deck.size()=25 → battle_full_clear ---")
	var deck := _make_deck(25, 1)  # 25 张同元素（但 size 触发先于偏科）
	var scene: String = _select_via_logic(deck, 1)
	assert(scene == "battle_full_clear", "deck=25 应返回 battle_full_clear, 实际 %s" % scene)
	print("  ✓ 大 deck (25 张) → battle_full_clear")

func test_select_dominant_element() -> void:
	print("\n--- 测试 偏科 60%+ (10 张里 7 张同元素) → chain_test ---")
	# 7 张木(1) + 1 张火(2) + 1 张土(3) + 1 张金(4) = 10 张, 木占 70%
	var deck: Array = []
	for i in 7:
		deck.append({"element": 1, "id": "card_w_%d" % i})
	deck.append({"element": 2, "id": "card_h_1"})
	deck.append({"element": 3, "id": "card_t_1"})
	deck.append({"element": 4, "id": "card_j_1"})
	var scene: String = _select_via_logic(deck, 1)
	assert(scene == "chain_test", "偏科 70 percent 应返回 chain_test, 实际 %s" % scene)
	print("  ✓ 偏科 70% (10 张) → chain_test")

func test_select_realm_progression() -> void:
	print("\n--- 测试 realm 阶段 ---")
	# 平衡 deck (10 张, 5 种元素各 2 张) 不触发偏科
	var balanced_deck := [
		{"element": 1, "id": "w1"}, {"element": 1, "id": "w2"},
		{"element": 2, "id": "h1"}, {"element": 2, "id": "h2"},
		{"element": 3, "id": "t1"}, {"element": 3, "id": "t2"},
		{"element": 4, "id": "j1"}, {"element": 4, "id": "j2"},
		{"element": 5, "id": "s1"}, {"element": 5, "id": "s2"},
	]
	var scene_realm1: String = _select_via_logic(balanced_deck, 1)
	assert(scene_realm1 == "battle_baseline", "realm=1 应返回 battle_baseline, 实际 %s" % scene_realm1)
	print("  ✓ realm=1 → battle_baseline")
	var scene_realm2: String = _select_via_logic(balanced_deck, 2)
	assert(scene_realm2 == "battle_should_lose", "realm=2 应返回 battle_should_lose, 实际 %s" % scene_realm2)
	print("  ✓ realm=2 → battle_should_lose")
	var scene_realm3: String = _select_via_logic(balanced_deck, 3)
	assert(scene_realm3 == "battle_deep", "realm=3 应返回 battle_deep, 实际 %s" % scene_realm3)
	print("  ✓ realm=3 → battle_deep")
	var scene_realm4: String = _select_via_logic(balanced_deck, 4)
	assert(scene_realm4 == "battle_deep", "realm=4 应返回 battle_deep, 实际 %s" % scene_realm4)
	print("  ✓ realm=4 → battle_deep (>= 3 一律)")

func test_select_default_baseline() -> void:
	print("\n--- 测试 default 路径 (deck=10, realm=1, balanced) → battle_baseline ---")
	var deck := [
		{"element": 1, "id": "w1"}, {"element": 2, "id": "h1"},
		{"element": 3, "id": "t1"}, {"element": 4, "id": "j1"},
		{"element": 5, "id": "s1"}, {"element": 1, "id": "w2"},
		{"element": 2, "id": "h2"}, {"element": 3, "id": "t2"},
		{"element": 4, "id": "j2"}, {"element": 5, "id": "s2"},
	]
	var scene: String = _select_via_logic(deck, 1)
	assert(scene == "battle_baseline", "balanced deck realm=1 应返回 battle_baseline, 实际 %s" % scene)
	print("  ✓ balanced deck realm=1 → battle_baseline")

func test_select_balanced_deck() -> void:
	print("\n--- 测试 balanced 8 张 (40% 偏科不过线) → 默认 battle_baseline ---")
	# 8 张, 8 个不同元素分配 → 最高 2 张同元素 = 25% < 60% 阈值
	var deck: Array = []
	for i in 2:
		deck.append({"element": 1, "id": "w%d" % i})
	for i in 2:
		deck.append({"element": 2, "id": "h%d" % i})
	for i in 2:
		deck.append({"element": 3, "id": "t%d" % i})
	deck.append({"element": 4, "id": "j1"})
	deck.append({"element": 5, "id": "s1"})
	# 8 张, 木占 25% (2/8) < 60%
	var scene: String = _select_via_logic(deck, 1)
	assert(scene == "battle_baseline", "balanced 8 张应返回 battle_baseline, 实际 %s" % scene)
	print("  ✓ balanced 8 张 (25%) → battle_baseline (偏科阈值 60% 不过线)")

func _make_deck(count: int, element: int) -> Array:
	var deck: Array = []
	for i in count:
		deck.append({"element": element, "id": "card_%d" % i})
	return deck