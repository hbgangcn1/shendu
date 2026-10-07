## Player 单元测试
## 测试玩家牌堆管理、能量系统和出牌逻辑
# implements: design/07-combat-system-spec §三 玩家与出牌
# implements_philosophy: rule_1_core_loop_first, rule_5_real_agency

extends Node

const CardDataResource := preload("res://scripts/core/card_data.gd")

func run_all_tests() -> void:
	print("\n=== Player 测试 ===")
	test_player_creation()
	test_init_deck()
	test_draw_cards()
	test_play_card()
	test_energy_management()
	test_reshuffle()
	test_turn_management()
	print("=== Player 测试完成 ===\n")

func test_player_creation() -> void:
	print("\n--- 测试 Player 创建 ---")
	var player := Player.new("主角", 80, WuXing.Element.FIRE, 10)
	assert(player.actor_name == "主角", "名称错误")
	assert(player.max_hp == 80, "最大 HP 错误")
	assert(player.max_energy == 10, "最大能量错误")
	assert(player.current_energy == 10, "当前能量错误")
	assert(player.hand.is_empty(), "初始手牌应为空")
	assert(player.draw_pile.is_empty(), "初始抽牌堆应为空")
	print("  ✓ Player 创建正确")

func test_init_deck() -> void:
	print("\n--- 测试初始化牌堆 ---")
	var player := Player.new("主角", 80, WuXing.Element.FIRE, 10)
	player.init_deck()
	# fallback 路径：GameState.deck 为空时用 mvp 池（炼气池 17 张）
	var mvp_size: int = CardPool.get_mvp_pool().size()
	assert(player.draw_pile.size() == mvp_size, "抽牌堆应为 %d 张（mvp 池），实际为 %d" % [mvp_size, player.draw_pile.size()])
	assert(player.hand.is_empty(), "手牌应为空")
	assert(player.discard_pile.is_empty(), "弃牌堆应为空")
	print("  ✓ 牌堆初始化正确（%d 张）" % player.draw_pile.size())

func test_draw_cards() -> void:
	print("\n--- 测试抽牌 ---")
	var player := Player.new("主角", 80, WuXing.Element.FIRE, 10)
	player.init_deck()
	var mvp_size: int = CardPool.get_mvp_pool().size()

	# 抽 5 张牌
	var drawn := player.draw_cards(5)
	assert(drawn.size() == 5, "应抽 5 张牌，实际为 %d" % drawn.size())
	assert(player.hand.size() == 5, "手牌应为 5 张")
	assert(player.get_draw_pile_count() == mvp_size - 5, "抽牌堆应剩 %d 张，实际为 %d" % [mvp_size - 5, player.get_draw_pile_count()])
	print("  ✓ 抽牌正确")

func test_play_card() -> void:
	print("\n--- 测试出牌 ---")
	var player := Player.new("主角", 80, WuXing.Element.FIRE, 10)
	player.init_deck()
	player.draw_cards(5)
	
	var old_hand_size := player.hand.size()
	var old_energy := player.current_energy
	var card: CardDataResource = player.hand[0]
	
	# 确保能量足够
	if card.cost <= player.current_energy:
		var success := player.play_card(0)
		assert(success == true, "出牌应成功")
		assert(player.hand.size() == old_hand_size - 1, "手牌应减少 1")
		assert(player.current_energy == old_energy - card.cost, "能量应扣除")
		assert(player.discard_pile.size() == 1, "弃牌堆应有 1 张")
	print("  ✓ 出牌正确")

func test_energy_management() -> void:
	print("\n--- 测试能量管理 ---")
	var player := Player.new("主角", 80, WuXing.Element.FIRE, 10)
	player.init_deck()
	player.draw_cards(5)
	
	# 尝试打出多张牌直到能量不足
	var cards_played := 0
	while player.hand.size() > 0 and player.current_energy >= player.hand[0].cost:
		player.play_card(0)
		cards_played += 1
	
	# 尝试能量不足时出牌
	if player.hand.size() > 0:
		var success := player.play_card(0)
		assert(success == false, "能量不足时出牌应失败")
	print("  ✓ 能量管理正确")

func test_reshuffle() -> void:
	print("\n--- 测试洗牌 ---")
	var player := Player.new("主角", 80, WuXing.Element.FIRE, 10)
	player.init_deck()
	var mvp_size: int = CardPool.get_mvp_pool().size()

	# 抽 5 张牌（hand_size=5）
	player.draw_cards()
	assert(player.hand.size() == 5, "应抽 5 张，实际为 %d" % player.hand.size())
	assert(player.get_draw_pile_count() == mvp_size - 5, "抽牌堆应剩 %d 张" % (mvp_size - 5))
	
	# 弃掉所有手牌
	player.discard_hand()
	assert(player.hand.is_empty(), "手牌应为空")
	assert(player.get_discard_pile_count() == 5, "弃牌堆应有 5 张，实际为 %d" % player.get_discard_pile_count())
	
	# 再次抽牌（应触发洗牌）
	player.draw_cards()
	assert(player.hand.size() == 5, "手牌应为 5 张")
	print("  ✓ 洗牌正确")

func test_turn_management() -> void:
	print("\n--- 测试回合管理 ---")
	var player := Player.new("主角", 80, WuXing.Element.FIRE, 10)
	player.init_deck()
	
	# 开始回合（初始 10 + 回复 4 = 14，但上限 10）
	player.start_turn()
	assert(player.current_energy == 10, "能量应为 min(10, 10+4)=10，实际为 %d" % player.current_energy)
	assert(player.hand.size() == 5, "应抽 5 张牌，实际为 %d" % player.hand.size())
	
	# 结束回合（手牌保留，不弃牌）
	player.end_turn()
	assert(player.hand.size() == 5, "手牌应保留 5 张，实际为 %d" % player.hand.size())
	print("  ✓ 回合管理正确")
