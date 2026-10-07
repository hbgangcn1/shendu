## Run Goals — 任务驱动的运行目标管理
## 每次 run 携带 1-N 个 completion goal，全部完成才结束

# implements: agent-infrastructure
# implements_philosophy: rule_5_real_agency
# agent-infrastructure: loop-engineering

extends Node

## 单个 Goal 数据结构定义在 scripts/qa/goal.gd（class_name Goal，extends RefCounted）。
## 本文件通过全局 class_name 直接引用 Goal 类型：
##   - `var _goals: Array[Goal]` typed array
##   - `Goal.new(type, value, priority)` 构造
##   - `goal.check(stats)` / `goal.description` / `goal.completed` 字段访问
##
## 拆分原因（P1.1 Phase 1 Step 1, 2026-07-05）：
##   - single responsibility（Goal 数据 vs RunGoals 状态机）
##   - 独立单元测（scripts/test/test_goal.gd 后续添加）
##   - 外部配置（yaml/json）可直接构造 Goal 实例
##   - ExperienceMemory callback 可挂到 Goal 而非 RunGoals

## Goal 完成时 emit
## listener 接收参数: (goal: Goal, stats: Dictionary)
## 默认 callback: _default_goal_callback (写入 ExperienceMemory, _ready 时自动连接)
## 测试可调用 disconnect_default_callback() 避免污染 experience-memory.json
signal goal_completed

var _goals: Array[Goal] = []
var _stats: Dictionary = {}
var _run_id: String = ""
var _completed_goals: Array[String] = []
var _all_completed: bool = false

func _ready() -> void:
	reset_stats()
	# 注册默认 callback: 写入 ExperienceMemory
	if not goal_completed.is_connected(_default_goal_callback):
		goal_completed.connect(_default_goal_callback)

## 断开默认 callback (测试用, 避免污染 experience-memory.json)
func disconnect_default_callback() -> void:
	if goal_completed.is_connected(_default_goal_callback):
		goal_completed.disconnect(_default_goal_callback)

## 重新连接默认 callback (测试清理用)
func reconnect_default_callback() -> void:
	if not goal_completed.is_connected(_default_goal_callback):
		goal_completed.connect(_default_goal_callback)

# ===== 外部配置加载 (P1.1 Phase 1 Step 2, 2026-07-05) =====

## 默认 goal library 路径 (可被 load_goal_scene(scene, custom_path) 覆盖)
const DEFAULT_GOAL_LIBRARY_PATH := "res://scripts/qa/goal_library.json"

## 从 JSON 库加载指定场景 (不修改 _goals, 仅返回 Array[Goal])
## 失败返回 []: path 不存在 / JSON 错 / 场景不存在 / 字段缺 — 不抛错
## caller 负责 fallback (如调 GoalTemplates.battle_baseline())
##
## JSON schema:
##   { "version": 1,
##     "scenes": { "scene_name": [ {type, value, priority}, ... ] } }
func load_goal_scene(scene_name: String, library_path: String = DEFAULT_GOAL_LIBRARY_PATH) -> Array[Goal]:
	var goals: Array[Goal] = []
	if not FileAccess.file_exists(library_path):
		push_warning("RunGoals: goal library not found: %s" % library_path)
		return goals
	var file := FileAccess.open(library_path, FileAccess.READ)
	if not file:
		return goals
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("RunGoals: invalid JSON in %s" % library_path)
		return goals
	var library: Dictionary = parsed
	var scenes_var: Variant = library.get("scenes", {})
	if not scenes_var is Dictionary:
		push_warning("RunGoals: 'scenes' field is not a dictionary in %s" % library_path)
		return goals
	var scenes: Dictionary = scenes_var
	if not scenes.has(scene_name):
		push_warning("RunGoals: scene '%s' not in library %s" % [scene_name, library_path])
		return goals
	var raw_goals_var: Variant = scenes[scene_name]
	if not raw_goals_var is Array:
		push_warning("RunGoals: scene '%s' is not an array" % scene_name)
		return goals
	var raw_goals: Array = raw_goals_var
	for goal_dict in raw_goals:
		if goal_dict is Dictionary:
			var goal: Goal = _goal_from_dict(goal_dict)
			if goal != null:
				goals.append(goal)
	return goals

