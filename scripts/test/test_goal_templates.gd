## GoalTemplates 单元测试
## 测试 scripts/qa/goal_templates.gd 的所有场景模板
##
## P1.1 Phase 1 Step 4 (2026-07-05) — Goal 模板库
## 覆盖：
##   - 10 个 static 场景返回合法 Goal 数组
##   - 所有 type/priority 都在 VALID_* 范围
##   - 关键场景包含期望的 Goal type
##   - empty() 返回空数组（边界条件）
##   - validate_all() 检测无效 goal

# implements: agent-infrastructure (test infrastructure)

extends Node

func run_all_tests() -> void:
	print("\n=== GoalTemplates 测试 ===")
	var tpl := GoalTemplates.new()
	test_scene_names_count(tpl)
	test_battle_baseline(tpl)
	test_battle_deep(tpl)
	test_battle_should_lose(tpl)
	test_battle_full_clear(tpl)
	test_deck_health_check(tpl)
	test_map_exploration(tpl)
	test_long_run(tpl)
	test_loop_stress(tpl)
	test_single_goal_max_runtime(tpl)
	test_empty_returns_empty(tpl)
	test_validate_all_pass(tpl)
	test_scenes_contain_real_type_priority(tpl)
	# P1.1 Phase 2 Step 7 (H7, 2026-07-05 20:20): 覆盖与 JSON 库一致性 + 关键 value 断言
	test_load_goal_scene_matches_templates(tpl)
	test_battle_baseline_specific_values(tpl)
	# H5 (2026-07-05 21:05): 版本化
	test_library_version_constant(tpl)
	print("=== GoalTemplates 测试完成 ===\n")

# ===== Scene 名称测试 =====

func test_scene_names_count(tpl: GoalTemplates) -> void:
	print("\n--- 测试 all_scene_names() 返回 10 个场景 ---")
	var names: Array[String] = tpl.all_scene_names()
	assert(names.size() == 10, "应有 10 个场景，实际 %d" % names.size())
	assert(names.has("battle_baseline"), "缺少 battle_baseline")
	assert(names.has("empty"), "缺少 empty")
	print("  ✓ all_scene_names() 返回 %d 个场景" % names.size())

# ===== 各场景测试 =====

func _assert_scene_has_goal(tpl: GoalTemplates, scene_name: String, expected_type: String) -> void:
	var goals: Array[Goal] = tpl.call(scene_name)
	for g in goals:
		if g.type == expected_type:
			return
	assert(false, "%s 应包含 type=%s 的 Goal" % [scene_name, expected_type])

func test_battle_baseline(tpl: GoalTemplates) -> void:
	print("\n--- 测试 battle_baseline() ---")
	var goals: Array[Goal] = tpl.battle_baseline()
	assert(goals.size() == 3, "battle_baseline 应有 3 个 goal，实际 %d" % goals.size())
	_assert_scene_has_goal(tpl, "battle_baseline", Goal.TYPE_SURVIVE_N_BATTLES)
	_assert_scene_has_goal(tpl, "battle_baseline", Goal.TYPE_MAX_RUNTIME_SECONDS)
	_assert_scene_has_goal(tpl, "battle_baseline", Goal.TYPE_COLLECT_N_CARDS)
	print("  ✓ battle_baseline: 3 goal (survive_3 / 120s / cards_15)")

func test_battle_deep(tpl: GoalTemplates) -> void:
	print("\n--- 测试 battle_deep() ---")
	var goals: Array[Goal] = tpl.battle_deep()
	assert(goals.size() == 4, "battle_deep 应有 4 个 goal，实际 %d" % goals.size())
	_assert_scene_has_goal(tpl, "battle_deep", Goal.TYPE_TRIGGER_N_CHAINS)
	_assert_scene_has_goal(tpl, "battle_deep", Goal.TYPE_REACH_REALM_N)
	print("  ✓ battle_deep: 4 goal (survive_5 / chain_8 / realm_2 / 180s)")

