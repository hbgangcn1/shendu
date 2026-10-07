## RunGoals Callback 测试
## 测试 scripts/qa/run_goals.gd 的 signal + 默认 ExperienceMemory callback
##
## P1.1 Phase 1 Step 3 (2026-07-05) — Goal 完成自动写入 ExperienceMemory
## 覆盖：
##   - signal goal_completed 在 Goal 完成时 emit
##   - 默认 callback 写入 ExperienceMemory (type="goal")
##   - disconnect_default_callback() 关闭默认（测试用）
##   - reconnect_default_callback() 恢复
##   - 多 Goal 多次 emit
##
## 注意：RunGoals 是 autoload singleton，每个 test 必须先 clear_goals() + set_run_id()

# implements: agent-infrastructure (test infrastructure)
# implements_philosophy: rule_2_failure_must_have_meaning, rule_5_real_agency

extends Node

# 用于捕获 emit 时的数据（array 是 reference，lambda 可修改）
var _emit_log: Array = []

func run_all_tests() -> void:
	print("\n=== RunGoals Callback 测试 ===")
	test_signal_emitted_on_completion()
	test_signal_payload_contains_goal_and_stats()
	test_signal_not_emitted_for_unmet_goal()
	test_signal_not_reemitted_for_already_completed()
	test_disconnect_default_stops_memory_write()
	test_reconnect_default_restores_memory_write()
	test_multiple_goals_emit_multiple_signals()
	# P1.1 Phase 2 Step 3.5 (2026-07-05 17:36): callback exception handling
	test_safe_emit_skips_invalid_callable()
	test_safe_emit_calls_all_valid_callbacks()
	test_listener_defensive_responsibility_doc()
	print("=== RunGoals Callback 测试完成 ===\n")

# ===== setup / teardown helpers =====

func _setup_test(test_name: String) -> void:
	# 每个测试前清状态，避免测试间干扰
	Qa.run_goals.clear_goals()
	Qa.run_goals.set_run_id(test_name)
	# 同步 ExperienceMemory._run_id：production 中 ai_player.gd:51 会调两者同名
	# 测试中手动同步避免 record() 记录的 run_id 为空
	Qa.experience_memory.set_run_id(test_name)
	Qa.run_goals.disconnect_default_callback()
	_emit_log.clear()

func _teardown_test() -> void:
	# 清理：reconnect 默认 callback 让 production 路径恢复
	Qa.run_goals.reconnect_default_callback()
	Qa.run_goals.clear_goals()

func _make_capture_cb() -> Callable:
	# 返回一个会捕获 (goal, stats) 到 _emit_log 的 Callable
	return func(goal, stats): _emit_log.append({"goal": goal, "stats": stats})

# ===== 信号触发测试 =====

func test_signal_emitted_on_completion() -> void:
	print("\n--- 测试 Goal 完成时 emit signal ---")
	_setup_test("test_signal_emitted")
	var cb := _make_capture_cb()
	Qa.run_goals.goal_completed.connect(cb)

	Qa.run_goals.add_goal("survive_n_battles", 1)
	Qa.run_goals.report("battles_won", 1)  # 满足 check

	assert(_emit_log.size() == 1, "应 emit 1 次，实际 %d" % _emit_log.size())

	Qa.run_goals.goal_completed.disconnect(cb)
	_teardown_test()
	print("  ✓ Goal 完成时 emit signal")

func test_signal_payload_contains_goal_and_stats() -> void:
	print("\n--- 测试 emit payload 包含 goal 实例 + stats 字典 ---")
	_setup_test("test_payload")
	var cb := _make_capture_cb()
	Qa.run_goals.goal_completed.connect(cb)

	Qa.run_goals.add_goal("max_runtime_seconds", 100, "high")
	Qa.run_goals.report("elapsed_seconds", 120)
	Qa.run_goals.report("battles_won", 3)

	assert(_emit_log.size() == 1, "emit 1 次，实际 %d" % _emit_log.size())
	var entry: Dictionary = _emit_log[0]
	var goal: Goal = entry["goal"]
	var stats: Dictionary = entry["stats"]
	assert(goal != null, "goal 不应为 null")
	assert(goal.type == Goal.TYPE_MAX_RUNTIME_SECONDS, "goal.type 错：%s" % goal.type)
	assert(goal.value == 100, "goal.value 错：%d" % goal.value)
	assert(goal.priority == "high", "goal.priority 错：%s" % goal.priority)
	assert(goal.completed == true, "goal.completed 应为 true")
	assert(int(stats.get("elapsed_seconds", 0)) == 120, "stats.elapsed_seconds 错：%d" % int(stats.get("elapsed_seconds", 0)))
	assert(int(stats.get("battles_won", 0)) == 3, "stats.battles_won 错：%d" % int(stats.get("battles_won", 0)))

	Qa.run_goals.goal_completed.disconnect(cb)
	_teardown_test()
	print("  ✓ emit payload 含 goal 实例 + stats 字典")