## Dict → Goal 转换 (公开供外部 loader)
## 字段缺 type 返回 null; 缺 value/priority 用默认值
func _goal_from_dict(d: Dictionary) -> Goal:
	if not d.has("type"):
		return null
	var type_str: String = String(d.get("type", ""))
	var value_int: int = int(d.get("value", 0))
	var priority_str: String = String(d.get("priority", "normal"))
	return Goal.new(type_str, value_int, priority_str)

## 默认 callback: Goal 完成时写入 ExperienceMemory
## type="goal" (与 battle/trick/stuck/bug/design_issue 等并列)
## evidence 包含 type/value/priority/stats_at_completion
## confidence=0.7 (Goal 自动判定, 不是 LLM/AI 主观判断)
func _default_goal_callback(goal: Goal, stats: Dictionary) -> void:
	Qa.experience_memory.record(
		"goal",
		"run_goals",
		goal.description,
		{
			"type": goal.type,
			"value": goal.value,
			"priority": goal.priority,
			"stats_at_completion": stats.duplicate(),
		},
		0.7
	)

func set_run_id(run_id: String) -> void:
	_run_id = run_id
	reset_stats()

## 添加 goal（可重复调用）
func add_goal(type: String, value: int = 0, priority: String = "normal") -> Goal:
	var goal := Goal.new(type, value, priority)
	_goals.append(goal)
	print("RunGoals[%s]: +goal %s" % [_run_id, goal.description])
	return goal

## 清除所有 goals
func clear_goals() -> void:
	_goals.clear()
	_completed_goals.clear()
	_all_completed = false

## 报告一个 stats 更新
func report(key: String, value: Variant) -> void:
	_stats[key] = value
	_check_goals()

## 报告 stats 增量（如 chains_triggered +1）
func increment(key: String, delta: int = 1) -> void:
	var current: int = int(_stats.get(key, 0))
	_stats[key] = current + delta
	_check_goals()

## 记录节点类型访问
func visit_node_type(type: int) -> void:
	var visited: Array = _stats.get("node_types_visited", [])
	if not visited.has(type):
		visited.append(type)
		_stats["node_types_visited"] = visited
	_check_goals()

## 记录场景
func record_scene(scene_name: String) -> void:
	var seq: Array = _stats.get("scene_sequence", [])
	if seq.is_empty() or seq.back() != scene_name:
		seq.append(scene_name)
		_stats["scene_sequence"] = seq

## 检查所有 goals
func _check_goals() -> void:
	for goal in _goals:
		if goal.completed:
			continue
		if goal.check(_stats):
			goal.completed = true
			_completed_goals.append(goal.type)
			print("RunGoals[%s]: ✓ goal 完成: %s" % [_run_id, goal.description])
			# P1.1 Phase 2 Step 3.5 (2026-07-05 17:36): safe emit + 隔离 listener 异常
			# GDScript 4.x 无 native try-catch; 这里手动遍历 connections
			# listener 责任 try 内部防御; helper 处理 invalid callable
			_emit_goal_completed_safe(goal, _stats)
	_check_all_completed()

