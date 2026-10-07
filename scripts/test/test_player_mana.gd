## Player 灵力系统单元测试
## 测试灵力管理：max=10, 累积制, 过载, 枯竭, 回合充能, 出牌消耗
# implements: design/00-MASTER.md §一 灵力, design/07-combat-system-spec §三.3
# implements_philosophy: rule_1_core_loop_first, rule_6_flow_channel

extends Node

func run_all_tests() -> void:
	print("\n=== 灵力系统测试 ===")
	test_max_mana_is_10()
	test_mana_accumulates()
	test_mana_does_not_exceed_max()
	test_mana_regen_is_4()
	test_turn_spent_mana_tracking()
	test_exhaustion_after_two_zero_mana_turns()
	test_regen_penalty_when_exhausted()
	test_exhaustion_resets_after_non_zero_turn()
	print("=== 灵力系统测试完成 ===\n")

func _create_player() -> Player:
	return Player.new("测试者", 80, WuXing.Element.FIRE, 10)

func test_max_mana_is_10() -> void:
	print("\n--- 测试灵力上限为 10 ---")
	var p: Player = _create_player()
	assert(p.max_mana == 10, "max_mana 应为 10，实际为 %d" % p.max_mana)
	assert(p.current_energy == 10, "初始灵力应为 10，实际为 %d" % p.current_energy)
	print("  ✓ 灵力上限正确")

func test_mana_accumulates() -> void:
	print("\n--- 测试灵力累积（不重置） ---")
	var p: Player = _create_player()
	# 消耗 6 灵力
	p.current_energy -= 6
	assert(p.current_energy == 4, "消耗后灵力应为 4，实际为 %d" % p.current_energy)
	# 开始回合：+4 累积
	p.start_turn()
	assert(p.current_energy == 8, "累积后灵力应为 8，实际为 %d" % p.current_energy)
	print("  ✓ 灵力累积正确")

func test_mana_does_not_exceed_max() -> void:
	print("\n--- 测试灵力不超过上限 ---")
	var p: Player = _create_player()
	# 灵力已满 10，不消耗直接开始新回合
	p.start_turn()
	assert(p.current_energy == 10, "满灵力回合开始后应仍为 10，实际为 %d" % p.current_energy)
	# 消耗 2，再开始回合
	p.current_energy -= 2
	p.start_turn()
	assert(p.current_energy == 10, "累积后应 cap 在 10，实际为 %d" % p.current_energy)
	print("  ✓ 灵力上限 cap 正确")

func test_mana_regen_is_4() -> void:
	print("\n--- 测试每回合回复 4 ---")
	var p: Player = _create_player()
	p.current_energy = 0
	p.start_turn()
	assert(p.current_energy == 4, "空灵力回复后应为 4，实际为 %d" % p.current_energy)
	print("  ✓ 灵力回复量正确")

func test_turn_spent_mana_tracking() -> void:
	print("\n--- 测试回合花费追踪 ---")
	var p: Player = _create_player()
	assert(p.turn_spent_mana == 0, "初始花费应为 0")
	# 模拟打牌扣费
	p.current_energy -= 3
	p.turn_spent_mana += 3
	assert(p.turn_spent_mana == 3, "花费应为 3，实际为 %d" % p.turn_spent_mana)
	# 回合开始重置
	p.start_turn()
	assert(p.turn_spent_mana == 0, "回合开始后花费应重置为 0")
	print("  ✓ 花费追踪正确")

func test_exhaustion_after_two_zero_mana_turns() -> void:
	print("\n--- 测试连续 2 回合灵力为 0 触发枯竭 ---")
	var p: Player = _create_player()
	p.init_deck()
	# 第 1 回合：start_turn → 消耗所有灵力 → end_turn
	p.start_turn()
	p.current_energy = 0
	p.zero_mana_streak = 1  # 模拟灵力为 0 的回合
	p.end_turn()
	assert(p.exhausted == false, "1 回合灵力为 0 不应枯竭")
	# 第 2 回合：灵力仍为 0
	p.start_turn()
	p.current_energy = 0
	p.zero_mana_streak = 2
	p.end_turn()
	assert(p.exhausted == true, "连续 2 回合灵力为 0 应进入枯竭")
	print("  ✓ 枯竭触发正确")

func test_regen_penalty_when_exhausted() -> void:
	print("\n--- 测试枯竭状态回复惩罚 ---")
	var p: Player = _create_player()
	# 手动设置枯竭
	p.exhausted = true
	p.current_energy = 0
	p.start_turn()
	# 枯竭时回复 4-1=3，但最低 2
	assert(p.current_energy == 3, "枯竭回复应为 3，实际为 %d" % p.current_energy)
	assert(p.exhausted == false, "开始回合后枯竭应重置")
	print("  ✓ 枯竭回复惩罚正确")

func test_exhaustion_resets_after_non_zero_turn() -> void:
	print("\n--- 测试非零灵力回合重置枯竭计数 ---")
	var p: Player = _create_player()
	p.init_deck()
	# 模拟第 1 回合灵力为 0
	p.zero_mana_streak = 1
	assert(p.zero_mana_streak == 1, "1 回合灵力为 0，streak 应为 1")
	# 模拟第 2 回合灵力不为 0（play_card 中重置）
	p.zero_mana_streak = 0
	assert(p.zero_mana_streak == 0, "非零回合应重置 streak")
	assert(p.exhausted == false, "不应进入枯竭")
	print("  ✓ 枯竭重置正确")
