## Experience Memory — AI Player 经验记忆系统
## 记录每轮游戏的胜负、关键决策、发现的技巧和卡点
## 用于让 AI 像真实玩家一样学习和探索

# implements: design/01-player-experience.md
# implements_philosophy: rule_2_failure_must_have_meaning, rule_5_real_agency
# agent-infrastructure: loop-engineering

extends Node

const SAVE_DIR := "user://qa-logs/"
const MEMORY_FILE := "user://qa-logs/experience-memory.json"

# 2026-07-14: 同时写一份镜像到 workspace 路径，让 shendu-loop Phase E 能读到
# （Phase E 是 Node.js 工具，跑在 workspace 上下文，读 user:// 路径需要装 Godot SDK 不可行）
# 双写策略：user:// 是权威源（Godot 启动时读），workspace 是镜像（agent 读）
const WORKSPACE_MIRROR_FILE := "C:/Users/hbgan/.openclaw/workspace/shendu/qa-logs/experience-memory.json"

## 经验记录字段（使用 Dictionary）：
## id, type, scene, run_id, description, evidence, confidence, uses, timestamp

var _records: Array[Dictionary] = []
var _run_id: String = ""
var _run_start_time_ms: int = 0
# 2026-07-14: per-run 序号计数器（set_run_id 时重置为 0），保证 record id 在同 run 内唯一
var _run_seq: int = 0

func _ready() -> void:
	_load_memory()

## 设置当前 run id
func set_run_id(run_id: String) -> void:
	_run_id = run_id
	_run_start_time_ms = Time.get_ticks_msec()
	_run_seq = 0  # 重置 per-run 序号（新 run 重新从 0 开始）

## 记录一次经验
## P1.1 Phase 2 Step 7 (H1, 2026-07-05 17:57): 加 fail-safe schema 校验
## - invalid 时 print_warning 但不阻止 record（避免破坏 gameplay）
## - 校验逻辑独立在 ExperienceMemorySchema class_name 里（可测）
## 2026-07-14: id 格式改为 exp_<run_id>_<run_seq>，run_seq 在 set_run_id() 时重置为 0
## 避免跨 run id 冲突（之前用 _records.size() 全局下标会撞 test_reconnect 类的同名 session）
func record(type: String, scene: String, description: String, evidence: Dictionary = {}, confidence: float = 0.5) -> Dictionary:
	return _record_internal(type, scene, description, evidence, confidence, false)

# 2026-08-03: record_quiet — 噪音抑制 B 实现
# 跟 record() 同效果（写入 experience file），但 entry 带 quiet: true
# phase_e_consume.mjs 读 quiet: true 的 record 会过滤（不计入 issues.json）
# 用于"我知道这会发生"的 fallback（比如 _force_skip_battle 找不到 BattleManager 的 fallback）
func record_quiet(type: String, scene: String, description: String, evidence: Dictionary = {}, confidence: float = 0.5) -> Dictionary:
	return _record_internal(type, scene, description, evidence, confidence, true)

