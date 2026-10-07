## AIPlayer.compute_goal_pct() 单元测试
## 测试 scripts/qa/ai_player.gd 的 Goal 进度计算
##
## P1.1 Phase 2 (H6, 2026-07-05 20:40): Goal 实时进度感知
## 覆盖：
##   - 9 种 Goal type 的 pct 计算
##   - 边界：value=0 / pct > 1.0 时钳制到 1.0 / 不存在的 type 返回 0.0

# implements: agent-infrastructure (test infrastructure)
# implements_philosophy: rule_5_real_agency, rule_9_progressive_disclosure

extends Node

func run_all_tests() -> void:
	print("\n=== compute_goal_pct 测试 ===")
	test_survive_n_battles_pct()
	test_max_runtime_pct()
	test_collect_n_cards_pct()
	test_trigger_n_chains_pct()
	test_reach_realm_pct()
	test_visit_node_types_pct()
	test_loop_count_pct()
	test_pct_clamp_to_one_when_exceeded()
	test_value_zero_returns_check_result()
	test_unknown_type_returns_zero()
	print("=== compute_goal_pct 测试完成 ===\n")

func _pct(g: Goal, stats: Dictionary) -> float:
	return Qa.ai_player.compute_goal_pct(g, stats)

# ===== 9 种 Goal type =====

func test_survive_n_battles_pct() -> void:
	print("\n--- 测试 survive_n_battles pct ---")
	var g := Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 3)
	assert(_pct(g, {"battles_won": 0}) == 0.0, "battles_won=0 应 0.0")
	assert(_pct(g, {"battles_won": 1}) < 0.34 and _pct(g, {"battles_won": 1}) > 0.33, "battles_won=1 应 ~0.333")
	assert(_pct(g, {"battles_won": 3}) == 1.0, "battles_won=3 应 1.0")
	assert(_pct(g, {"battles_won": 5}) == 1.0, "battles_won=5 应钳制到 1.0")
	print("  ✓ survive_n_battles: 0/1/3/5 → 0/0.333/1.0/1.0")

func test_max_runtime_pct() -> void:
	print("\n--- 测试 max_runtime_seconds pct ---")
	var g := Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 120)
	assert(_pct(g, {"elapsed_seconds": 0}) == 0.0, "elapsed=0 应 0.0")
	assert(_pct(g, {"elapsed_seconds": 60}) < 0.51 and _pct(g, {"elapsed_seconds": 60}) > 0.49, "elapsed=60 应 ~0.5")
	assert(_pct(g, {"elapsed_seconds": 120}) == 1.0, "elapsed=120 应 1.0")
	assert(_pct(g, {"elapsed_seconds": 200}) == 1.0, "elapsed=200 应钳制到 1.0")
	print("  ✓ max_runtime_seconds: 0/60/120/200 → 0/0.5/1.0/1.0")

func test_collect_n_cards_pct() -> void:
	print("\n--- 测试 collect_n_cards pct ---")
	var g := Goal.new(Goal.TYPE_COLLECT_N_CARDS, 15)
	assert(_pct(g, {"cards_collected": 0}) == 0.0, "cards=0 应 0.0")
	assert(_pct(g, {"cards_collected": 7}) < 0.47 and _pct(g, {"cards_collected": 7}) > 0.46, "cards=7 应 ~0.467")
	assert(_pct(g, {"cards_collected": 15}) == 1.0, "cards=15 应 1.0")
	print("  ✓ collect_n_cards: 0/7/15 → 0/0.467/1.0")

func test_trigger_n_chains_pct() -> void:
	print("\n--- 测试 trigger_n_chains pct ---")
	var g := Goal.new(Goal.TYPE_TRIGGER_N_CHAINS, 8)
	assert(_pct(g, {"chains_triggered": 0}) == 0.0)
	assert(_pct(g, {"chains_triggered": 4}) == 0.5, "chains=4 应 0.5")
	assert(_pct(g, {"chains_triggered": 8}) == 1.0)
	print("  ✓ trigger_n_chains: 0/4/8 → 0/0.5/1.0")