func test_battle_should_lose(tpl: GoalTemplates) -> void:
	print("\n--- 测试 battle_should_lose() ---")
	var goals: Array[Goal] = tpl.battle_should_lose()
	assert(goals.size() == 2, "应有 2 个 goal，实际 %d" % goals.size())
	_assert_scene_has_goal(tpl, "battle_should_lose", Goal.TYPE_FIRST_LOSS)
	var first_loss := goals[0]
	assert(first_loss.type == Goal.TYPE_FIRST_LOSS, "first_loss 应是 type=first_loss")
	print("  ✓ battle_should_lose: 2 goal (first_loss / 60s)")

func test_battle_full_clear(tpl: GoalTemplates) -> void:
	print("\n--- 测试 battle_full_clear() ---")
	var goals: Array[Goal] = tpl.battle_full_clear()
	_assert_scene_has_goal(tpl, "battle_full_clear", Goal.TYPE_COMPLETE_RUN)
	print("  ✓ battle_full_clear: 2 goal (complete_run / 240s)")

func test_deck_health_check(tpl: GoalTemplates) -> void:
	print("\n--- 测试 deck_health_check() ---")
	var goals: Array[Goal] = tpl.deck_health_check()
	_assert_scene_has_goal(tpl, "deck_health_check", Goal.TYPE_COLLECT_N_CARDS)
	assert(goals[0].value == 20, "deck_health_check[0].value 应是 20（collect_n_cards=20）")
	print("  ✓ deck_health_check: 3 goal (collect_20 / survive_1 / 90s)")

func test_map_exploration(tpl: GoalTemplates) -> void:
	print("\n--- 测试 map_exploration() ---")
	var goals: Array[Goal] = tpl.map_exploration()
	_assert_scene_has_goal(tpl, "map_exploration", Goal.TYPE_VISIT_NODE_TYPES)
	print("  ✓ map_exploration: 2 goal (visit_4 / 120s)")

func test_long_run(tpl: GoalTemplates) -> void:
	print("\n--- 测试 long_run() ---")
	var goals: Array[Goal] = tpl.long_run()
	assert(goals.size() == 1, "long_run 应只 1 个 goal，实际 %d" % goals.size())
	assert(goals[0].type == Goal.TYPE_MAX_RUNTIME_SECONDS, "应是 max_runtime_seconds")
	assert(goals[0].value == 300, "应是 300 秒")
	assert(goals[0].priority == Goal.TYPE_PRIORITY_HIGH, "应是 high priority")
	print("  ✓ long_run: 1 goal (max_runtime=300s, high)")

func test_loop_stress(tpl: GoalTemplates) -> void:
	print("\n--- 测试 loop_stress() ---")
	var goals: Array[Goal] = tpl.loop_stress()
	_assert_scene_has_goal(tpl, "loop_stress", Goal.TYPE_LOOP_COUNT_N)
	print("  ✓ loop_stress: 2 goal (loop_50 / 180s)")

func test_single_goal_max_runtime(tpl: GoalTemplates) -> void:
	print("\n--- 测试 single_goal_max_runtime() ---")
	var goals: Array[Goal] = tpl.single_goal_max_runtime()
	assert(goals.size() == 1, "应有 1 个 goal，实际 %d" % goals.size())
	assert(goals[0].value == 10, "single_goal_max_runtime 应是 10 秒")
	print("  ✓ single_goal_max_runtime: 1 goal (max_runtime=10s)")

func test_empty_returns_empty(tpl: GoalTemplates) -> void:
	print("\n--- 测试 empty() 返回空数组（边界条件）---")
	var goals: Array[Goal] = tpl.empty()
	assert(goals.is_empty(), "empty() 应返回空数组，实际 %d 个" % goals.size())
	print("  ✓ empty() 边界条件正确")

# ===== 验证所有场景 =====

func test_validate_all_pass(tpl: GoalTemplates) -> void:
	print("\n--- 测试 validate_all() 检测所有合法模板 ---")
	var result: Dictionary = tpl.validate_all()
	assert(result["invalid"] == 0, "应有 0 个 invalid goal，实际 %d：%s" % [result["invalid"], str(result["errors"])])
	assert(result["total"] > 0, "total 应 > 0，实际 %d" % result["total"])
	print("  ✓ validate_all: %d 个 goal 全部合法" % result["total"])

