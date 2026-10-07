## Experience Memory Schema — 字段类型与值校验器
##
## 2026-07-05 P1.1 Phase 2 Step 7 (H1, trace)：
##   - 防字段类型漂移（confidence 写错类型 / type 拼错等）
##   - 防 schema 版本不一致（升级时显式迁移）
##   - 给 ExperienceMemory.record() 一个 fail-safe 校验路径
##
## 设计哲学（implements rule_2_failure_must_have_meaning）：
##   - 校验失败时 print_warning + return errors 数组（不抛错，避免破坏 gameplay）
##   - 校验逻辑本身独立可测（class_name 全局可见）
##   - VALID_TYPES 是常量，新增 type 必须改这里 + 加测试
##
## 设计哲学（implements rule_9_progressive_disclosure）：
##   - 不强制 record() 必须校验（保留 fail-safe 路径给 production）
##   - 但提供工具让 test / dev 主动调 validate

# implements: agent-infrastructure
# implements_philosophy: rule_2_failure_must_have_meaning, rule_9_progressive_disclosure
# agent-infrastructure: loop-engineering

class_name ExperienceMemorySchema
extends RefCounted

# ===== Schema 版本 =====

const SCHEMA_VERSION := 1

# ===== 合法 type 常量 =====

## 所有合法 type（与 experience_memory.gd record_*() 方法对应）
const VALID_TYPES: PackedStringArray = [
	"win",
	"loss",
	"trick",
	"stuck",
	"bug",
	"design_issue",
	"balance_issue",
	"ui_issue",
	"strategy_profile",   # P1.1 Phase 3 (2026-07-05)
	"goal",               # P1.1 Step 3 (2026-07-05)
	"progress",           # 2026-07-06: AI Player 进度里程碑（卡组收集等）
]

# ===== 字段类型定义 =====

## 字段名 → 期望 GDScript 类型（用于 typeof() 检查）
## 注意：GDScript typeof() 返回值：
##   TYPE_NIL = 0, TYPE_BOOL = 1, TYPE_INT = 2, TYPE_FLOAT = 3, TYPE_STRING = 4,
##   TYPE_DICTIONARY = 18, TYPE_ARRAY = 14
const FIELD_TYPES: Dictionary = {
	"id": TYPE_STRING,
	"type": TYPE_STRING,
	"scene": TYPE_STRING,
	"run_id": TYPE_STRING,
	"description": TYPE_STRING,
	"evidence": TYPE_DICTIONARY,
	"confidence": TYPE_FLOAT,
	"uses": TYPE_INT,
	"timestamp": TYPE_STRING,
}

## 必填字段（缺则校验失败）
const REQUIRED_FIELDS: PackedStringArray = [
	"id",
	"type",
	"scene",
	"run_id",
	"description",
	"confidence",
	"timestamp",
]

## 字段名 → 合法值范围（用于 enum-style 字段）
const FIELD_VALID_VALUES: Dictionary = {
	"type": VALID_TYPES,
}

## 字段名 → 数值范围（min, max）
const FIELD_NUMERIC_RANGES: Dictionary = {
	"confidence": [0.0, 1.0],
}

# ===== 校验主入口 =====

## 校验单条 record，返回错误列表（empty = 全部合法）
## 错误格式："{field}: {message}" — 第一个字段名便于 grep
static func validate_record(rec: Variant) -> Array[String]:
	var errors: Array[String] = []

	# 0. 类型门：必须是 Dictionary
	if not (rec is Dictionary):
		errors.append("record: 必须是 Dictionary，实际是 %s" % typeof(rec))
		return errors

	var d: Dictionary = rec

	# 1. 必填字段检查
	for field in REQUIRED_FIELDS:
		if not d.has(field):
			errors.append("%s: 字段缺失" % field)

	# 2. 类型检查（只检查 present 字段，缺失的留给必填检查）
	for field in FIELD_TYPES:
		if d.has(field):
			var expected_type: int = int(FIELD_TYPES[field])
			var actual_type: int = typeof(d[field])
			# int 在 GDScript 中可接受为 float 范围（confidence 字段）
			# 但 confidence 实际写是 float，所以严格要求 TYPE_FLOAT
			if actual_type != expected_type:
				errors.append("%s: 类型错误，期望 %d，实际 %d" % [field, expected_type, actual_type])

	# 3. enum-style 字段值合法性
	for field in FIELD_VALID_VALUES:
		if d.has(field):
			var valid_values: PackedStringArray = FIELD_VALID_VALUES[field]
			var actual_value: String = str(d[field])
			if not valid_values.has(actual_value):
				errors.append("%s: 非法值 '%s'，合法值: %s" % [field, actual_value, str(valid_values)])

	# 4. 数值范围
	for field in FIELD_NUMERIC_RANGES:
		if d.has(field):
			var range_value: Array = FIELD_NUMERIC_RANGES[field]
			var min_v: float = float(range_value[0])
			var max_v: float = float(range_value[1])
			var actual_v: float = float(d[field])
			if actual_v < min_v or actual_v > max_v:
				errors.append("%s: 数值 %.3f 超出范围 [%.3f, %.3f]" % [field, actual_v, min_v, max_v])

	return errors