func test_reach_realm_pct() -> void:
	print("\n--- 测试 reach_realm_n pct ---")
	var g := Goal.new(Goal.TYPE_REACH_REALM_N, 3)
	assert(_pct(g, {"realm": 1}) < 0.34 and _pct(g, {"realm": 1}) > 0.33, "realm=1 应 ~0.333")
	assert(_pct(g, {"realm": 2}) < 0.67 and _pct(g, {"realm": 2}) > 0.66, "realm=2 应 ~0.667")
	assert(_pct(g, {"realm": 3}) == 1.0, "realm=3 应 1.0")
	print("  ✓ reach_realm_n: 1/2/3 → 0.333/0.667/1.0")

func test_visit_node_types_pct() -> void:
	print("\n--- 测试 visit_node_types pct ---")
	var g := Goal.new(Goal.TYPE_VISIT_NODE_TYPES, 4)
	assert(_pct(g, {"node_types_visited": []}) == 0.0, "空 array 应 0.0")
	assert(_pct(g, {"node_types_visited": [1, 2]}) == 0.5, "[1,2] 应 0.5")
	assert(_pct(g, {"node_types_visited": [1, 2, 3, 4, 5]}) == 1.0, "[1..5] 应钳制到 1.0")
	print("  ✓ visit_node_types: []/[1,2]/[1..5] → 0/0.5/1.0")

func test_loop_count_pct() -> void:
	print("\n--- 测试 loop_count_n pct ---")
	var g := Goal.new(Goal.TYPE_LOOP_COUNT_N, 50)
	assert(_pct(g, {"loop_count": 0}) == 0.0)
	assert(_pct(g, {"loop_count": 25}) == 0.5, "loop=25 应 0.5")
	assert(_pct(g, {"loop_count": 50}) == 1.0)
	assert(_pct(g, {"loop_count": 100}) == 1.0, "loop=100 应钳制到 1.0")
	print("  ✓ loop_count_n: 0/25/50/100 → 0/0.5/1.0/1.0")

# ===== 边界 =====

func test_pct_clamp_to_one_when_exceeded() -> void:
	print("\n--- 测试 pct 超过 1.0 时钳制 ---")
	# 已通过上面 9 type 的 "exceed" case 间接验证
	# 这里是显式汇总：
	var g_survive := Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 3)
	var g_realm := Goal.new(Goal.TYPE_REACH_REALM_N, 2)
	assert(_pct(g_survive, {"battles_won": 100}) == 1.0, "battles_won=100 应钳制到 1.0")
	assert(_pct(g_realm, {"realm": 5}) == 1.0, "realm=5 应钳制到 1.0")
	print("  ✓ pct 钳制工作正确")

func test_value_zero_returns_check_result() -> void:
	print("\n--- 测试 value=0 时返回 check 结果 ---")
	# value=0 的 Goal 通常是 boolean type (first_loss, complete_run)
	var g_first_loss := Goal.new(Goal.TYPE_FIRST_LOSS, 0)
	assert(_pct(g_first_loss, {"defeat": true}) == 1.0, "value=0 + check=true 应 1.0")
	assert(_pct(g_first_loss, {"defeat": false}) == 0.0, "value=0 + check=false 应 0.0")
	var g_complete := Goal.new(Goal.TYPE_COMPLETE_RUN, 0)
	assert(_pct(g_complete, {"victory": true, "defeat": false}) == 1.0)
	assert(_pct(g_complete, {"victory": false, "defeat": false}) == 0.0)
	print("  ✓ value=0 时 pct = check() 结果（0.0 或 1.0）")

func test_unknown_type_returns_zero() -> void:
	print("\n--- 测试未知 type 返回 0.0 ---")
	# 直接构造一个 unknown type 的 Goal（type 不在 VALID_TYPES）
	var g := Goal.new("invalid_type_xyz", 10)
	var pct: float = _pct(g, {"some_field": 100})
	assert(pct == 0.0, "未知 type 应返回 0.0，实际 %.3f" % pct)
	print("  ✓ 未知 type 防御正确")