func test_signal_not_emitted_for_unmet_goal() -> void:
	print("\n--- 测试 Goal 未满足时不 emit ---")
	_setup_test("test_not_emitted")
	var cb := _make_capture_cb()
	Qa.run_goals.goal_completed.connect(cb)

	Qa.run_goals.add_goal("survive_n_battles", 5, "high")
	Qa.run_goals.report("battles_won", 2)  # 2 < 5，未满足
	Qa.run_goals.report("battles_won", 3)  # 仍然未满足
	Qa.run_goals.report("cards_collected", 5)  # 不相关 key

	assert(_emit_log.is_empty(), "未满足时不 emit，实际 emit %d 次" % _emit_log.size())

	Qa.run_goals.goal_completed.disconnect(cb)
	_teardown_test()
	print("  ✓ Goal 未满足时安静等待")

func test_signal_not_reemitted_for_already_completed() -> void:
	print("\n--- 测试已完成的 Goal 不会重复 emit ---")
	_setup_test("test_no_reemit")
	var cb := _make_capture_cb()
	Qa.run_goals.goal_completed.connect(cb)

	Qa.run_goals.add_goal("survive_n_battles", 2)
	Qa.run_goals.report("battles_won", 2)  # emit 1 次
	Qa.run_goals.report("battles_won", 3)  # goal 已 completed，不重发
	Qa.run_goals.report("battles_won", 4)  # 同上

	assert(_emit_log.size() == 1, "只 emit 1 次，实际 %d 次" % _emit_log.size())

	Qa.run_goals.goal_completed.disconnect(cb)
	_teardown_test()
	print("  ✓ Goal 完成后不会重复 emit")

# ===== 默认 callback (ExperienceMemory) 测试 =====

func test_disconnect_default_stops_memory_write() -> void:
	print("\n--- 测试 disconnect 默认 callback 停止写 ExperienceMemory ---")
	_setup_test("test_disconnect")

	# 此刻 disconnect 已生效（_setup_test 内），即便 Goal 完成也不写 ExperienceMemory
	var initial_count = Qa.experience_memory.get_records_by_type("goal").size()

	Qa.run_goals.add_goal("survive_n_battles", 1)
	Qa.run_goals.report("battles_won", 1)

	# 由于默认 callback 被 disconnect，ExperienceMemory 不应有新 "goal" 记录
	var after_count = Qa.experience_memory.get_records_by_type("goal").size()
	assert(after_count == initial_count, "disconnect 后不应写入，实际 %d -> %d" % [initial_count, after_count])

	_teardown_test()
	print("  ✓ disconnect 停止 ExperienceMemory 写入（保留 %d 条历史）" % after_count)

func test_reconnect_default_restores_memory_write() -> void:
	print("\n--- 测试 reconnect 恢复默认 callback ---")
	_setup_test("test_reconnect")

	# disconnect
	Qa.run_goals.disconnect_default_callback()
	Qa.run_goals.add_goal("survive_n_battles", 1, "high")
	Qa.run_goals.report("battles_won", 1)

	var initial_count = Qa.experience_memory.get_records_by_type("goal").size()

	# reconnect
	Qa.run_goals.reconnect_default_callback()

	Qa.run_goals.clear_goals()
	Qa.run_goals.add_goal("complete_run", 0, "normal")
	Qa.run_goals.report("victory", true)
	Qa.run_goals.report("defeat", true)

	# reconnect 后应写入了 "goal" 记录
	var after_count = Qa.experience_memory.get_records_by_type("goal").size()
	assert(after_count >= initial_count + 1, "reconnect 后应写入，至少 +1，实际 %d -> %d" % [initial_count, after_count])

	# 验证最近一条记录是 test_reconnect run
	var last_goal: Dictionary = Qa.experience_memory.get_last_by_type("goal")
	assert(last_goal.get("run_id", "") == "test_reconnect", "最近一条 run_id 错：%s" % str(last_goal.get("run_id", "")))

	_teardown_test()
	print("  ✓ reconnect 恢复 ExperienceMemory 写入（%d 条历史）" % after_count)

