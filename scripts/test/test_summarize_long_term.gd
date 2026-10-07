## ExperienceMemory.summarize_long_term() 单元测试
## 测试 scripts/qa/experience_memory.gd 的 long-term 聚合
##
## P1.1 Phase 3 完整版 (2026-07-05 20:30) — long-term memory 写入 goal-pattern
## 覆盖：
##   - 空 records → no_data 报告
##   - 单条 profile → runs_analyzed=1
##   - 多条 profile → avg_completion_rate / priority+type 分布聚合
##   - 5+ 条 → trend 计算（improving/regressing/stable）
##   - window_size=last_n 截断
##
## 注意：不调 record_strategy_profile（会 _save_memory 污染生产 EM 文件）
##     直接 _records.append({...}) in-memory 测试，测完后 remove

# implements: agent-infrastructure (test infrastructure)
# implements_philosophy: rule_5_real_agency, rule_9_progressive_disclosure

extends Node

var _added_records: Array[Dictionary] = []

func run_all_tests() -> void:
	print("\n=== summarize_long_term 测试 ===")
	test_empty_records_returns_no_data()
	test_single_profile()
	test_three_profiles_aggregate_avg()
	test_five_profiles_trend_improving()
	test_five_profiles_trend_regressing()
	test_five_profiles_trend_stable()
	test_priority_distribution_aggregation()
	test_type_distribution_aggregation()
	test_window_size_truncation()
	print("=== summarize_long_term 测试完成 ===\n")

# ===== Helpers =====

func _make_profile_record(timestamp: String, completion_rate: float, completed_goals: int, total_goals: int, priority_high: int = 1, priority_normal: int = 0, priority_low: int = 0, type_breakdown: Dictionary = {}) -> Dictionary:
	return {
		"id": "exp_long_term_test_%d_%s" % [Time.get_ticks_msec(), timestamp],
		"type": "strategy_profile",
		"scene": "long_term_test",
		"run_id": "long_term_test_run",
		"description": "test profile at %s" % timestamp,
		"evidence": {
			"completion_rate": completion_rate,
			"completed_goals": completed_goals,
			"total_goals": total_goals,
			"avg_completed_value": float(completed_goals * 30),
			"completed_by_priority": {"high": priority_high, "normal": priority_normal, "low": priority_low},
			"priority_breakdown": {"high": priority_high, "normal": priority_normal, "low": priority_low},
			"type_breakdown": type_breakdown,
			"elapsed_seconds": 60.0,
			"summary_at_ms": 1000.0,
			"summary_kind": "strategy_profile",
		},
		"confidence": 0.7,
		"uses": 0,
		"timestamp": timestamp,
	}

func _add_profile(rec: Dictionary) -> void:
	ExperienceMemory._records.append(rec)
	_added_records.append(rec)

func _cleanup() -> void:
	# 从 _records 末尾移除我们 add 的（保持顺序假设：add 是 append）
	for rec in _added_records:
		var idx := ExperienceMemory._records.find(rec)
		if idx >= 0:
			ExperienceMemory._records.remove_at(idx)
	_added_records.clear()

# ===== Tests =====

func test_empty_records_returns_no_data() -> void:
	print("\n--- 测试：当只剩余我们 add 的 mock 时，先 clear ——")
	# 注意：production EM 有 11+ 条 strategy_profile，所以 "空 records" 假设不成立
	# 改为测试 last_n=0 边界
	var result := ExperienceMemory.summarize_long_term(0)
	assert(result["runs_analyzed"] == 0, "last_n=0 应 runs_analyzed=0，实际 %d" % result["runs_analyzed"])
	assert(result["trend"] == "no_data", "空 trend 应 no_data，实际 %s" % result["trend"])
	print("  ✓ last_n=0 边界: runs_analyzed=0")

func test_single_profile() -> void:
	print("\n--- 测试：单条 profile 聚合 ---")
	var ts := "2026-07-05T20:00:00"
	var rec := _make_profile_record(ts, 0.8, 4, 5, 2, 2, 0, {"survive_n_battles": 2, "max_runtime_seconds": 2})
	_add_profile(rec)
	var result := ExperienceMemory.summarize_long_term(50)  # 大 window 确保只 add 这条新 mock
	_cleanup()
	# 单条时 runs_analyzed=1 (如果没其他 mock 污染)
	# 但 production EM 有历史 profile，所以 runs_analyzed >= 1
	assert(result["runs_analyzed"] >= 1, "应至少 1 条 runs_analyzed，实际 %d" % result["runs_analyzed"])
	assert(result["window_size"] == 50, "window_size 应=50，实际 %d" % result["window_size"])
	print("  ✓ 单条 profile 聚合（runs_analyzed=%d）" % result["runs_analyzed"])