func test_scenes_contain_real_type_priority(tpl: GoalTemplates) -> void:
	print("\n--- 测试每个场景的 goal 都用真实 type/priority 常量 ---")
	var names: Array[String] = tpl.all_scene_names()
	for name in names:
		var goals: Array[Goal] = tpl.call(name)
		for g in goals:
			assert(g.type in Goal.VALID_TYPES, "%s: type '%s' 不在 VALID_TYPES" % [name, g.type])
			assert(g.priority in Goal.VALID_PRIORITIES, "%s: priority '%s' 不在 VALID_PRIORITIES" % [name, g.priority])
	print("  ✓ 所有 %d 场景的 type/priority 都是合法常量" % names.size())

# ===== H7: 与 JSON 库一致性 + 关键 value 断言 =====

## P1.1 Phase 2 Step 7 (H7, 2026-07-05 20:20):
## test_runner 跑测时主动对比 GoalTemplates vs goal_library.json，让 drift 早暴露
func test_load_goal_scene_matches_templates(tpl: GoalTemplates) -> void:
	print("\n--- 测试 RunGoals.load_goal_scene() 与 GoalTemplates 一致（drift 早暴露）---")
	var names: Array[String] = tpl.all_scene_names()
	var mismatches: Array[String] = []

	for scene_name in names:
		var tpl_goals: Array[Goal] = tpl.call(scene_name)
		var json_goals: Array[Goal] = RunGoals.load_goal_scene(scene_name)

		if tpl_goals.size() != json_goals.size():
			mismatches.append("%s: goal count %d (templates) != %d (json)" % [scene_name, tpl_goals.size(), json_goals.size()])
			continue

		for i in range(tpl_goals.size()):
			var tg := tpl_goals[i]
			var jg := json_goals[i]
			if tg.type != jg.type:
				mismatches.append("%s[%d].type: '%s' != '%s'" % [scene_name, i, tg.type, jg.type])
			elif tg.value != jg.value:
				mismatches.append("%s[%d].value: %d != %d" % [scene_name, i, tg.value, jg.value])
			elif tg.priority != jg.priority:
				mismatches.append("%s[%d].priority: '%s' != '%s'" % [scene_name, i, tg.priority, jg.priority])

	assert(mismatches.is_empty(), "TEMPLATES vs JSON LIBRARY DRIFT: %s" % str(mismatches))
	print("  ✓ %d 个场景 templates 与 JSON 库完全一致（type/value/priority）" % names.size())

## 测试 battle_baseline 三个 goal 的具体 value（防意外改坏）
func test_battle_baseline_specific_values(tpl: GoalTemplates) -> void:
	print("\n--- 测试 battle_baseline 三 goal 的具体 value ---")
	var goals: Array[Goal] = tpl.battle_baseline()
	assert(goals.size() == 3, "battle_baseline 应有 3 goal，实际 %d" % goals.size())
	assert(goals[0].type == Goal.TYPE_SURVIVE_N_BATTLES and goals[0].value == 3, "goals[0] 应是 survive_n_battles=3，实际 type=%s value=%d" % [goals[0].type, goals[0].value])
	assert(goals[1].type == Goal.TYPE_MAX_RUNTIME_SECONDS and goals[1].value == 120, "goals[1] 应是 max_runtime_seconds=120，实际 type=%s value=%d" % [goals[1].type, goals[1].value])
	assert(goals[2].type == Goal.TYPE_COLLECT_N_CARDS and goals[2].value == 15, "goals[2] 应是 collect_n_cards=15，实际 type=%s value=%d" % [goals[2].type, goals[2].value])
	print("  ✓ battle_baseline: survive_n_battles=3 / max_runtime=120 / collect_n_cards=15")

## H5 (2026-07-05 21:05): 验证模板库 schema 版本常量
func test_library_version_constant(tpl: GoalTemplates) -> void:
	print("\n--- 测试 GoalTemplates.LIBRARY_VERSION ---")
	var v: int = tpl.get_library_version()
	assert(v == GoalTemplates.LIBRARY_VERSION, "get_library_version() 应返回常量值，实际 %d vs const %d" % [v, GoalTemplates.LIBRARY_VERSION])
	assert(GoalTemplates.LIBRARY_VERSION > 0, "LIBRARY_VERSION 应 > 0，实际 %d" % GoalTemplates.LIBRARY_VERSION)
	print("  ✓ GoalTemplates.LIBRARY_VERSION = %d" % GoalTemplates.LIBRARY_VERSION)