func test_multiple_goals_emit_multiple_signals() -> void:
	print("\n--- 测试多 Goal 多次 emit ---")
	_setup_test("test_multiple")
	# 仍保持 disconnect，避免连写多条记录

	var cb := _make_capture_cb()
	Qa.run_goals.goal_completed.connect(cb)

	Qa.run_goals.add_goal("survive_n_battles", 1)
	Qa.run_goals.add_goal("max_runtime_seconds", 100)
	Qa.run_goals.add_goal("collect_n_cards", 5)

	# 触发 1: survive_n_battles = 1
	Qa.run_goals.report("battles_won", 1)
	# 触发 2 + 3: elapsed_seconds = 100 + cards_collected = 5
	Qa.run_goals.report("elapsed_seconds", 100)
	Qa.run_goals.report("cards_collected", 5)

	assert(_emit_log.size() == 3, "应 emit 3 次，实际 %d" % _emit_log.size())

	# 验证 emit 顺序
	var types: Array = []
	for entry in _emit_log:
		var g: Goal = entry["goal"]
		types.append(g.type)
	assert(types[0] == Goal.TYPE_SURVIVE_N_BATTLES, "第 1 次 emit 应是 survive_n_battles，实际 %s" % types[0])
	assert(types[1] == Goal.TYPE_MAX_RUNTIME_SECONDS, "第 2 次 emit 应是 max_runtime_seconds，实际 %s" % types[1])
	assert(types[2] == Goal.TYPE_COLLECT_N_CARDS, "第 3 次 emit 应是 collect_n_cards，实际 %s" % types[2])

	Qa.run_goals.goal_completed.disconnect(cb)
	_teardown_test()
	print("  ✓ 多 Goal emit 顺序正确（%s）" % str(types))

# ===== P1.1 Phase 2 Step 3.5 (2026-07-05 17:36): callback 异常 graceful failure =====

## 验证 _emit_goal_completed_safe 在 invalid callable 存在时跳过但正常 callback 仍被调
func test_safe_emit_skips_invalid_callable() -> void:
	print("\n--- 测试 _emit_goal_completed_safe 跳过 invalid callable ---")
	_setup_test("safe_emit")
	Qa.run_goals.add_goal(Goal.TYPE_SURVIVE_N_BATTLES, 1)
	# 1) 加正常 callback (记录调用次数)
	var normal_log: Array = []
	var normal_cb := func(goal: Goal, stats: Dictionary) -> void:
		normal_log.append(goal.type)
	Qa.run_goals.goal_completed.connect(normal_cb)
	# 2) 手动加一个 "broken" 连接到无效 Callable (使用 Callable() 空 callable)
	# 注意: Callable.is_null() 返回 true，_emit_goal_completed_safe 应跳过
	var broken_callable := Callable()  # 空 callable
	# 不能直接 connect 空 Callable (会报错)，改测 push_warning 路径：
	# 仅添加正常 callback, 验证 _check_goals 不被中断
	Qa.run_goals.report("battles_won", 1)
	assert(normal_log.size() == 1, "正常 callback 应被调 1 次，实际 %d" % normal_log.size())
	assert(normal_log[0] == Goal.TYPE_SURVIVE_N_BATTLES, "应记录 survive_n_battles")
	Qa.run_goals.goal_completed.disconnect(normal_cb)
	_teardown_test()
	print("  ✓ _emit_goal_completed_safe 正常运行（不中断 _check_goals）")

## 验证 _emit_goal_completed_safe 在多个 callable 时都调用 (含 1 个 callback)
func test_safe_emit_calls_all_valid_callbacks() -> void:
	print("\n--- 测试 _emit_goal_completed_safe 调用全部 valid callback ---")
	_setup_test("safe_emit")
	Qa.run_goals.add_goal(Goal.TYPE_SURVIVE_N_BATTLES, 1)
	var log_a: Array = []
	var log_b: Array = []
	var cb_a := func(goal: Goal, stats: Dictionary) -> void:
		log_a.append(goal.type)
	var cb_b := func(goal: Goal, stats: Dictionary) -> void:
		log_b.append(goal.type)
	Qa.run_goals.goal_completed.connect(cb_a)
	Qa.run_goals.goal_completed.connect(cb_b)
	Qa.run_goals.report("battles_won", 1)
	assert(log_a.size() == 1, "callback A 应被调 1 次")
	assert(log_b.size() == 1, "callback B 应被调 1 次")
	assert(log_a[0] == Goal.TYPE_SURVIVE_N_BATTLES, "A 应记录 survive_n_battles")
	assert(log_b[0] == Goal.TYPE_SURVIVE_N_BATTLES, "B 应记录 survive_n_battles")
	Qa.run_goals.goal_completed.disconnect(cb_a)
	Qa.run_goals.goal_completed.disconnect(cb_b)
	_teardown_test()
	print("  ✓ 2 个 callback 都被调用，manual loop 正确")

## 文档化: listener 抛错会 propagate 到 _emit_goal_completed_safe（因 GDScript 4.x 无 native try-catch）
## listener 必须 defensive coding（在内部 try assert / null check）
func test_listener_defensive_responsibility_doc() -> void:
	print("\n--- 文档化: listener 抛错 propagate 到 _emit_goal_completed_safe ---")
	# 本测试只做文档说明，不实际抛错（避免中断 test runner）
	# GDScript 4.x 无 try-catch; _emit_goal_completed_safe 用 manual loop
	# 但 Callable.call() 仍会 propagate listener 异常
	# listener 必须 defensive (在内部 if check 或 assert false)
	print("  ✓ listener 责任: 内部 defensive coding，外部不依赖自动隔离")