## 安全 emit goal_completed (P1.1 Phase 2 Step 3.5, 2026-07-05)
## 替代 goal_completed.emit() 直接调用，避免 listener 异常中断 _check_goals
## 注意: GDScript 4.x 无 native try-catch; listener 抛错仍会 propagate
## listener 应自己在内部 try 防御
func _emit_goal_completed_safe(goal: Goal, stats: Dictionary) -> void:
	var connections: Array = goal_completed.get_connections()
	if connections.is_empty():
		return
	for conn in connections:
		var callable: Callable = conn.callable if conn is Dictionary and conn.has("callable") else Callable()
		if callable.is_null() or not callable.is_valid():
			push_warning("RunGoals[%s]: skipping invalid callback" % _run_id)
			continue
		# GDScript 4.x 无 try-catch — caller 责任确保 listener 不抛错
		# 这里 push_warning 让 listener 异常可见于日志, 但仍 propagate 到 _check_goals
		callable.call(goal, stats)

## P1.1 Phase 3 (2026-07-05 17:55): session 策略画像聚合
## 返回当前 run 的策略画像 — AI Player / ExperienceMemory 后续可用作 long-term pattern
## 包含: completion rate + priority breakdown + type breakdown + avg value + elapsed
func summarize_session() -> Dictionary:
	var goals: Array = get_goals()
	var completed: Array = get_completed_goals()
	var total_count: int = goals.size()
	var completed_count: int = completed.size()
	var completion_rate: float = 0.0 if total_count == 0 else float(completed_count) / float(total_count)
	var priority_breakdown := {"high": 0, "normal": 0, "low": 0}
	var completed_by_priority := {"high": 0, "normal": 0, "low": 0}
	var type_breakdown := {}
	var value_sum: int = 0
	for goal in goals:
		priority_breakdown[goal.priority] = int(priority_breakdown.get(goal.priority, 0)) + 1
		if goal.completed:
			completed_by_priority[goal.priority] = int(completed_by_priority.get(goal.priority, 0)) + 1
			type_breakdown[goal.type] = int(type_breakdown.get(goal.type, 0)) + 1
			value_sum += goal.value
	var avg_value: float = 0.0 if completed_count == 0 else float(value_sum) / float(completed_count)
	return {
		"run_id": _run_id,
		"total_goals": total_count,
		"completed_goals": completed_count,
		"completion_rate": completion_rate,
		"priority_breakdown": priority_breakdown,
		"completed_by_priority": completed_by_priority,
		"type_breakdown": type_breakdown,
		"avg_completed_value": avg_value,
		"elapsed_seconds": int(_stats.get("elapsed_seconds", 0)),
		"summary_at_ms": Time.get_ticks_msec(),
	}

## 检查所有 goal 是否都完成
func _check_all_completed() -> void:
	if _goals.is_empty():
		return
	var all_done: bool = true
	for goal in _goals:
		if not goal.completed:
			all_done = false
			break
	_all_completed = all_done

## 所有 goal 是否都完成
func is_all_completed() -> bool:
	return _all_completed

## 是否应该结束（所有 goal 完成 或 max_runtime_seconds 触发）
func should_quit() -> bool:
	if _all_completed:
		return true
	# 也检查 max_runtime
	for goal in _goals:
		if goal.type == "max_runtime_seconds" and goal.completed:
			return true
	return false

## 获取当前 stats
func get_stats() -> Dictionary:
	return _stats.duplicate(true)

## 获取 goals 列表
func get_goals() -> Array[Goal]:
	return _goals.duplicate()

## 获取已完成的 goal 类型列表
func get_completed_goals() -> Array[String]:
	return _completed_goals.duplicate()

## 重置 stats 和 completed goals (P1.1 Phase 2 H8 bugfix 2026-07-05 20:58):
## 公开 API，test_e2e_goal_pipeline.gd 需要调它做 scenario setup
func reset_stats() -> void:
	_stats = {
		"battles_won": 0,
		"battles_lost": 0,
		"cards_collected": 0,
		"chains_triggered": 0,
		"realm": 0,
		"node_types_visited": [],
		"scene_sequence": [],
		"elapsed_seconds": 0,
		"loop_count": 0,
		"victory": false,
		"defeat": false,
	}
	_completed_goals.clear()
	_all_completed = false