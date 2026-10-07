## Goal 单元测试
## 测试 scripts/qa/goal.gd 的 9 种 Goal type × check(stats) 判定
##
## P1.1 Phase 1 Step 1（2026-07-05）：拆分 Goal class 后首次单元测
## 覆盖：
##   - 9 种 Goal type 的 _describe() 输出正确
##   - 9 种 type 的 check() 在 true/false 各 1 case
##   - priority 常量 + VALID_TYPES / VALID_PRIORITIES
##   - is_valid() / to_dict() 工具方法
##
## 不覆盖：
##   - RunGoals.gd 的状态机（已在 ai_player.gd 端到端覆盖）

# implements: agent-infrastructure (test infrastructure)
# implements_philosophy: rule_5_real_agency

extends Node

func run_all_tests() -> void:
	print("\n=== Goal 测试 ===")
	test_goal_constants()
	test_describe_all_types()
	test_check_survive_n_battles()
	test_check_complete_run()
	test_check_first_loss()
	test_check_collect_n_cards()
	test_check_trigger_n_chains()
	test_check_reach_realm_n()
	test_check_visit_node_types()
	test_check_max_runtime_seconds()
	test_check_loop_count_n()
	test_is_valid()
	test_to_dict()
	# P1.1 Phase 1 Step 1.5 (2026-07-05 17:30): missing-field + invalid + value=0 + multi-goal
	test_missing_field_defaults()
	test_invalid_type_returns_false()
	test_value_zero_boundary()
	test_multi_goal_priority_arbitration()
	print("=== Goal 测试完成 ===\n")

# ===== 常量测试 =====

func test_goal_constants() -> void:
	print("\n--- 测试 Goal 类型/优先级常量 ---")
	assert(Goal.TYPE_SURVIVE_N_BATTLES == "survive_n_battles", "TYPE_SURVIVE_N_BATTLES 值错")
	assert(Goal.TYPE_COMPLETE_RUN == "complete_run", "TYPE_COMPLETE_RUN 值错")
	assert(Goal.TYPE_FIRST_LOSS == "first_loss", "TYPE_FIRST_LOSS 值错")
	assert(Goal.TYPE_COLLECT_N_CARDS == "collect_n_cards", "TYPE_COLLECT_N_CARDS 值错")
	assert(Goal.TYPE_TRIGGER_N_CHAINS == "trigger_n_chains", "TYPE_TRIGGER_N_CHAINS 值错")
	assert(Goal.TYPE_REACH_REALM_N == "reach_realm_n", "TYPE_REACH_REALM_N 值错")
	assert(Goal.TYPE_VISIT_NODE_TYPES == "visit_node_types", "TYPE_VISIT_NODE_TYPES 值错")
	assert(Goal.TYPE_MAX_RUNTIME_SECONDS == "max_runtime_seconds", "TYPE_MAX_RUNTIME_SECONDS 值错")
	assert(Goal.TYPE_LOOP_COUNT_N == "loop_count_n", "TYPE_LOOP_COUNT_N 值错")

	assert(Goal.TYPE_PRIORITY_HIGH == "high", "TYPE_PRIORITY_HIGH 值错")
	assert(Goal.TYPE_PRIORITY_NORMAL == "normal", "TYPE_PRIORITY_NORMAL 值错")
	assert(Goal.TYPE_PRIORITY_LOW == "low", "TYPE_PRIORITY_LOW 值错")

	assert(Goal.VALID_TYPES.size() == 9, "VALID_TYPES 应有 9 项，实际 %d" % Goal.VALID_TYPES.size())
	assert(Goal.VALID_PRIORITIES.size() == 3, "VALID_PRIORITIES 应有 3 项，实际 %d" % Goal.VALID_PRIORITIES.size())
	print("  ✓ Goal 常量正确（9 types + 3 priorities）")

# ===== _describe() 测试 =====

func test_describe_all_types() -> void:
	print("\n--- 测试 _describe() 对 9 种 type 的输出 ---")
	var cases := [
		[Goal.TYPE_SURVIVE_N_BATTLES, 3, "完成 3 场战斗"],
		[Goal.TYPE_COMPLETE_RUN, 0, "通关或被击败"],
		[Goal.TYPE_FIRST_LOSS, 0, "第一次战斗失败"],
		[Goal.TYPE_COLLECT_N_CARDS, 15, "卡牌池达到 15 张"],
		[Goal.TYPE_TRIGGER_N_CHAINS, 5, "触发 5 次五行相生链"],
		[Goal.TYPE_REACH_REALM_N, 3, "进入第 3 个境界"],
		[Goal.TYPE_VISIT_NODE_TYPES, 4, "访问 4 种节点类型"],
		[Goal.TYPE_MAX_RUNTIME_SECONDS, 120, "运行上限 120 秒"],
		[Goal.TYPE_LOOP_COUNT_N, 10, "循环次数达到 10"],
	]
	for case in cases:
		var g := Goal.new(case[0], case[1])
		assert(g.description == case[2], "%s: 期望 '%s'，实际 '%s'" % [case[0], case[2], g.description])
	print("  ✓ 9 种 type 的 _describe() 输出正确")

