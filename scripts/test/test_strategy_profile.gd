## P1.1 Phase 3 (2026-07-05 17:55) — Strategy Profile 单元测试
## 测试 RunGoals.summarize_session() + ExperienceMemory.record_strategy_profile()
extends Node

func run_all_tests() -> void:
	print("\n=== Strategy Profile 测试 ===")
	test_summarize_empty_session()
	test_summarize_partial_completion()
	test_summarize_full_completion_with_priority()
	test_record_strategy_profile_to_experience_memory()
	test_profile_aggregation_with_realistic_data()
	print("=== Strategy Profile 测试完成 ===\n")

## 空 session（无 goals）
func test_summarize_empty_session() -> void:
	print("\n--- 空 session 画像 ---")
	Qa.run_goals.clear_goals()
	Qa.run_goals.set_run_id("profile-empty")
	var profile = Qa.run_goals.summarize_session()
	assert(profile["total_goals"] == 0, "空 session total_goals 应 0")
	assert(profile["completed_goals"] == 0, "空 session completed 应 0")
	assert(profile["completion_rate"] == 0.0, "空 session completion_rate 应 0.0")
	assert(profile["run_id"] == "profile-empty", "run_id 应匹配")
	assert(profile["avg_completed_value"] == 0.0, "空 session avg_value 应 0.0")
	print("  ✓ 空 session 画像正确")

## 部分完成
func test_summarize_partial_completion() -> void:
	print("\n--- 部分完成 (1/3) ---")
	Qa.run_goals.clear_goals()
	Qa.run_goals.set_run_id("profile-partial")
	Qa.run_goals.add_goal("survive_n_battles", 3, "high")
	Qa.run_goals.add_goal("max_runtime_seconds", 120, "normal")
	Qa.run_goals.add_goal("collect_n_cards", 15, "normal")
	# 只触发 survive_n_battles 完成
	Qa.run_goals.report("battles_won", 3)
	var profile = Qa.run_goals.summarize_session()
	assert(profile["total_goals"] == 3, "total 应 3")
	assert(profile["completed_goals"] == 1, "completed 应 1")
	assert(abs(profile["completion_rate"] - 0.333) < 0.01, "completion_rate 应 ≈ 0.333，实际 %f" % profile["completion_rate"])
	assert(profile["priority_breakdown"]["high"] == 1, "priority.high 应 1")
	assert(profile["priority_breakdown"]["normal"] == 2, "priority.normal 应 2")
	assert(profile["completed_by_priority"]["high"] == 1, "completed.high 应 1")
	assert(profile["completed_by_priority"]["normal"] == 0, "completed.normal 应 0")
	assert(profile["type_breakdown"]["survive_n_battles"] == 1, "type.survive 应 1")
	assert(profile["avg_completed_value"] == 3.0, "avg_value 应 3.0 (survive value)")
	print("  ✓ 部分完成画像正确")

## 全部完成 + 优先级分布
func test_summarize_full_completion_with_priority() -> void:
	print("\n--- 全完成 + 3 priority ---")
	Qa.run_goals.clear_goals()
	Qa.run_goals.set_run_id("profile-full")
	Qa.run_goals.add_goal("survive_n_battles", 5, "high")
	Qa.run_goals.add_goal("max_runtime_seconds", 60, "normal")
	Qa.run_goals.add_goal("collect_n_cards", 10, "low")
	Qa.run_goals.report("battles_won", 5)
	Qa.run_goals.report("elapsed_seconds", 60)
	Qa.run_goals.report("cards_collected", 10)
	var profile = Qa.run_goals.summarize_session()
	assert(profile["total_goals"] == 3, "total 应 3")
	assert(profile["completed_goals"] == 3, "completed 应 3")
	assert(profile["completion_rate"] == 1.0, "completion_rate 应 1.0")
	assert(profile["priority_breakdown"]["high"] == 1, "high 应 1")
	assert(profile["priority_breakdown"]["normal"] == 1, "normal 应 1")
	assert(profile["priority_breakdown"]["low"] == 1, "low 应 1")
	assert(profile["completed_by_priority"]["high"] == 1, "completed.high 应 1")
	assert(profile["avg_completed_value"] == 25.0, "avg_value 应 (5+60+10)/3 = 25.0")
	print("  ✓ 全完成 + 3 priority 画像正确")

## ExperienceMemory 记录
func test_record_strategy_profile_to_experience_memory() -> void:
	print("\n--- ExperienceMemory 写入测试 ---")
	Qa.run_goals.clear_goals()
	Qa.run_goals.set_run_id("profile-mem")
	Qa.run_goals.add_goal("survive_n_battles", 2, "high")
	Qa.run_goals.add_goal("max_runtime_seconds", 100, "normal")
	Qa.run_goals.report("battles_won", 2)
	Qa.run_goals.report("elapsed_seconds", 100)
	var profile = Qa.run_goals.summarize_session()
	var record: Dictionary = Qa.experience_memory.record_strategy_profile("test_scenario", profile)
	assert(record.get("type") == "strategy_profile", "记录 type 应 strategy_profile")
	assert(record.get("evidence", {}).get("summary_kind") == "strategy_profile", "evidence 含 summary_kind")
	assert(record.get("evidence", {}).get("run_id") == "profile-mem", "evidence 含 run_id")
	print("  ✓ ExperienceMemory 收到 strategy_profile 记录 (type=strategy_profile)")

## 真实数据聚合
func test_profile_aggregation_with_realistic_data() -> void:
	print("\n--- 真实数据聚合 ---")
	Qa.run_goals.clear_goals()
	Qa.run_goals.set_run_id("profile-realistic")
	# 模拟 AI Player default 3 goals
	Qa.run_goals.add_goal("survive_n_battles", 3, "high")
	Qa.run_goals.add_goal("max_runtime_seconds", 120, "normal")
	Qa.run_goals.add_goal("collect_n_cards", 15, "normal")
	# 模拟 AI Player 真实 gameplay: 打 3 场 + 收集 12 张 + 跑到 90s
	Qa.run_goals.report("battles_won", 3)        # survive_n_battles 完成
	Qa.run_goals.report("cards_collected", 12)   # 未达 15, 未完成
	Qa.run_goals.report("elapsed_seconds", 90)   # 未达 120, 未完成
	var profile = Qa.run_goals.summarize_session()
	assert(profile["completed_goals"] == 1, "仅 survive 完成，应 1/3")
	assert(profile["completion_rate"] < 1.0, "completion_rate < 1.0")
	# 验证 elapsed_seconds 已记录
	assert(profile["elapsed_seconds"] == 90, "elapsed_seconds 应 90")
	# 验证 summary_at_ms 是当前时间（< 1 秒前）
	var elapsed_ms: int = int(Time.get_ticks_msec()) - int(profile["summary_at_ms"])
	assert(elapsed_ms < 5000, "summary_at_ms 应近期生成（实际 %d ms ago）" % elapsed_ms)
	print("  ✓ 真实数据画像正确（1/3 完成，elapsed=90s）")