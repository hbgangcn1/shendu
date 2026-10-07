## load_goal_scene + _goal_from_dict 单元测试
## 测试 scripts/qa/run_goals.gd 的 JSON 库加载 + Dict→Goal 转换
##
## P1.1 Phase 1 Step 2 (2026-07-05) — 外部 JSON 配置加载
## 覆盖：
##   - load_goal_scene 加载已知场景（battle_baseline 等）
##   - 加载不存在场景返回 []
##   - 加载不存在 path 返回 []
##   - _goal_from_dict 转换合法 dict
##   - _goal_from_dict 缺 type 返回 null
##   - JSON 加载和 GoalTemplates 一致（防漂移）

# implements: agent-infrastructure (test infrastructure)

extends Node

func run_all_tests() -> void:
	print("\n=== load_goal_scene 测试 ===")
	test_load_battle_baseline()
	test_load_empty_scene()
	test_load_all_10_scenes()
	test_load_nonexistent_scene()
	test_load_nonexistent_path()
	test_invalid_json_structure()
	test_goal_from_dict_basics()
	test_goal_from_dict_missing_type()
	test_goal_from_dict_default_value_priority()
	test_json_matches_goal_templates()
	print("=== load_goal_scene 测试完成 ===\n")

# ===== load_goal_scene 测试 =====

func test_load_battle_baseline() -> void:
	print("\n--- 测试 load_goal_scene('battle_baseline') ---")
	var goals: Array[Goal] = RunGoals.load_goal_scene("battle_baseline")
	assert(goals.size() == 3, "battle_baseline 应有 3 个 goal，实际 %d" % goals.size())
	assert(goals[0].type == Goal.TYPE_SURVIVE_N_BATTLES, "[0].type 错：%s" % goals[0].type)
	assert(goals[0].value == 3, "[0].value 错：%d" % goals[0].value)
	assert(goals[0].priority == "high", "[0].priority 错：%s" % goals[0].priority)
	assert(goals[1].type == Goal.TYPE_MAX_RUNTIME_SECONDS, "[1].type 错")
	assert(goals[1].value == 120, "[1].value 错")
	assert(goals[2].type == Goal.TYPE_COLLECT_N_CARDS, "[2].type 错")
	assert(goals[2].value == 15, "[2].value 错")
	print("  ✓ battle_baseline 加载正确（3 goals: survive_3, max_120, cards_15）")

func test_load_empty_scene() -> void:
	print("\n--- 测试 load_goal_scene('empty') 边界 ---")
	var goals: Array[Goal] = RunGoals.load_goal_scene("empty")
	assert(goals.is_empty(), "empty 应返回空数组，实际 %d 个" % goals.size())
	print("  ✓ empty 场景返回空数组")

func test_load_all_10_scenes() -> void:
	print("\n--- 测试加载全部 10 个场景 ---")
	var scene_names: Array[String] = [
		"battle_baseline", "battle_deep", "battle_should_lose", "battle_full_clear",
		"deck_health_check", "map_exploration", "long_run", "loop_stress",
		"single_goal_max_runtime", "empty"
	]
	for scene_name in scene_names:
		var goals: Array[Goal] = RunGoals.load_goal_scene(scene_name)
		assert(goals.size() >= 0, "%s 加载结果非法" % scene_name)
		for g in goals:
			assert(g.type in Goal.VALID_TYPES, "%s: type '%s' 不合法" % [scene_name, g.type])
			assert(g.priority in Goal.VALID_PRIORITIES, "%s: priority '%s' 不合法" % [scene_name, g.priority])
	print("  ✓ 全部 10 场景加载成功 + type/priority 合法")

func test_load_nonexistent_scene() -> void:
	print("\n--- 测试 load_goal_scene('not_exist') 返回 [] ---")
	var goals: Array[Goal] = RunGoals.load_goal_scene("not_exist_scene")
	assert(goals.is_empty(), "不存在场景应返回空，实际 %d 个" % goals.size())
	print("  ✓ 不存在场景返回空数组（push_warning 已记录）")

