## 测试运行器
## headless 模式下运行所有单元测试
## 用法: godot --headless --scene res://scenes/test_runner.tscn --quit
# implements: agent-infrastructure (非游戏设计文档)

extends Node

# 测试结果追踪
var total_tests := 0
var passed_tests := 0
var failed_tests := 0
var errors: Array = []
# 耗时统计 (P1.1 Phase 2 Step 5, 2026-07-05 18:00)
var _runner_start_ms: int = 0
var _suite_durations: Dictionary = {}  # suite_name -> ms

func _ready() -> void:
	_runner_start_ms = Time.get_ticks_msec()
	print("")
	print("╔══════════════════════════════════════╗")
	print("║   蜃都 · 单元测试运行器 (Headless)   ║")
	print("╚══════════════════════════════════════╝")
	print("")

	# 等待一帧让 autoload 就绪
	await get_tree().process_frame
	
	# 运行所有测试套件
	_run_test_suite("五行系统", "res://scripts/test/test_wuxing.gd")
	_run_test_suite("Actor 基类", "res://scripts/test/test_actor.gd")
	_run_test_suite("玩家系统", "res://scripts/test/test_player.gd")
	_run_test_suite("敌人系统", "res://scripts/test/test_enemy.gd")
	_run_test_suite("卡池加载", "res://scripts/test/test_card_pool.gd")
	_run_test_suite("灵力系统", "res://scripts/test/test_player_mana.gd")
	_run_test_suite("卡牌效果结构", "res://scripts/test/test_card_effects.gd")
	_run_test_suite("战斗契约验证", "res://scripts/test/test_combat_checklist.gd")
	_run_test_suite("全流程集成", "res://scripts/test/test_integration.gd")
	_run_test_suite("系统契约验证", "res://scripts/test/test_systems_checklist.gd")
	_run_test_suite("奖励契约验证", "res://scripts/test/test_reward_contract.gd")
	_run_test_suite("Starter Deck 真实化", "res://scripts/test/test_starter_deck.gd")
	_run_test_suite("EA 范围 45 张卡池", "res://scripts/test/test_ea_pool.gd")
	_run_test_suite("Shop Cosmetics-Only 防御", "res://scripts/test/test_shop_cosmetics_only.gd")
	_run_test_suite("Goal 数据结构 (P1.1 Phase 1)", "res://scripts/test/test_goal.gd")
	_run_test_suite("RunGoals Callback (P1.1 Step 3)", "res://scripts/test/test_run_goals_callback.gd")
	_run_test_suite("GoalTemplates (P1.1 Step 4)", "res://scripts/test/test_goal_templates.gd")
	_run_test_suite("load_goal_scene (P1.1 Step 2)", "res://scripts/test/test_load_goal_scene.gd")
	_run_test_suite("AIPlayer Goal Callback (P2.1)", "res://scripts/test/test_ai_player_goal_callback.gd")
	_run_test_suite("AIPlayer Auto-Select Goal Scene (P1.1 Phase 2)", "res://scripts/test/test_auto_select_goal_scene.gd")
	_run_test_suite("E2E Goal Pipeline (P1.1 Phase 2 Step 4)", "res://scripts/test/test_e2e_goal_pipeline.gd")
	_run_test_suite("Strategy Profile (P1.1 Phase 3)", "res://scripts/test/test_strategy_profile.gd")
	_run_test_suite("ExperienceMemory Schema (P1.1 Phase 2 H1)", "res://scripts/test/test_experience_memory_schema.gd")
	_run_test_suite("summarize_long_term (P1.1 Phase 3 H4)", "res://scripts/test/test_summarize_long_term.gd")
	_run_test_suite("compute_goal_pct (P1.1 Phase 2 H6)", "res://scripts/test/test_compute_goal_pct.gd")

	# 输出总结
	print("")
	print("╔══════════════════════════════════════╗")
	print("║           测试结果总结                ║")
	print("╠══════════════════════════════════════╣")
	print("║  总计: %d | 通过: %d | 失败: %d     ║" % [total_tests, passed_tests, failed_tests])
	print("╚══════════════════════════════════════╝")
	
	# 耗时统计 (Step 5, 2026-07-05 18:00)
	var total_elapsed_ms: int = Time.get_ticks_msec() - _runner_start_ms
	var total_seconds: float = float(total_elapsed_ms) / 1000.0
	print("║  总耗时: %.2f 秒                       ║" % total_seconds)
	# 打印 top-3 最慢 suite
	var sorted_suites: Array = _suite_durations.keys()
	sorted_suites.sort_custom(func(a, b): return _suite_durations[a] > _suite_durations[b])
	if sorted_suites.size() > 0:
		print("")
		print("║  最慢 3 个 suite:                   ║")
		for i in range(min(3, sorted_suites.size())):
			var suite_name = sorted_suites[i]
			var ms: int = int(_suite_durations[suite_name])
			print("║    %.2fs  %s" % [float(ms) / 1000.0, suite_name])

	if failed_tests > 0:
		print("")
		print("失败详情:")
		for err in errors:
			print("  ❌ %s" % err)
		print("")
		# 输出 JSON 格式结果供脚本解析 (含耗时)
		print("TEST_RESULT_JSON:%s" % JSON.stringify({
			"success": false,
			"total": total_tests,
			"passed": passed_tests,
			"failed": failed_tests,
			"errors": errors,
			"total_ms": total_elapsed_ms,
			"suite_durations": _suite_durations,
		}))
	else:
		print("")
		print("TEST_RESULT_JSON:%s" % JSON.stringify({
			"success": true,
			"total": total_tests,
			"passed": passed_tests,
			"failed": failed_tests,
			"errors": [],
			"total_ms": total_elapsed_ms,
			"suite_durations": _suite_durations,
		}))
	
	# 退出
	get_tree().quit(0 if failed_tests == 0 else 1)

func _run_test_suite(suite_name: String, script_path: String) -> void:
	print("━━━ %s ━━━" % suite_name)

	var script = load(script_path)
	if script == null:
		_record_fail(suite_name, "无法加载脚本: %s" % script_path)
		return

	var instance = script.new()
	if instance == null or not instance is Node:
		_record_fail(suite_name, "无法实例化脚本")
		if instance: instance.free()
		return

	add_child(instance)

	# 耗时统计 (Step 5, 2026-07-05 18:00)
	var suite_start_ms: int = Time.get_ticks_msec()

	# 运行测试
	if instance.has_method("run_all_tests"):
		instance.run_all_tests()
		var suite_ms: int = Time.get_ticks_msec() - suite_start_ms
		_suite_durations[suite_name] = suite_ms
		_record_pass(suite_name, suite_ms)
	else:
		_record_fail(suite_name, "脚本没有 run_all_tests() 方法")

	instance.free()

func _record_pass(suite_name: String, duration_ms: int = 0) -> void:
	total_tests += 1
	passed_tests += 1
	if duration_ms > 0:
		print("  ✅ %s 通过 (%.2fs)" % [suite_name, float(duration_ms) / 1000.0])
	else:
		print("  ✅ %s 通过" % suite_name)

func _record_fail(suite_name: String, reason: String) -> void:
	total_tests += 1
	failed_tests += 1
	errors.append("%s: %s" % [suite_name, reason])
	print("  ❌ %s 失败: %s" % [suite_name, reason])