# ===== check() 测试：每种 type × true/false 各 1 case =====

func test_check_survive_n_battles() -> void:
	print("\n--- 测试 check() survive_n_battles ---")
	var g := Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 3)
	assert(not g.check({"battles_won": 2}), "battles_won=2 < 3 应 false")
	assert(g.check({"battles_won": 3}), "battles_won=3 >= 3 应 true")
	assert(g.check({"battles_won": 5}), "battles_won=5 >= 3 应 true")
	assert(not g.check({}), "空 stats 应 false（battles_won 默认 0）")
	print("  ✓ survive_n_battles 判定正确")

func test_check_complete_run() -> void:
	print("\n--- 测试 check() complete_run ---")
	var g := Goal.new(Goal.TYPE_COMPLETE_RUN)
	assert(not g.check({"victory": false, "defeat": false}), "都 false 应 false")
	assert(g.check({"victory": true, "defeat": false}), "victory=true 应 true")
	assert(g.check({"victory": false, "defeat": true}), "defeat=true 应 true")
	print("  ✓ complete_run 判定正确")

func test_check_first_loss() -> void:
	print("\n--- 测试 check() first_loss ---")
	var g := Goal.new(Goal.TYPE_FIRST_LOSS)
	assert(not g.check({"defeat": false}), "defeat=false 应 false")
	assert(g.check({"defeat": true}), "defeat=true 应 true")
	print("  ✓ first_loss 判定正确")

func test_check_collect_n_cards() -> void:
	print("\n--- 测试 check() collect_n_cards ---")
	var g := Goal.new(Goal.TYPE_COLLECT_N_CARDS, 15)
	assert(not g.check({"cards_collected": 14}), "14 < 15 应 false")
	assert(g.check({"cards_collected": 15}), "15 >= 15 应 true")
	print("  ✓ collect_n_cards 判定正确")

func test_check_trigger_n_chains() -> void:
	print("\n--- 测试 check() trigger_n_chains ---")
	var g := Goal.new(Goal.TYPE_TRIGGER_N_CHAINS, 5)
	assert(not g.check({"chains_triggered": 4}), "4 < 5 应 false")
	assert(g.check({"chains_triggered": 5}), "5 >= 5 应 true")
	print("  ✓ trigger_n_chains 判定正确")

func test_check_reach_realm_n() -> void:
	print("\n--- 测试 check() reach_realm_n ---")
	var g := Goal.new(Goal.TYPE_REACH_REALM_N, 3)
	assert(not g.check({"realm": 2}), "realm=2 < 3 应 false")
	assert(g.check({"realm": 3}), "realm=3 >= 3 应 true")
	print("  ✓ reach_realm_n 判定正确")

func test_check_visit_node_types() -> void:
	print("\n--- 测试 check() visit_node_types ---")
	var g := Goal.new(Goal.TYPE_VISIT_NODE_TYPES, 3)
	assert(not g.check({"node_types_visited": [1, 2]}), "2 种 < 3 应 false")
	assert(g.check({"node_types_visited": [1, 2, 3]}), "3 种 >= 3 应 true")
	assert(g.check({"node_types_visited": [1, 2, 3, 4]}), "4 种 >= 3 应 true")
	assert(not g.check({"node_types_visited": []}), "空数组 < 3 应 false")
	print("  ✓ visit_node_types 判定正确")

func test_check_max_runtime_seconds() -> void:
	print("\n--- 测试 check() max_runtime_seconds ---")
	var g := Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 120)
	assert(not g.check({"elapsed_seconds": 119}), "119 < 120 应 false")
	assert(g.check({"elapsed_seconds": 120}), "120 >= 120 应 true")
	print("  ✓ max_runtime_seconds 判定正确")

func test_check_loop_count_n() -> void:
	print("\n--- 测试 check() loop_count_n ---")
	var g := Goal.new(Goal.TYPE_LOOP_COUNT_N, 10)
	assert(not g.check({"loop_count": 9}), "9 < 10 应 false")
	assert(g.check({"loop_count": 10}), "10 >= 10 应 true")
	print("  ✓ loop_count_n 判定正确")

# ===== 工具方法 =====

func test_is_valid() -> void:
	print("\n--- 测试 is_valid() ---")
	assert(Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 3).is_valid(), "合法 type+priority 应 valid")
	assert(Goal.new(Goal.TYPE_COMPLETE_RUN).is_valid(), "合法 type 应 valid")
	assert(not Goal.new("unknown_type", 0).is_valid(), "未知 type 应 invalid")
	assert(not Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 0, "ultra").is_valid(), "未知 priority 应 invalid")
	print("  ✓ is_valid() 判定正确")