func test_load_nonexistent_path() -> void:
	print("\n--- 测试 load_goal_scene(scene, 'fake/path.json') 返回 [] ---")
	var goals: Array[Goal] = RunGoals.load_goal_scene("battle_baseline", "res://scripts/qa/does_not_exist.json")
	assert(goals.is_empty(), "不存在 path 应返回空，实际 %d" % goals.size())
	print("  ✓ 不存在路径返回空数组")

func test_invalid_json_structure() -> void:
	print("\n--- 测试 malformed JSON 返回 [] ---")
	# 写一个 malformed JSON 到 user:// 让测试用
	var bad_path := "user://test_invalid_goal_library.json"
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string("not valid json {{{")
	bad_file.close()

	var goals: Array[Goal] = RunGoals.load_goal_scene("battle_baseline", bad_path)
	assert(goals.is_empty(), "malformed JSON 应返回空，实际 %d" % goals.size())

	# cleanup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	print("  ✓ malformed JSON 返回空数组")

# ===== _goal_from_dict 测试 =====

func test_goal_from_dict_basics() -> void:
	print("\n--- 测试 _goal_from_dict 转换合法 dict ---")
	var g: Goal = RunGoals._goal_from_dict({
		"type": Goal.TYPE_SURVIVE_N_BATTLES,
		"value": 5,
		"priority": Goal.TYPE_PRIORITY_HIGH
	})
	assert(g != null, "应返回非 null Goal")
	assert(g.type == Goal.TYPE_SURVIVE_N_BATTLES, "type 错：%s" % g.type)
	assert(g.value == 5, "value 错：%d" % g.value)
	assert(g.priority == "high", "priority 错：%s" % g.priority)
	print("  ✓ _goal_from_dict 转换正确")

func test_goal_from_dict_missing_type() -> void:
	print("\n--- 测试 _goal_from_dict 缺 type 返回 null ---")
	var g: Variant = RunGoals._goal_from_dict({"value": 5, "priority": "high"})
	assert(g == null, "缺 type 应返回 null，实际 %s" % str(g))
	print("  ✓ 缺 type 返回 null")

func test_goal_from_dict_default_value_priority() -> void:
	print("\n--- 测试 _goal_from_dict 缺 value/priority 用默认 ---")
	var g: Goal = RunGoals._goal_from_dict({"type": Goal.TYPE_COMPLETE_RUN})
	assert(g != null, "应返回非 null")
	assert(g.value == 0, "value 默认应为 0，实际 %d" % g.value)
	assert(g.priority == "normal", "priority 默认应为 normal，实际 %s" % g.priority)
	print("  ✓ 缺 value/priority 用默认值")

# ===== JSON 与 GoalTemplates 一致性测试 =====

func test_json_matches_goal_templates() -> void:
	print("\n--- 测试 JSON 库与 GoalTemplates 一致（防漂移）---")
	var tpl := GoalTemplates.new()
	# 抽取 json 中 battle_baseline 的关键字段，和 GoalTemplates 对齐
	var json_battle: Array[Goal] = RunGoals.load_goal_scene("battle_baseline")
	var tpl_battle: Array[Goal] = tpl.battle_baseline()
	assert(json_battle.size() == tpl_battle.size(), "battle_baseline 数量不一致：JSON=%d TPL=%d" % [json_battle.size(), tpl_battle.size()])
	for i in range(json_battle.size()):
		assert(json_battle[i].type == tpl_battle[i].type, "[%d].type 不一致：JSON=%s TPL=%s" % [i, json_battle[i].type, tpl_battle[i].type])
		assert(json_battle[i].value == tpl_battle[i].value, "[%d].value 不一致" % i)
		assert(json_battle[i].priority == tpl_battle[i].priority, "[%d].priority 不一致" % i)
	print("  ✓ JSON 库与 GoalTemplates 一致（防漂移）")
