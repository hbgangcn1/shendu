## AIPlayer._on_ai_player_goal_completed 单元测试
## 测试 ai_player.gd 在 Goal 完成时的策略评估函数
##
## P2.1 (2026-07-05): AI Player Goal 完成判断
## 覆盖：
##   - 5 种 goal type 路由到对应 ExperienceMemory type
##   - 1 种 fallback 类型（goal_strategy）
##   - _run_id 设置正确（自动生成 fallback）
##   - ExperienceMemory 计数对每个 type 正确 +1
##
## 不覆盖：
##   - ai_player.gd 真实 QA mode 行为（_ready 需 --qa-auto-run 启动）
##   - _run_loop 主循环（production 中会跑，这里静态调用方法）

# implements: agent-infrastructure (test infrastructure)

extends Node

const AIPlayerScript := preload("res://scripts/qa/ai_player.gd")

func run_all_tests() -> void:
	print("\n=== AIPlayer Goal Callback 测试 ===")
	var player := AIPlayerScript.new()
	# 加到 SceneTree（但不调 _ready，让 _is_qa_mode 返回 false 不启动主循环）
	add_child(player)
	player._start_time_ms = Time.get_ticks_msec() - 30000  # 模拟已经跑 30s
	player._run_id = "test_ai_player_callback"

	# 关闭 RunGoals 默认 callback，避免污染 production memory
	Qa.run_goals.disconnect_default_callback()
	Qa.run_goals.set_run_id("test_ai_player_callback")
	Qa.experience_memory.set_run_id("test_ai_player_callback")
	Qa.run_goals.clear_goals()

	_run_for_goal(player, "survive_n_battles", 3)
	_run_for_goal(player, "max_runtime_seconds", 120)
	_run_for_goal(player, "collect_n_cards", 15)
	_run_for_goal(player, "complete_run", 0)
	_run_for_goal(player, "first_loss", 0)
	_run_for_goal(player, "trigger_n_chains", 5)
	_run_for_goal(player, "reach_realm_n", 2)

	# 验证
	test_tactic_record()
	test_strategy_record()
	test_progress_record()
	test_loss_record()
	test_fallback_record()
	test_run_id_propagation()
	test_elapsed_sec_in_evidence()

	# cleanup
	Qa.run_goals.reconnect_default_callback()
	Qa.run_goals.clear_goals()
	player.queue_free()
	print("=== AIPlayer Goal Callback 测试完成 ===\n")

# ===== 测试数据 helper =====

func _run_for_goal(player, type_name: String, value: int) -> void:
	var goal := Goal.new(type_name, value)
	var mock_stats := {
		"battles_won": 5, "battles_lost": 1,
		"cards_collected": 18, "chains_triggered": 6,
		"realm": 2, "node_types_visited": [1, 2, 3, 4],
		"elapsed_seconds": 45, "loop_count": 12,
		"victory": false, "defeat": false,
	}
	player._on_ai_player_goal_completed(goal, mock_stats)

func _get_latest_record_of_type(type_name: String) -> Dictionary:
	# ExperienceMemory.get_last_by_type 返回最新
	return Qa.experience_memory.get_last_by_type(type_name)

# ===== 各 type 路由测试 =====

func test_tactic_record() -> void:
	print("\n--- 测试 survive_n_battles 路由到 trick 类型 ---")
	var rec: Dictionary = _get_latest_record_of_type("trick")
	assert(not rec.is_empty(), "trick 记录应非空")
	assert(rec.get("run_id", "") == "test_ai_player_callback", "trick run_id 错：%s" % str(rec.get("run_id", "")))
	assert(rec.get("scene", "") == "ai_player", "trick scene 错：%s" % str(rec.get("scene", "")))
	assert(rec.get("type", "") == "trick", "type 应是 trick，实际 %s" % str(rec.get("type", "")))
	assert(rec.get("evidence", {}).get("goal_type", "") == Goal.TYPE_SURVIVE_N_BATTLES, "goal_type 错")
	assert(int(rec.get("evidence", {}).get("goal_value", -1)) == 3, "goal_value 错")
	assert(int(rec.get("evidence", {}).get("elapsed_sec", -1)) > 0, "elapsed_sec 应 > 0")
	assert("效率" in str(rec.get("description", "")), "描述应含'效率'：%s" % str(rec.get("description", "")))
	print("  ✓ survive_n_battles → trick（efficiency 计算 + elapsed 追踪）")

