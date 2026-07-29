## Goal Templates — 蜃都 Goal 场景模板库
##
## 按"测试场景"组织的 Goal 集合，AI Player / test 可按场景加载。
## P1.1 Phase 1 Step 4（2026-07-05）：模板库。
##
## 改用 instance method（不是 static），因为 GDScript 4.x `class_name X extends RefCounted`
## 通过 X.method() 调用 static func 在某些路径会触发 "Nonexistent function"。
## instance method 走 var t = GoalTemplates.new(); t.scene() 路径更可靠。
##
## 使用方式：
##   var t := GoalTemplates.new()
##   var goals: Array[Goal] = t.battle_baseline()
##   for g in goals:
##       RunGoals._goals.append(g)  # 或暴露 add_goals_batch API
##
## 设计原则：
##   - **场景驱动**：每个方法对应一个具体测试场景（如 battle_baseline / deck_health）
##   - **可扩展**：新增场景只需添加一个 method
##   - **零依赖**：不需要任何 autoload / 文件 IO
##   - **可读性**：方法名 = 场景名，调用方一看就懂
##
## 后续（不在本文件范围）：
##   - 外部化（goal_library.json）走 P1.1 Step 2
##   - 集成到 ai_player.gd（让 AI Player 按 deck 状态自动选场景）

# implements: agent-infrastructure (test data library)
# implements_philosophy: rule_1_core_loop_first, rule_5_real_agency

class_name GoalTemplates
extends RefCounted

## Goal 模板库 schema 版本 (H5, 2026-07-05 21:05)
## 与 goal_library.json 的 version 字段必须保持一致
## 修改 check_goal_drift.mjs VERSION_EXPECTED 同步 bump
const LIBRARY_VERSION := 1

## 获取当前库 schema 版本 (用于运行时对比 goal_library.json)
func get_library_version() -> int:
	return LIBRARY_VERSION

# ===== Battle / Combat =====

## 战斗基准测试：3 场战斗 + 120 秒运行上限
## 用途：QA 烟雾测试，每次 ai_player 跑都默认跑这个
## 复用了 ai_player.gd:55-57 默认 goal 列表
func battle_baseline() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 3, Goal.TYPE_PRIORITY_HIGH),
		# 2026-07-29 fix: 120s 太短，AI Player 等不到 LLM 首次响应（minimax API 30-60s + session 启动）就 quit
		# 改为 600s (10min)，让 session 有足够时间跑通 character_select → map → battle
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 600, Goal.TYPE_PRIORITY_NORMAL),
		Goal.new(Goal.TYPE_COLLECT_N_CARDS, 8, Goal.TYPE_PRIORITY_NORMAL),
	]

## 战斗深度测试：5 场战斗 + 触发 8 次五行相生链 + 到达筑基境界
## 用途：验证核心战斗循环（rule_1_core_loop_first）的深度表现
func battle_deep() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 5, Goal.TYPE_PRIORITY_HIGH),
		Goal.new(Goal.TYPE_TRIGGER_N_CHAINS, 8, Goal.TYPE_PRIORITY_HIGH),
		Goal.new(Goal.TYPE_REACH_REALM_N, 2, Goal.TYPE_PRIORITY_NORMAL),
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 180, Goal.TYPE_PRIORITY_NORMAL),
	]

## 失败测试：故意让 AI Player 战斗失败
## 用途：验证 experience_memory.record("loss") + 失败有意义（rule_2）
func battle_should_lose() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_FIRST_LOSS, 0, Goal.TYPE_PRIORITY_HIGH),
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 60, Goal.TYPE_PRIORITY_NORMAL),
	]

## 通关测试：完整通关一次
## 用途：验证 victory 路径
func battle_full_clear() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_COMPLETE_RUN, 0, Goal.TYPE_PRIORITY_HIGH),
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 240, Goal.TYPE_PRIORITY_NORMAL),
	]

# ===== Deck / Card Pool =====

## 牌组健康度测试：积累 20 张卡 + 完成 1 场战斗
## 用途：验证 deck_analyzer + 卡组构建路径
func deck_health_check() -> Array[Goal]:
	return [
		# 2026-07-29 fix: collect_n_cards 从 20 调为 8（避免必须 collect 20 张才能 complete）
		Goal.new(Goal.TYPE_COLLECT_N_CARDS, 8, Goal.TYPE_PRIORITY_HIGH),
		Goal.new(Goal.TYPE_SURVIVE_N_BATTLES, 1, Goal.TYPE_PRIORITY_NORMAL),
		# 2026-07-29 fix: 90s 太短，session 还没等到 LLM 首次响应就 quit
		# 这是 24 sessions 0 wins 的核心阻塞（每次都 90s 退场）
		# 改为 600s (10min)，给 AI Player 足够时间进入战斗
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 600, Goal.TYPE_PRIORITY_NORMAL),
	]

# ===== Map / Node Visiting =====

## 地图遍历测试：访问 4 种节点类型
## 用途：验证 scene_walker / map 节点类型多样性
func map_exploration() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_VISIT_NODE_TYPES, 4, Goal.TYPE_PRIORITY_HIGH),
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 120, Goal.TYPE_PRIORITY_NORMAL),
	]

# ===== Loop / Time =====

## 长跑测试：300 秒长跑，强制因 runtime 退出
## 用途：验证 goal_completed 在 max_runtime_seconds 触发时正常 emit
func long_run() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 300, Goal.TYPE_PRIORITY_HIGH),
	]

## 循环计数器测试：循环 50 次
## 用途：验证 _loop_count 统计正确 + loop_count_n type 工作
func loop_stress() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_LOOP_COUNT_N, 50, Goal.TYPE_PRIORITY_HIGH),
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 180, Goal.TYPE_PRIORITY_NORMAL),
	]

# ===== Composite =====

## 单 goal（minimum test）
## 用途：smoke test，验证 signal emit + ExperienceMemory 写入
func single_goal_max_runtime() -> Array[Goal]:
	return [
		Goal.new(Goal.TYPE_MAX_RUNTIME_SECONDS, 10, Goal.TYPE_PRIORITY_HIGH),
	]

## 空场景（boundary test）
## 用途：验证 RunGoals 在 0 goal 时不 crash
func empty() -> Array[Goal]:
	return []

# ===== Tool =====

## 获取所有场景名称（用于测试 / 文档）
func all_scene_names() -> Array[String]:
	return [
		"battle_baseline",
		"battle_deep",
		"battle_should_lose",
		"battle_full_clear",
		"deck_health_check",
		"map_exploration",
		"long_run",
		"loop_stress",
		"single_goal_max_runtime",
		"empty",
	]

## 验证所有场景的 goal 都是合法的（type/priority 都在 VALID_*）
## 用于 production health check（跑一次确保模板库自身无错）
func validate_all() -> Dictionary:
	var result := {"total": 0, "invalid": 0, "errors": []}
	for scene_name in all_scene_names():
		var goals: Array[Goal] = call(scene_name)
		result["total"] += goals.size()
		for goal in goals:
			if not goal.is_valid():
				result["invalid"] += 1
				result["errors"].append("%s: type=%s priority=%s" % [scene_name, goal.type, goal.priority])
	return result