func test_to_dict() -> void:
	print("\n--- 测试 to_dict() ---")
	var g := Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 3, Goal.TYPE_PRIORITY_HIGH)
	g.completed = true
	var d := g.to_dict()
	assert(d["type"] == Goal.TYPE_SURVIVE_N_BATTLES, "to_dict type 错")
	assert(d["value"] == 3, "to_dict value 错")
	assert(d["priority"] == Goal.TYPE_PRIORITY_HIGH, "to_dict priority 错")
	assert(d["completed"] == true, "to_dict completed 错")
	assert(d["description"] == "完成 3 场战斗", "to_dict description 错")
	print("  ✓ to_dict() 序列化正确")

# ===== P1.1 Phase 1 Step 1.5 (2026-07-05 17:30): missing-field + invalid type + multi-goal 补全 =====

## missing-field 显式断言：8/9 type 缺 case（survive_n_battles 已有）
## check() 用 int(stats.get(xxx, 0)) default 隐式兜底，但显式断言更稳
func test_missing_field_defaults() -> void:
	print("\n--- 测试 missing-field 显式断言 (8 type) ---")
	assert(not Goal.new(Goal.TYPE_COMPLETE_RUN, 0).check({}), "complete_run 空 stats 应 false")
	assert(not Goal.new(Goal.TYPE_FIRST_LOSS, 0).check({}), "first_loss 空 stats 应 false")
	assert(not Goal.new(Goal.TYPE_COLLECT_N_CARDS, 15).check({}), "collect_n_cards 空 stats 应 false")
	assert(not Goal.new(Goal.TYPE_TRIGGER_N_CHAINS, 5).check({}), "trigger_n_chains 空 stats 应 false")
	assert(not Goal.new(Goal.TYPE_REACH_REALM_N, 3).check({}), "reach_realm_n 空 stats 应 false")
	assert(not Goal.new(Goal.TYPE_VISIT_NODE_TYPES, 3).check({}), "visit_node_types 空 stats 应 false")
	assert(not Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 120).check({}), "max_runtime_seconds 空 stats 应 false")
	assert(not Goal.new(Goal.TYPE_LOOP_COUNT_N, 10).check({}), "loop_count_n 空 stats 应 false")
	print("  ✓ 8/8 type missing-field 判定正确")

## 非法 type 行为：check() 应 return false (match default case)
func test_invalid_type_returns_false() -> void:
	print("\n--- 测试非法 type check() 返回 false ---")
	var g := Goal.new("totally_invalid_type", 1)
	assert(not g.check({"any_key": 100}), "非法 type 应 false")
	assert(not g.check({}), "非法 type + 空 stats 应 false")
	assert(not g.is_valid(), "非法 type is_valid 应 false")
	print("  ✓ 非法 type 行为正确（check=false, is_valid=false）")

## value=0 边界：0 >= 0 应 true
func test_value_zero_boundary() -> void:
	print("\n--- 测试 value=0 边界 (0 >= 0 应 true) ---")
	assert(Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 0).check({}), "survive_0 + 空 stats 应 true")
	assert(Goal.new(Goal.TYPE_COLLECT_N_CARDS, 0).check({}), "collect_0 + 空 stats 应 true")
	assert(Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 0).check({}), "runtime_0 + 空 stats 应 true")
	assert(Goal.new(Goal.TYPE_LOOP_COUNT_N, 0).check({}), "loop_0 + 空 stats 应 true")
	print("  ✓ value=0 边界正确")

## 多 Goal priority arbitration
## 当前 RunGoals 不内置仲裁，但 Goal[] 排序测试确保 priority 字段可比较
## 未来若加 GetHighestPriorityGoal()，基础数据已就位
func test_multi_goal_priority_arbitration() -> void:
	print("\n--- 测试多 Goal priority 排序基础 ---")
	var goals: Array = []
	goals.append(Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 1, Goal.TYPE_PRIORITY_LOW))
	goals.append(Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 1, Goal.TYPE_PRIORITY_HIGH))
	goals.append(Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 1, Goal.TYPE_PRIORITY_NORMAL))
	# 模拟排序: high > normal > low
	goals.sort_custom(func(a: Goal, b: Goal) -> bool:
		return _priority_rank(a.priority) > _priority_rank(b.priority))
	assert(goals[0].priority == Goal.TYPE_PRIORITY_HIGH, "排序后 [0] 应是 high")
	assert(goals[1].priority == Goal.TYPE_PRIORITY_NORMAL, "排序后 [1] 应是 normal")
	assert(goals[2].priority == Goal.TYPE_PRIORITY_LOW, "排序后 [2] 应是 low")
	print("  ✓ priority 排序正确 (high > normal > low)")

## helper: priority -> int rank (high=2, normal=1, low=0)
func _priority_rank(p: String) -> int:
	match p:
		Goal.TYPE_PRIORITY_HIGH: return 2
		Goal.TYPE_PRIORITY_NORMAL: return 1
		Goal.TYPE_PRIORITY_LOW: return 0
		_: return -1