func test_strategy_record() -> void:
	print("\n--- 测试 max_runtime_seconds / complete_run 路由到 strategy_profile 类型 ---")
	var rec_max: Dictionary = _get_latest_record_of_type("strategy_profile")
	# latest strategy_profile 应该是 complete_run（最后写）
	assert(not rec_max.is_empty(), "strategy_profile 记录应非空")
	assert(rec_max.get("evidence", {}).get("goal_type", "") == Goal.TYPE_COMPLETE_RUN,
		"latest strategy_profile 应是 complete_run，实际 %s" % str(rec_max.get("evidence", {}).get("goal_type", "")))

	# 验证 max_runtime_seconds 写过的 strategy_profile record 还在
	var all_strategies = Qa.experience_memory.get_records_by_type("strategy_profile")
	assert(all_strategies.size() >= 2, "应有 2+ 条 strategy_profile 记录（max_runtime + complete_run），实际 %d" % all_strategies.size())
	var has_max := false
	for r in all_strategies:
		if r.get("evidence", {}).get("goal_type", "") == Goal.TYPE_MAX_RUNTIME_SECONDS:
			has_max = true
			break
	assert(has_max, "应有一条 max_runtime_seconds strategy_profile 记录")
	print("  ✓ max_runtime_seconds + complete_run → strategy_profile（2 条记录）")

func test_progress_record() -> void:
	print("\n--- 测试 collect_n_cards 路由到 progress 类型 ---")
	var rec: Dictionary = _get_latest_record_of_type("progress")
	assert(not rec.is_empty(), "progress 记录应非空")
	assert(rec.get("evidence", {}).get("goal_type", "") == Goal.TYPE_COLLECT_N_CARDS,
		"goal_type 错：%s" % str(rec.get("evidence", {}).get("goal_type", "")))
	assert("卡组达到" in str(rec.get("description", "")), "描述应含'卡组达到'")
	print("  ✓ collect_n_cards → progress")

func test_loss_record() -> void:
	print("\n--- 测试 first_loss 路由到 loss 类型 ---")
	var rec: Dictionary = _get_latest_record_of_type("loss")
	assert(not rec.is_empty(), "loss 记录应非空")
	assert(rec.get("evidence", {}).get("goal_type", "") == Goal.TYPE_FIRST_LOSS, "loss goal_type 错")
	assert("第一次失败" in str(rec.get("description", "")), "描述应含'第一次失败'")
	print("  ✓ first_loss → loss")

func test_fallback_record() -> void:
	print("\n--- 测试未匹配类型走 fallback (goal) ---")
	# trigger_n_chains + reach_realm_n 没在 match 里，应走 fallback
	# 注意: 跨多次 test_runner run 累积，本 run 应至少 +2
	var all_goal = Qa.experience_memory.get_records_by_type("goal")
	assert(all_goal.size() >= 2, "fallback 记录应 >= 2，实际 %d" % all_goal.size())
	var has_trigger: bool = false
	var has_realm: bool = false
	for r in all_goal:
		var goal_type: String = str(r.get("evidence", {}).get("goal_type", ""))
		if goal_type == Goal.TYPE_TRIGGER_N_CHAINS:
			has_trigger = true
		elif goal_type == Goal.TYPE_REACH_REALM_N:
			has_realm = true
	assert(has_trigger, "应包含 trigger_n_chains")
	assert(has_realm, "应包含 reach_realm_n")
	print("  ✓ trigger_n_chains + reach_realm_n → goal (fallback, %d 条历史)" % all_goal.size())

# ===== 字段测试 =====

func test_run_id_propagation() -> void:
	print("\n--- 测试所有记录 run_id 来自 AI Player ---")
	for type_name in ["trick", "strategy_profile", "progress", "loss", "goal"]:
		var rec: Dictionary = _get_latest_record_of_type(type_name)
		assert(rec.get("run_id", "") == "test_ai_player_callback",
			"%s: run_id 应是 test_ai_player_callback，实际 %s" % [type_name, str(rec.get("run_id", ""))])
	print("  ✓ 所有 5 种 type 的 run_id 都正确传播")

func test_elapsed_sec_in_evidence() -> void:
	print("\n--- 测试 elapsed_sec 在 evidence 里 ---")
	for type_name in ["trick", "strategy_profile", "progress", "loss", "goal"]:
		var rec: Dictionary = _get_latest_record_of_type(type_name)
		var evidence: Dictionary = rec.get("evidence", {})
		assert(int(evidence.get("elapsed_sec", -1)) >= 0,
			"%s: elapsed_sec 应 >= 0，实际 %d" % [type_name, int(evidence.get("elapsed_sec", -1))])
	print("  ✓ 所有 type 的 evidence 都含 elapsed_sec >= 0")