# QA registry (2026-10-07): production project.godot 不再 autoload QA 单例后，
# 原 12 个裸单例名 (RunGoals. 等) 全部改为经 Qa.<snake> 访问。
# 由 debug_runner.ensure_qa_nodes() 在挂载完成后调用 bind_all(tree) 绑定。
class_name Qa

static var viewport_capture: Node
static var scene_walker: Node
static var agent_socket: Node
static var agent_inspector: Node
static var run_goals: Node
static var experience_memory: Node
static var agent_input: Node
static var agent_actions: Node
static var reward_evaluator: Node
static var deck_analyzer: Node
static var ai_player: Node
static var visual_checker: Node

static func bind_all(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	viewport_capture = tree.root.get_node_or_null("ViewportCapture")
	scene_walker = tree.root.get_node_or_null("SceneWalker")
	agent_socket = tree.root.get_node_or_null("AgentSocket")
	agent_inspector = tree.root.get_node_or_null("AgentInspector")
	run_goals = tree.root.get_node_or_null("RunGoals")
	experience_memory = tree.root.get_node_or_null("ExperienceMemory")
	agent_input = tree.root.get_node_or_null("AgentInput")
	agent_actions = tree.root.get_node_or_null("AgentActions")
	reward_evaluator = tree.root.get_node_or_null("RewardEvaluator")
	deck_analyzer = tree.root.get_node_or_null("DeckAnalyzer")
	ai_player = tree.root.get_node_or_null("AIPlayer")
	visual_checker = tree.root.get_node_or_null("VisualChecker")
