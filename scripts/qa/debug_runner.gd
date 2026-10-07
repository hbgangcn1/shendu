# implements: agent-infrastructure (debug script — 非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends SceneTree

# QA bootstrap (2026-10-07): production project.godot 不再 autoload QA 单例 ——
# 普通玩家启动只有 6 个游戏单例。QA/headless 运行经 ensure_qa_nodes() 恢复
# 12 个 QA 节点，以 --qa-auto-run 为门（与 agent_socket.gd 的 AGENT_FLAG 同款模式）。
# QA 入口：godot -s res://scripts/qa/debug_runner.gd -- --qa-auto-run
# （-s 下工程 autoload 照常加载，QA 节点挂到 /root 上，
# get_node_or_null("/root/AgentSocket") 类查找保持可用）。
const AGENT_FLAG := "--qa-auto-run"

# 挂载顺序：RunGoals / ExperienceMemory / AgentInput / AgentActions 必须在
# AIPlayer 及其他消费者之前挂载 —— AIPlayer._ready() 内直接调用
# Qa.run_goals / Qa.experience_memory (set_run_id, get_goals, goal_completed),
# 而 add_child 会同步触发被挂节点的 _ready，此时 bind_all 尚未跑完，
# 因此被依赖的 4 个节点必须先挂载，且每次 add_child 后增量 bind 一次，
# 保证消费者 _ready 里 Qa.* 已可用；循环结束后再全量 bind_all 一次兜底。
const QA_SINGLETONS: Array = [
	["ViewportCapture", "res://scripts/qa_capture.gd"],
	["SceneWalker", "res://scripts/scene_walker.gd"],
	["AgentSocket", "res://scripts/agent_socket.gd"],
	["AgentInspector", "res://scripts/agent_inspector.gd"],
	["RunGoals", "res://scripts/qa/run_goals.gd"],
	["ExperienceMemory", "res://scripts/qa/experience_memory.gd"],
	["AgentInput", "res://scripts/qa/agent_input.gd"],
	["AgentActions", "res://scripts/qa/agent_actions.gd"],
	["RewardEvaluator", "res://scripts/qa/reward_evaluator.gd"],
	["DeckAnalyzer", "res://scripts/qa/deck_analyzer.gd"],
	["AIPlayer", "res://scripts/qa/ai_player.gd"],
	["VisualChecker", "res://scripts/qa/visual_checker_stub.gd"],
]

static func is_qa_mode() -> bool:
	return AGENT_FLAG in OS.get_cmdline_user_args()

# flag 不在 → 返回 0 且一个节点也不加（production 行为：零 QA 常驻）。
# flag 在 → 按上表顺序 load + add_child 到 tree.root，返回实际挂载数（重复调用幂等）。
static func ensure_qa_nodes(tree: SceneTree) -> int:
	if not is_qa_mode():
		print("QA bootstrap: --qa-auto-run absent → skip QA nodes (production: 6 game singletons only)")
		return 0
	var root: Window = tree.root
	var added: int = 0
	for entry in QA_SINGLETONS:
		var node_name: String = entry[0]
		var script_path: String = entry[1]
		if root.get_node_or_null(node_name) != null:
			continue
		if not ResourceLoader.exists(script_path):
			push_warning("QA bootstrap: missing script %s for %s" % [script_path, node_name])
			continue
		var qa_script: Script = load(script_path) as Script
		if qa_script == null or not qa_script.can_instantiate():
			push_warning("QA bootstrap: cannot instantiate %s" % script_path)
			continue
		var node: Node = qa_script.new() as Node
		if node == null:
			push_warning("QA bootstrap: script %s is not a Node" % script_path)
			continue
		node.name = node_name
		root.add_child(node)
		added += 1
		# 增量绑定：add_child 已同步触发该节点的 _ready，后续挂载的消费者
		# (如 AIPlayer._ready) 在 _ready 内即可用 Qa.run_goals 等先行节点。
		Qa.bind_all(tree)
	Qa.bind_all(tree)
	print("QA bootstrap: --qa-auto-run present → mounted %d QA nodes" % added)
	return added

func _initialize() -> void:
	# QA auto-run 入口：flag 在才动态挂载 12 个 QA 节点（production 默认零挂载）
	ensure_qa_nodes(self)
	print("DebugRunner _initialize called")
	var gs: Node = get_root().get_node_or_null("GameState")
	if gs == null:
		print("GameState NOT found at /root/GameState")
		print("Root children:")
		for child in get_root().get_children():
			print("  %s (%s)" % [child.name, child.get_class()])
		quit()
		return

	print("GameState FOUND at /root/GameState")
	print("Class: %s" % gs.get_class())
	print("Script: %s" % gs.get_script().resource_path)

	# List all properties
	var props: Array = gs.get_property_list()
	for prop in props:
		var name: Variant = prop.name
		var usage: Variant = prop.usage
		var type: Variant = prop.type
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			print("SCRIPT_VAR: %s (usage=%d, type=%d)" % [name, usage, type])
		else:
			print("OTHER: %s (usage=%d, type=%d)" % [name, usage, type])
	
	# Check specific properties
	for key in ["hp", "max_hp", "spirit_stones", "deck", "collection", "hand", "current_realm", "visited_node_ids", "player_name", "character_id", "dao_xing", "mo_nian", "current_node_id", "game_map", "is_boss_defeated", "deck_max_size", "deck_removal_count", "total_dao_xing"]:
		if gs.has(key):
			var val: Variant = gs.get(key)
			print("%s = %s (type=%s)" % [key, val, typeof(val)])
		else:
			print("%s NOT FOUND" % key)
	
	quit()