func _record_internal(type: String, scene: String, description: String, evidence: Dictionary, confidence: float, quiet: bool) -> Dictionary:
	var id := "exp_%s_%d" % [_run_id, _run_seq]
	_run_seq += 1
	var entry := {
		"id": id,
		"type": type,
		"scene": scene,
		"run_id": _run_id,
		"description": description,
		"evidence": evidence,
		"confidence": confidence,
		"uses": 0,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	if quiet:
		entry["quiet"] = true

	# H1 fail-safe schema 校验（不抛错，只 warning）
	var schema_errors: Array[String] = ExperienceMemorySchema.validate_record(entry)
	if not schema_errors.is_empty():
		push_warning("ExperienceMemory[%s]: record 校验失败: %s" % [_run_id, str(schema_errors)])

	_records.append(entry)
	_save_memory()
	print("ExperienceMemory: [%s] %s" % [type, description])
	return entry

## 记录战斗胜负
func record_battle_result(won: bool, turn_count: int, player_hp_percent: float, evidence: Dictionary) -> void:
	var type := "win" if won else "loss"
	var desc := "战斗%s，%d回合，玩家HP %.0f%%" % ["胜利" if won else "失败", turn_count, player_hp_percent * 100]
	record(type, "battle", desc, evidence, 0.8)

## 记录发现的技巧
func record_trick(scene: String, description: String, evidence: Dictionary) -> void:
	record("trick", scene, description, evidence, 0.6)

## 记录卡点
func record_stuck(scene: String, description: String, evidence: Dictionary) -> void:
	record("stuck", scene, description, evidence, 0.9)

## 记录 bug
func record_bug(scene: String, description: String, evidence: Dictionary) -> void:
	record("bug", scene, description, evidence, 0.95)

## 记录设计问题（需要 Robert 批准后修改）
func record_design_issue(scene: String, description: String, evidence: Dictionary = {}) -> void:
	record("design_issue", scene, description, evidence, 0.85)

## 记录平衡问题（需要 Robert 批准后修改）
func record_balance_issue(scene: String, description: String, evidence: Dictionary = {}) -> void:
	record("balance_issue", scene, description, evidence, 0.85)

## 记录 UI/UX 问题
## P1.1 Phase 3 (2026-07-05 17:55): 记录策略画像到 ExperienceMemory
## type = "strategy_profile", evidence = summarize_session() 输出
func record_strategy_profile(scene: String, profile: Dictionary) -> Dictionary:
	var evidence := profile.duplicate()
	evidence["summary_kind"] = "strategy_profile"
	return record("strategy_profile", scene, "策略画像：完成 %d/%d goals, 优先 high=%d normal=%d low=%d" % [
		int(profile.get("completed_goals", 0)),
		int(profile.get("total_goals", 0)),
		int(profile.get("completed_by_priority", {}).get("high", 0)),
		int(profile.get("completed_by_priority", {}).get("normal", 0)),
		int(profile.get("completed_by_priority", {}).get("low", 0)),
	], evidence, 0.7)

## P1.1 Phase 3 完整版 (2026-07-05 20:30): long-term memory 聚合
## - 读最近 N 条 strategy_profile records
## - 计算 avg_completion_rate / avg_completed_value / 跨 run priority+type 分布 / trend
## - AI Player 启动可调用 / cron 每日调 / wiki 写入原材料
func summarize_long_term(last_n: int = 10) -> Dictionary:
	var profiles: Array = []
	for rec in _records:
		if rec.get("type", "") == "strategy_profile":
			profiles.append(rec)
	# 按 timestamp 倒序（最近在前）
	profiles.sort_custom(func(a, b): return str(a.get("timestamp", "")) > str(b.get("timestamp", "")))
	var selected: Array = profiles.slice(0, last_n)

	if selected.is_empty():
		return {
			"runs_analyzed": 0,
			"avg_completion_rate": 0.0,
			"avg_completed_value": 0.0,
			"total_completed_goals": 0,
			"total_goals_attempted": 0,
			"priority_distribution": {},
			"type_distribution": {},
			"trend": "no_data",
			"last_updated": "",
			"window_size": last_n,
		}

	var total_rate: float = 0.0
	var total_value: float = 0.0
	var total_completed: int = 0
	var total_attempted: int = 0
	var priority_dist: Dictionary = {"high": 0, "normal": 0, "low": 0}
	var type_dist: Dictionary = {}
	var latest_ts: String = ""

	for rec in selected:
		var ev: Dictionary = rec.get("evidence", {})
		total_rate += float(ev.get("completion_rate", 0.0))
		total_value += float(ev.get("avg_completed_value", 0.0))
		total_completed += int(ev.get("completed_goals", 0))
		total_attempted += int(ev.get("total_goals", 0))

		# 累加 priority 分布
		var cbp: Dictionary = ev.get("completed_by_priority", {})
		for p in cbp:
			var pv: int = int(cbp[p])
			priority_dist[p] = int(priority_dist.get(p, 0)) + pv

		# 累加 type 分布
		var tb: Dictionary = ev.get("type_breakdown", {})
		for t in tb:
			var tv: int = int(tb[t])
			type_dist[t] = int(type_dist.get(t, 0)) + tv

		if latest_ts == "" or str(rec.get("timestamp", "")) > latest_ts:
			latest_ts = str(rec.get("timestamp", ""))

	var n: int = selected.size()
	var avg_rate: float = total_rate / float(n) if n > 0 else 0.0
	var avg_value: float = total_value / float(n) if n > 0 else 0.0

	# Trend: 最近一半 vs 之前一半的 completion_rate 差
	# positive 表示越来越好，negative 表示退步
	var trend: String = "stable"
	if n >= 4:
		var half: int = int(float(n) / 2.0)
		var recent_sum: float = 0.0
		var older_sum: float = 0.0
		for i in range(half):
			recent_sum += float((selected[i] as Dictionary).get("evidence", {}).get("completion_rate", 0.0))
		for i in range(half, n):
			older_sum += float((selected[i] as Dictionary).get("evidence", {}).get("completion_rate", 0.0))
		var recent_avg: float = recent_sum / float(half)
		var older_avg: float = older_sum / float(n - half)
		var delta: float = recent_avg - older_avg
		if delta > 0.05:
			trend = "improving"
		elif delta < -0.05:
			trend = "regressing"
		else:
			trend = "stable"

	return {
		"runs_analyzed": n,
		"avg_completion_rate": avg_rate,
		"avg_completed_value": avg_value,
		"total_completed_goals": total_completed,
		"total_goals_attempted": total_attempted,
		"priority_distribution": priority_dist,
		"type_distribution": type_dist,
		"trend": trend,
		"last_updated": latest_ts,
		"window_size": last_n,
	}

func record_ui_issue(scene: String, description: String, evidence: Dictionary = {}) -> void:
	record("ui_issue", scene, description, evidence, 0.8)

## 根据类型查询经验
func get_records_by_type(type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rec in _records:
		if rec.get("type", "") == type:
			result.append(rec)
	return result

## 获取最近一次同类型经验
func get_last_by_type(type: String) -> Dictionary:
	var filtered := get_records_by_type(type)
	if filtered.is_empty():
		return {}
	return filtered.back()

## 获取所有记录
func get_all_records() -> Array[Dictionary]:
	return _records.duplicate()

## 保存到 JSON
func _save_memory() -> void:
	var dir := DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive(SAVE_DIR)

	var data := {
		"updated_at": Time.get_datetime_string_from_system(),
		"record_count": _records.size(),
		"records": _records,
	}

	# 2026-07-14: 总是同步镜像到 workspace（独立于 user:// 写盘是否成功）
	# Phase E 依赖 workspace 镜像驱动反馈闭环
	_mirror_to_workspace(data)

	var file := FileAccess.open(MEMORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

# 2026-07-14: 镜像到 workspace 路径（sute-SilentCommand 友好）
func _mirror_to_workspace(data: Dictionary) -> void:
	var abs_path := WORKSPACE_MIRROR_FILE
	var abs_dir := abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var mirror_file := FileAccess.open(abs_path, FileAccess.WRITE)
	if mirror_file:
		mirror_file.store_string(JSON.stringify(data, "\t"))
		mirror_file.close()

## 从 JSON 加载
func _load_memory() -> void:
	if not FileAccess.file_exists(MEMORY_FILE):
		return
	var file := FileAccess.open(MEMORY_FILE, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var data: Dictionary = parsed
		var records_data: Array = data.get("records", [])
		_records.clear()
		for rec_dict in records_data:
			if rec_dict is Dictionary:
				var rec: Dictionary = rec_dict
				_records.append(rec)
		print("ExperienceMemory: 已加载 %d 条经验" % _records.size())
