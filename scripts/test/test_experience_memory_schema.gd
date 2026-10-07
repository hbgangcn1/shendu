## ExperienceMemory Schema 单元测试
## 测试 scripts/qa/experience_memory_schema.gd 的 validate_record / validate_all_records / validate_file / migrate_record
##
## P1.1 Phase 2 Step 7 (H1, 2026-07-05 17:57)：防字段类型漂移 + 防 schema 版本不一致
## 覆盖：
##   - 合法 record → 0 errors
##   - 必填字段缺失
##   - 字段类型错误（confidence 是 string 等）
##   - enum-style 字段值非法（type="unknown"）
##   - 数值范围越界（confidence > 1.0）
##   - evidence 必须 Dictionary
##   - 多个错误聚合
##   - 全文件验证（file_exists / read_ok / parse_ok）
##   - v0 → v1 migration（uses 字段补 0）

# implements: agent-infrastructure (test infrastructure)
# implements_philosophy: rule_2_failure_must_have_meaning

extends Node

func run_all_tests() -> void:
	print("\n=== ExperienceMemory Schema 测试 ===")
	test_valid_record_has_zero_errors()
	test_missing_required_field_flagged()
	test_wrong_field_type_flagged()
	test_invalid_type_value_flagged()
	test_confidence_out_of_range_flagged()
	test_evidence_must_be_dictionary()
	test_multiple_errors_in_one_record()
	test_validate_all_records_aggregates()
	test_validate_file_missing_returns_empty_report()
	test_progress_type_is_valid()
	test_ai_player_goal_types_are_valid()
	test_migrate_v0_to_v1_adds_uses_field()
	print("=== ExperienceMemory Schema 测试完成 ===\n")

# ===== Helpers =====

func _make_valid_record() -> Dictionary:
	return {
		"id": "exp_test_001",
		"type": "win",
		"scene": "battle",
		"run_id": "test_run_001",
		"description": "测试合法 record",
		"evidence": {"turn_count": 5, "player_hp": 1.0},
		"confidence": 0.8,
		"uses": 0,
		"timestamp": "2026-07-05T17:57:00",
	}

# ===== 测试用例 =====

func test_valid_record_has_zero_errors() -> void:
	print("\n--- 测试合法 record 应有 0 errors ---")
	var rec := _make_valid_record()
	var errs := ExperienceMemorySchema.validate_record(rec)
	assert(errs.is_empty(), "合法 record 不应有 errors，实际: %s" % str(errs))
	print("  ✓ 合法 record 通过校验（0 errors）")

func test_missing_required_field_flagged() -> void:
	print("\n--- 测试必填字段缺失应被 flag ---")
	var rec := _make_valid_record()
	rec.erase("id")
	var errs := ExperienceMemorySchema.validate_record(rec)
	assert(errs.size() == 1, "缺 id 应有 1 error，实际 %d" % errs.size())
	assert(errs[0].begins_with("id:"), "error 应以 'id:' 开头，实际: %s" % errs[0])
	print("  ✓ 缺 'id' 字段被捕获: %s" % errs[0])

func test_wrong_field_type_flagged() -> void:
	print("\n--- 测试字段类型错应被 flag ---")
	var rec := _make_valid_record()
	rec["confidence"] = "high"  # 应是 float，写了 string
	var errs := ExperienceMemorySchema.validate_record(rec)
	assert(errs.size() == 1, "confidence 类型错应有 1 error，实际 %d" % errs.size())
	assert(errs[0].begins_with("confidence:"), "error 应以 'confidence:' 开头，实际: %s" % errs[0])
	print("  ✓ confidence 写成 string 被捕获: %s" % errs[0])

func test_invalid_type_value_flagged() -> void:
	print("\n--- 测试非法 type 值应被 flag ---")
	var rec := _make_valid_record()
	rec["type"] = "unknown_type"
	var errs := ExperienceMemorySchema.validate_record(rec)
	assert(errs.size() == 1, "非法 type 应有 1 error，实际 %d" % errs.size())
	assert(errs[0].begins_with("type:"), "error 应以 'type:' 开头，实际: %s" % errs[0])
	assert(errs[0].find("unknown_type") >= 0, "error 应包含非法值 'unknown_type'，实际: %s" % errs[0])
	print("  ✓ 非法 type 值 'unknown_type' 被捕获: %s" % errs[0])

func test_confidence_out_of_range_flagged() -> void:
	print("\n--- 测试 confidence 越界应被 flag ---")
	var rec := _make_valid_record()
	rec["confidence"] = 1.5  # 超出 [0.0, 1.0]
	var errs := ExperienceMemorySchema.validate_record(rec)
	assert(errs.size() == 1, "confidence=1.5 应有 1 error，实际 %d" % errs.size())
	assert(errs[0].begins_with("confidence:"), "error 应以 'confidence:' 开头，实际: %s" % errs[0])
	print("  ✓ confidence=1.5 越界被捕获: %s" % errs[0])

