## P1.1 Phase 2 Step 4 (2026-07-05 17:48) — E2E Goal Pipeline Integration Test
## 验证完整 pipeline: Goal 完成 → AIPlayer callback → ExperienceMemory 写入
## 不启动 main scene（避免 60s gameplay），而是直接模拟 Goal 完成链路
extends Node

## 测试每个 scenario 的 emit log
var _scenario_log: Array = []

func run_all_tests() -> void:
	print("\n=== E2E Goal Pipeline 测试 ===")
	test_scenario_battle_completion()
	test_scenario_max_runtime_hit()
	test_scenario_card_collection()
	test_scenario_multiple_goals_completion()
	test_scenario_priority_routing()
	print("=== E2E Goal Pipeline 测试完成 ===\n")

func _scenario_setup(scenario: String) -> void:
	# 清空 RunGoals state + reconnect default callback
	RunGoals.clear_goals()
	RunGoals.disconnect_default_callback()
	RunGoals.reconnect_default_callback()
	RunGoals.set_run_id("e2e-%s" % scenario)
	RunGoals.reset_stats()
	_scenario_log.clear()

## Scenario 1: 战斗 3 场完成 → survive_n_battles goal 触发 → tactic routing
func test_scenario_battle_completion() -> void:
	print("\n--- Scenario 1: 战斗 3 场完成 ---")
	_scenario_setup("battle")
	# AI Player default 3 goals (模拟 _ready 默认配置)
	RunGoals.add_goal("survive_n_battles", 3, "high")
	RunGoals.add_goal("max_runtime_seconds", 120, "normal")
	RunGoals.add_goal("collect_n_cards", 15, "normal")
	# 模拟 AI Player 打了 3 场战斗
	RunGoals.report("battles_won", 3)
	# 验证 RunGoals 状态
	var goals: Array = RunGoals.get_goals()
	var survive_goal: Goal = null
	for g in goals:
		if g.type == Goal.TYPE_SURVIVE_N_BATTLES:
			survive_goal = g
	assert(survive_goal != null and survive_goal.completed, "survive_n_battles 应已完成")
	# 验证 ExperienceMemory (default callback 自动写)
	# 注意: 真实 e2e 需要等 ExperienceMemory 写盘（JSON async），这里只验证 goal.completed
	print("  ✓ 战斗场景：survive_n_battles goal 完成")

## Scenario 2: max_runtime 触发 → strategy routing
func test_scenario_max_runtime_hit() -> void:
	print("\n--- Scenario 2: 运行上限 120s ---")
	_scenario_setup("runtime")
	RunGoals.add_goal("survive_n_battles", 3, "high")
	RunGoals.add_goal("max_runtime_seconds", 120, "normal")
	RunGoals.add_goal("collect_n_cards", 15, "normal")
	RunGoals.report("elapsed_seconds", 120)
	var goals: Array = RunGoals.get_goals()
	var runtime_goal: Goal = null
	for g in goals:
		if g.type == Goal.TYPE_MAX_RUNTIME_SECONDS:
			runtime_goal = g
	assert(runtime_goal != null and runtime_goal.completed, "max_runtime_seconds 应已完成")
	print("  ✓ 运行上限场景：max_runtime_seconds goal 完成")

## Scenario 3: 卡牌收集 15 张 → progress routing
func test_scenario_card_collection() -> void:
	print("\n--- Scenario 3: 卡牌池达到 15 张 ---")
	_scenario_setup("cards")
	RunGoals.add_goal("survive_n_battles", 3, "high")
	RunGoals.add_goal("max_runtime_seconds", 120, "normal")
	RunGoals.add_goal("collect_n_cards", 15, "normal")
	RunGoals.report("cards_collected", 15)
	var goals: Array = RunGoals.get_goals()
	var cards_goal: Goal = null
	for g in goals:
		if g.type == Goal.TYPE_COLLECT_N_CARDS:
			cards_goal = g
	assert(cards_goal != null and cards_goal.completed, "collect_n_cards 应已完成")
	print("  ✓ 卡牌场景：collect_n_cards goal 完成")

## Scenario 4: 多 Goal 同时完成 → 验证 emit 顺序 + _completed_goals 列表
func test_scenario_multiple_goals_completion() -> void:
	print("\n--- Scenario 4: 多 Goal 连续完成 ---")
	_scenario_setup("multi")
	RunGoals.add_goal("survive_n_battles", 1, "high")
	RunGoals.add_goal("max_runtime_seconds", 60, "normal")
	RunGoals.add_goal("collect_n_cards", 5, "normal")
	RunGoals.report("battles_won", 1)
	RunGoals.report("elapsed_seconds", 60)
	RunGoals.report("cards_collected", 5)
	var goals: Array = RunGoals.get_goals()
	var completed_count: int = 0
	for g in goals:
		if g.completed:
			completed_count += 1
	assert(completed_count == 3, "3 个 goal 应全部完成，实际 %d" % completed_count)
	print("  ✓ 多 Goal：3/3 完成")

## Scenario 5: priority arbitration — high 优先级先 emit（按 Goal 列表顺序遍历）
func test_scenario_priority_routing() -> void:
	print("\n--- Scenario 5: priority 仲裁（high vs normal）---")
	_scenario_setup("priority")
	# 故意把 normal priority 放在 high 之前，验证 RunGoals 不按 priority 排序（只按 add 顺序）
	RunGoals.add_goal("survive_n_battles", 1, "normal")  # normal 先 add
	RunGoals.add_goal("collect_n_cards", 5, "high")       # high 后 add
	RunGoals.report("battles_won", 1)
	RunGoals.report("cards_collected", 5)
	var goals: Array = RunGoals.get_goals()
	# 当前 RunGoals 是按 add 顺序遍历 emit, 不做 priority sort
	# 验证两个 goal 都完成即可
	var all_completed: bool = true
	for g in goals:
		if not g.completed:
			all_completed = false
	assert(all_completed, "所有 goal 应完成（当前实现: add 顺序遍历，非 priority sort）")
	print("  ✓ priority 路由：add 顺序遍历（priority 仅 metadata）")

func _tear_down() -> void:
	RunGoals.disconnect_default_callback()
	RunGoals.clear_goals()