## 校验一批 records，返回聚合报告
static func validate_all_records(records: Array) -> Dictionary:
	var valid_count: int = 0
	var invalid_count: int = 0
	var all_errors: Array[Dictionary] = []

	for i in range(records.size()):
		var rec = records[i]
		var errs: Array[String] = validate_record(rec)
		if errs.is_empty():
			valid_count += 1
		else:
			invalid_count += 1
			var rec_id: String = "index_%d" % i
			if rec is Dictionary and (rec as Dictionary).has("id"):
				rec_id = str((rec as Dictionary)["id"])
			all_errors.append({
				"record_id": rec_id,
				"errors": errs,
			})

	return {
		"total": records.size(),
		"valid_count": valid_count,
		"invalid_count": invalid_count,
		"all_errors": all_errors,
	}

## 从文件读取并校验（fail-safe：文件不存在返回空报告）
static func validate_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"file_exists": false,
			"path": path,
			"total": 0,
			"valid_count": 0,
			"invalid_count": 0,
			"all_errors": [],
		}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {
			"file_exists": true,
			"path": path,
			"read_ok": false,
			"total": 0,
			"valid_count": 0,
			"invalid_count": 0,
			"all_errors": [],
		}

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {
			"file_exists": true,
			"path": path,
			"read_ok": true,
			"parse_ok": false,
			"total": 0,
			"valid_count": 0,
			"invalid_count": 0,
			"all_errors": [],
		}

	var data: Dictionary = parsed
	var records_data: Array = data.get("records", [])
	var report: Dictionary = validate_all_records(records_data)
	report["file_exists"] = true
	report["read_ok"] = true
	report["parse_ok"] = true
	report["path"] = path
	report["schema_version"] = data.get("schema_version", 0)
	return report

# ===== Schema 迁移 =====

## 简单 v0 → v1 迁移（如果未来升级 schema）
## 当前 SCHEMA_VERSION=1，所以这是 no-op（保留接口便于未来）
static func migrate_record(rec: Dictionary, from_version: int) -> Dictionary:
	if from_version >= SCHEMA_VERSION:
		return rec  # 已是最新的，无需迁移

	var migrated: Dictionary = rec.duplicate()

	# v0 → v1：补 uses 字段（v0 没有）
	if from_version == 0 and not migrated.has("uses"):
		migrated["uses"] = 0

	return migrated

## 总结报告（人类可读）
static func summarize_report(report: Dictionary) -> String:
	if not bool(report.get("file_exists", true)):
		return "file missing: %s" % report.get("path", "?")
	if not bool(report.get("read_ok", true)):
		return "file read failed: %s" % report.get("path", "?")
	if not bool(report.get("parse_ok", true)):
		return "JSON parse failed: %s" % report.get("path", "?")

	var total: int = int(report.get("total", 0))
	var _valid: int = int(report.get("valid_count", 0))
	var invalid: int = int(report.get("invalid_count", 0))
	var version: int = int(report.get("schema_version", 0))

	if invalid == 0:
		return "✓ %d records 全部合法 (schema v%d)" % [total, version]

	var first_errors: Array = report.get("all_errors", [])
	var detail := ""
	if first_errors.size() > 0:
		var first: Dictionary = first_errors[0]
		detail = "；first invalid: %s — %s" % [
			first.get("record_id", "?"),
			str(first.get("errors", [])),
		]

	return "✗ %d/%d records 非法 (schema v%d)%s" % [invalid, total, version, detail]