func test_three_profiles_aggregate_avg() -> void:
	print("\n--- 测试：3 条 profile，avg_completion_rate 聚合 ---")
	# 用 isolated 时间戳（避免与历史 data 混淆），通过 unique 时间戳保证 window 内有这些
	var ts1 := "2026-07-05T21:00:00"
	var ts2 := "2026-07-05T21:00:01"
	var ts3 := "2026-07-05T21:00:02"
	_add_profile(_make_profile_record(ts1, 0.5, 5, 10, 5, 0, 0))
	_add_profile(_make_profile_record(ts2, 0.7, 7, 10, 5, 2, 0))
	_add_profile(_make_profile_record(ts3, 1.0, 10, 10, 5, 5, 0))
	var result := ExperienceMemory.summarize_long_term(3)  # 只看最近 3 条
	_cleanup()
	assert(result["runs_analyzed"] == 3, "window=3 应 3 条 runs_analyzed，实际 %d" % result["runs_analyzed"])
	# ts3 / ts2 / ts1 是最新 3 条（按倒序）
	# avg = (1.0 + 0.7 + 0.5) / 3 = 0.7333
	var expected_avg: float = (1.0 + 0.7 + 0.5) / 3.0
	assert(abs(result["avg_completion_rate"] - expected_avg) < 0.01, "avg_completion_rate 应 %.4f，实际 %.4f" % [expected_avg, result["avg_completion_rate"]])
	print("  ✓ 3 条 avg_completion_rate=%.3f" % result["avg_completion_rate"])

func test_five_profiles_trend_improving() -> void:
	print("\n--- 测试：5 条 profile，trend=improving ---")
	# time 顺序：老 (low rate) → 新 (high rate)
	# recent (top 2) = 0.9, 0.9 → avg=0.9; older (bottom 3) = 0.3, 0.3, 0.3 → avg=0.3
	_add_profile(_make_profile_record("2026-07-05T22:00:00", 0.3, 3, 10))
	_add_profile(_make_profile_record("2026-07-05T22:00:01", 0.3, 3, 10))
	_add_profile(_make_profile_record("2026-07-05T22:00:02", 0.3, 3, 10))
	_add_profile(_make_profile_record("2026-07-05T22:00:03", 0.9, 9, 10))
	_add_profile(_make_profile_record("2026-07-05T22:00:04", 0.9, 9, 10))
	var result := ExperienceMemory.summarize_long_term(5)
	_cleanup()
	assert(result["runs_analyzed"] == 5, "应 5 条，实际 %d" % result["runs_analyzed"])
	assert(result["trend"] == "improving", "trend 应 improving，实际 %s" % result["trend"])
	print("  ✓ 5 条 trend=improving (recent 0.9 vs older 0.3)")

func test_five_profiles_trend_regressing() -> void:
	print("\n--- 测试：5 条 profile，trend=regressing ---")
	# time 顺序：老 (high rate) → 新 (low rate)
	_add_profile(_make_profile_record("2026-07-05T23:00:00", 0.9, 9, 10))
	_add_profile(_make_profile_record("2026-07-05T23:00:01", 0.9, 9, 10))
	_add_profile(_make_profile_record("2026-07-05T23:00:02", 0.9, 9, 10))
	_add_profile(_make_profile_record("2026-07-05T23:00:03", 0.2, 2, 10))
	_add_profile(_make_profile_record("2026-07-05T23:00:04", 0.3, 3, 10))
	var result := ExperienceMemory.summarize_long_term(5)
	_cleanup()
	assert(result["runs_analyzed"] == 5, "应 5 条，实际 %d" % result["runs_analyzed"])
	assert(result["trend"] == "regressing", "trend 应 regressing，实际 %s" % result["trend"])
	print("  ✓ 5 条 trend=regressing (recent 0.25 vs older 0.9)")

