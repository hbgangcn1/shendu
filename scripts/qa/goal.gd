## Goal — 蜃都 Run Goal 单个数据结构
##
## 拆自 scripts/qa/run_goals.gd 的 inner class（2026-07-05 P1.1 Phase 1 Step 1）。
## 作为 class_name 全局可见；run_goals.gd 不再持有内联定义。
##
## 单个 Goal 描述一个完成条件，绑定 stats 字典判定（check() 方法）。
## 9 种 Goal type（参见下面 TYPE_* 常量）：
##   - TYPE_SURVIVE_N_BATTLES    完成 N 场战斗（stats.battles_won）
##   - TYPE_COMPLETE_RUN         通关或被击败（stats.victory OR stats.defeat）
##   - TYPE_FIRST_LOSS           第一次战斗失败（stats.defeat）
##   - TYPE_COLLECT_N_CARDS      卡牌池达到 N 张（stats.cards_collected）
##   - TYPE_TRIGGER_N_CHAINS     触发 N 次五行相生链（stats.chains_triggered）
##   - TYPE_REACH_REALM_N        进入第 N 个境界（stats.realm）
##   - TYPE_VISIT_NODE_TYPES     访问 N 种节点类型（stats.node_types_visited）
##   - TYPE_MAX_RUNTIME_SECONDS  运行上限 N 秒（stats.elapsed_seconds）
##   - TYPE_LOOP_COUNT_N         循环次数达到 N（stats.loop_count）
##
## 设计哲学：
##   - Goal 是「agency 表达」而不是「任务强加」（implements rule_5_real_agency）
##   - AI Player 可以拒绝 / 修改 Goal（不是被驱赶完成）
##   - priority 字段允许不同紧急度的 Goal 共存
##
## 后续 Phase：
##   - Phase 1 Step 2：外部配置加载（goal_library.yaml）
##   - Phase 1 Step 3：ExperienceMemory 自动写入 callback
##   - Phase 1 Step 4：Goal 模板库（goal_templates.gd，可选）

# implements: agent-infrastructure
# implements_philosophy: rule_5_real_agency
# agent-infrastructure: loop-engineering

class_name Goal
extends RefCounted

# ===== 字段 =====

## Goal 类型（9 种常量之一）
var type: String

## Goal 数值参数（如"3 场战斗"的 3）
var value: int = 0

## 优先级："high" | "normal" | "low"
var priority: String = TYPE_PRIORITY_NORMAL

## 是否已完成（运行中由 RunGoals 自动更新）
var completed: bool = false

## 人类可读描述（_init 时自动生成，可后续覆盖）
var description: String = ""

# ===== 类型常量（避免拼写错误）=====

const TYPE_SURVIVE_N_BATTLES := "survive_n_battles"
const TYPE_COMPLETE_RUN := "complete_run"
const TYPE_FIRST_LOSS := "first_loss"
const TYPE_COLLECT_N_CARDS := "collect_n_cards"
const TYPE_TRIGGER_N_CHAINS := "trigger_n_chains"
const TYPE_REACH_REALM_N := "reach_realm_n"
const TYPE_VISIT_NODE_TYPES := "visit_node_types"
const TYPE_MAX_RUNTIME_SECONDS := "max_runtime_seconds"
const TYPE_LOOP_COUNT_N := "loop_count_n"

const TYPE_PRIORITY_HIGH := "high"
const TYPE_PRIORITY_NORMAL := "normal"
const TYPE_PRIORITY_LOW := "low"

## 所有合法 type 列表（用于配置校验）
const VALID_TYPES: PackedStringArray = [
	TYPE_SURVIVE_N_BATTLES,
	TYPE_COMPLETE_RUN,
	TYPE_FIRST_LOSS,
	TYPE_COLLECT_N_CARDS,
	TYPE_TRIGGER_N_CHAINS,
	TYPE_REACH_REALM_N,
	TYPE_VISIT_NODE_TYPES,
	TYPE_MAX_RUNTIME_SECONDS,
	TYPE_LOOP_COUNT_N,
]

const VALID_PRIORITIES: PackedStringArray = [
	TYPE_PRIORITY_HIGH,
	TYPE_PRIORITY_NORMAL,
	TYPE_PRIORITY_LOW,
]

# ===== 构造函数 =====

func _init(p_type: String, p_value: int = 0, p_priority: String = TYPE_PRIORITY_NORMAL) -> void:
	type = p_type
	value = p_value
	priority = p_priority
	description = _describe()

# ===== 描述生成 =====

## 生成人类可读描述（自动调用，可被外部覆盖）
func _describe() -> String:
	match type:
		TYPE_SURVIVE_N_BATTLES:
			return "完成 %d 场战斗" % value
		TYPE_COMPLETE_RUN:
			return "通关或被击败"
		TYPE_FIRST_LOSS:
			return "第一次战斗失败"
		TYPE_COLLECT_N_CARDS:
			return "卡牌池达到 %d 张" % value
		TYPE_TRIGGER_N_CHAINS:
			return "触发 %d 次五行相生链" % value
		TYPE_REACH_REALM_N:
			return "进入第 %d 个境界" % value
		TYPE_VISIT_NODE_TYPES:
			return "访问 %d 种节点类型" % value
		TYPE_MAX_RUNTIME_SECONDS:
			return "运行上限 %d 秒" % value
		TYPE_LOOP_COUNT_N:
			return "循环次数达到 %d" % value
		_:
			# 未知 type：返回原字符串便于调试（不抛错，避免 1 个错 type 让整个 run 挂掉）
			return type

# ===== 完成判定 =====

## 根据 stats 字典判定 Goal 是否完成
## stats 字段约定：
##   - battles_won, battles_lost (int)
##   - cards_collected, chains_triggered, realm (int)
##   - elapsed_seconds, loop_count (int)
##   - node_types_visited (Array[int])
##   - victory, defeat (bool)
func check(stats: Dictionary) -> bool:
	match type:
		TYPE_SURVIVE_N_BATTLES:
			return int(stats.get("battles_won", 0)) >= value
		TYPE_COMPLETE_RUN:
			return bool(stats.get("victory", false)) or bool(stats.get("defeat", false))
		TYPE_FIRST_LOSS:
			return bool(stats.get("defeat", false))
		TYPE_COLLECT_N_CARDS:
			return int(stats.get("cards_collected", 0)) >= value
		TYPE_TRIGGER_N_CHAINS:
			return int(stats.get("chains_triggered", 0)) >= value
		TYPE_REACH_REALM_N:
			return int(stats.get("realm", 0)) >= value
		TYPE_VISIT_NODE_TYPES:
			var visited = stats.get("node_types_visited", [])
			return visited.size() >= value
		TYPE_MAX_RUNTIME_SECONDS:
			return int(stats.get("elapsed_seconds", 0)) >= value
		TYPE_LOOP_COUNT_N:
			return int(stats.get("loop_count", 0)) >= value
	return false

# ===== 验证工具 =====

## 返回 true 表示 type/priority 是合法值
func is_valid() -> bool:
	return type in VALID_TYPES and priority in VALID_PRIORITIES

## 用于序列化（如日志 / ExperienceMemory）
func to_dict() -> Dictionary:
	return {
		"type": type,
		"value": value,
		"priority": priority,
		"completed": completed,
		"description": description,
	}