func test_evidence_must_be_dictionary() -> void:
	print("\n--- 测试 evidence 必须 Dictionary ---")
	var rec := _make_valid_record()
	rec["evidence"] = [1, 2, 3]  # 应是 Dictionary，写了 Array
	var errs := ExperienceMemorySchema.validate_record(rec)
	assert(errs.size() == 1, "evidence 类型错应有 1 error，实际 %d" % errs.size())
	assert(errs[0].begins_with("evidence:"), "error 应以 'evidence:' 开头，实际: %s" % errs[0])
	print("  ✓ evidence 写成 Array 被捕获: %s" % errs[0])

func test_multiple_errors_in_one_record() -> void:
	print("\n--- 测试多个错误应聚合 ---")
	var rec := {
		# 缺 id / run_id / description / timestamp
		"type": "unknown_type",  # 非法值
		"scene": "battle",
		"confidence": 2.0,  # 越界
	}
	var errs := ExperienceMemorySchema.validate_record(rec)
	# 期望: 4 missing + 1 invalid type + 1 confidence range = 6 errors
	assert(errs.size() >= 5, "多条错误应聚合，实际 %d 条: %s" % [errs.size(), str(errs)])
	print("  ✓ 多错误聚合捕获（%d 条）: %s" % [errs.size(), str(errs)])

func test_validate_all_records_aggregates() -> void:
	print("\n--- 测试 validate_all_records 聚合报告 ---")
	var valid1 := _make_valid_record()
	valid1["id"] = "exp_001"
	var valid2 := _make_valid_record()
	valid2["id"] = "exp_002"
	var invalid := _make_valid_record()
	invalid["id"] = "exp_003"
	invalid["type"] = "bogus"

	var records: Array = [valid1, valid2, invalid]
	var report := ExperienceMemorySchema.validate_all_records(records)

	assert(report["total"] == 3, "total 应为 3，实际 %d" % report["total"])
	assert(report["valid_count"] == 2, "valid_count 应为 2，实际 %d" % report["valid_count"])
	assert(report["invalid_count"] == 1, "invalid_count 应为 1，实际 %d" % report["invalid_count"])

	var all_errors: Array = report["all_errors"]
	assert(all_errors.size() == 1, "all_errors 应有 1 项（仅 invalid 那条），实际 %d" % all_errors.size())
	assert(all_errors[0]["record_id"] == "exp_003", "record_id 应是 'exp_003'，实际 '%s'" % all_errors[0]["record_id"])

	print("  ✓ validate_all_records 聚合正确（valid=2, invalid=1, 错误定位到 exp_003）")

func test_validate_file_missing_returns_empty_report() -> void:
	print("\n--- 测试 validate_file 不存在的文件应返回空报告 ---")
	var report := ExperienceMemorySchema.validate_file("user://__nonexistent_path__.json")
	assert(not bool(report.get("file_exists", true)), "不存在文件应 file_exists=false")
	assert(report["total"] == 0, "total 应为 0")
	print("  ✓ 不存在文件正确处理: %s" % ExperienceMemorySchema.summarize_report(report))

func test_progress_type_is_valid() -> void:
	print("\n--- 测试 progress type 合法（AI Player 进度里程碑）---")
	var rec := _make_valid_record()
	rec["type"] = "progress"
	rec["description"] = "卡组达到 15 张"
	var errs := ExperienceMemorySchema.validate_record(rec)
	assert(errs.is_empty(), "progress 应是合法 type，实际 errors: %s" % str(errs))
	print("  ✓ progress type 校验通过")

func test_ai_player_goal_types_are_valid() -> void:
	print("\n--- 测试 AI Player goal 完成回调常用 type 全合法 ---")
	var types: Array[String] = ["trick", "strategy_profile", "progress", "loss", "goal"]
	for t in types:
		var rec := _make_valid_record()
		rec["type"] = t
		var errs := ExperienceMemorySchema.validate_record(rec)
		assert(errs.is_empty(), "type '%s' 应合法，实际 errors: %s" % [t, str(errs)])
	print("  ✓ AI Player goal types 全部合法: %s" % ", ".join(types))

func test_migrate_v0_to_v1_adds_uses_field() -> void:
	print("\n--- 测试 migrate_record v0 → v1 应补 uses 字段 ---")
	var v0_rec := {
		"id": "exp_v0_001",
		"type": "win",
		"scene": "battle",
		"run_id": "r001",
		"description": "v0 record",
		"confidence": 0.7,
		"timestamp": "2026-07-01T00:00:00",
		# 缺 uses
	}
	var migrated := ExperienceMemorySchema.migrate_record(v0_rec, 0)
	assert(migrated.has("uses"), "migrated 后应有 uses 字段")
	assert(int(migrated["uses"]) == 0, "uses 应默认为 0，实际 %d" % int(migrated["uses"]))
	print("  ✓ v0 → v1 migration 补 uses=0 成功")