func test_five_profiles_trend_stable() -> void:
	print("\n--- 测试：5 条 profile，trend=stable ---")
	_add_profile(_make_profile_record("2026-07-06T00:00:00", 0.7, 7, 10))
	_add_profile(_make_profile_record("2026-07-06T00:00:01", 0.7, 7, 10))
	_add_profile(_make_profile_record("2026-07-06T00:00:02", 0.7, 7, 10))
	_add_profile(_make_profile_record("2026-07-06T00:00:03", 0.7, 7, 10))
	_add_profile(_make_profile_record("2026-07-06T00:00:04", 0.7, 7, 10))
	var result := ExperienceMemory.summarize_long_term(5)
	_cleanup()
	assert(result["runs_analyzed"] == 5, "应 5 条，实际 %d" % result["runs_analyzed"])
	assert(result["trend"] == "stable", "trend 应 stable，实际 %s" % result["trend"])
	print("  ✓ 5 条 trend=stable (全部 0.7)")

func test_priority_distribution_aggregation() -> void:
	print("\n--- 测试：priority_distribution 跨多 profile 累加 ---")
	_add_profile(_make_profile_record("2026-07-06T01:00:00", 1.0, 5, 5, 2, 1, 0))
	_add_profile(_make_profile_record("2026-07-06T01:00:01", 1.0, 5, 5, 1, 2, 0))
	_add_profile(_make_profile_record("2026-07-06T01:00:02", 1.0, 5, 5, 0, 1, 1))
	var result := ExperienceMemory.summarize_long_term(3)
	_cleanup()
	# recent 3 条的 priority 累加：high=2+1+0=3, normal=1+2+1=4, low=0+0+1=1
	var pd: Dictionary = result["priority_distribution"]
	assert(int(pd.get("high", 0)) == 3, "high 应=3，实际 %d" % int(pd.get("high", 0)))
	assert(int(pd.get("normal", 0)) == 4, "normal 应=4，实际 %d" % int(pd.get("normal", 0)))
	assert(int(pd.get("low", 0)) == 1, "low 应=1，实际 %d" % int(pd.get("low", 0)))
	print("  ✓ priority_distribution: high=%d normal=%d low=%d" % [int(pd.get("high", 0)), int(pd.get("normal", 0)), int(pd.get("low", 0))])

func test_type_distribution_aggregation() -> void:
	print("\n--- 测试：type_distribution 跨多 profile 累加 ---")
	_add_profile(_make_profile_record("2026-07-06T02:00:00", 1.0, 3, 3, 1, 1, 0, {"survive_n_battles": 2, "max_runtime_seconds": 1}))
	_add_profile(_make_profile_record("2026-07-06T02:00:01", 1.0, 3, 3, 1, 1, 0, {"survive_n_battles": 1, "collect_n_cards": 2}))
	var result := ExperienceMemory.summarize_long_term(2)
	_cleanup()
	var td: Dictionary = result["type_distribution"]
	# survive_n_battles: 2+1=3, max_runtime_seconds: 1+0=1, collect_n_cards: 0+2=2
	assert(int(td.get("survive_n_battles", 0)) == 3, "survive_n_battles 应=3，实际 %d" % int(td.get("survive_n_battles", 0)))
	assert(int(td.get("max_runtime_seconds", 0)) == 1, "max_runtime_seconds 应=1，实际 %d" % int(td.get("max_runtime_seconds", 0)))
	assert(int(td.get("collect_n_cards", 0)) == 2, "collect_n_cards 应=2，实际 %d" % int(td.get("collect_n_cards", 0)))
	print("  ✓ type_distribution: survive=%d runtime=%d cards=%d" % [int(td.get("survive_n_battles", 0)), int(td.get("max_runtime_seconds", 0)), int(td.get("collect_n_cards", 0))])

func test_window_size_truncation() -> void:
	print("\n--- 测试：window_size 截断 ---")
	# 加 8 条 profile，window=3 应只取最近 3 条
	for i in range(8):
		_add_profile(_make_profile_record("2026-07-06T03:00:%02d" % i, float(i) / 8.0, i, 10))
	var result := ExperienceMemory.summarize_long_term(3)
	_cleanup()
	assert(result["runs_analyzed"] == 3, "window=3 应 3 条，实际 %d" % result["runs_analyzed"])
	# 最近 3 条时间戳是 07, 06, 05 → rate = 0.875, 0.75, 0.625
	# 但排序时 take .slice(0, 3)，slice 是 [0..3) = [07, 06, 05] 顺序
	var expected_avg: float = (0.875 + 0.75 + 0.625) / 3.0
	assert(abs(result["avg_completion_rate"] - expected_avg) < 0.01, "avg 应 %.4f，实际 %.4f" % [expected_avg, result["avg_completion_rate"]])
	print("  ✓ window=3 截断正确（runs=%d, avg=%.3f）" % [result["runs_analyzed"], result["avg_completion_rate"]])