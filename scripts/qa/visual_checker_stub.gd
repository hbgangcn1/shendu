## Visual Checker Stub — 画面审核触发器
## 负责在关键场景截图并保存到 review 目录，供外部 VLM 分析
## 只在 --qa-auto-run flag 存在时启用

# implements: design/NO_TEXT_DESIGN_PRINCIPLE.md
# implements_philosophy: rule_9_progressive_disclosure
# agent-infrastructure: loop-engineering

extends Node

const OUTPUT_DIR := "user://qa-captures/"
const SCENES_TO_CAPTURE: Array[String] = [
	"MainMenu",
	"CharacterSelect",
	"GameMapScene",
	"BattleScene",
	"RewardScene",
	"ShopScene",
	"SettlementScene",
	"VictoryScene",
]

## 需要每回合截图的场景
const PER_TURN_CAPTURE_SCENES: Array[String] = ["BattleScene"]

var _captured_scenes: Array[String] = []
var _last_turn_number: int = -1

func _ready() -> void:
	if not _is_qa_mode():
		return
	print("VisualChecker: 画面审核触发器已启动")
	# 订阅场景切换事件
	get_tree().node_added.connect(_on_node_added)

func _is_qa_mode() -> bool:
	return OS.get_cmdline_user_args().has("--qa-auto-run")

func _on_node_added(node: Node) -> void:
	if node == get_tree().current_scene:
		var scene_name: String = node.name
		if scene_name in SCENES_TO_CAPTURE and scene_name not in _captured_scenes:
			# 等待场景渲染一帧
			await get_tree().process_frame
			await get_tree().process_frame
			_capture_scene(scene_name)
			# 连接战斗回合信号
			if scene_name in PER_TURN_CAPTURE_SCENES:
				_connect_battle_signals(node)

## 连接战斗管理器信号，实现每回合截图
func _connect_battle_signals(scene: Node) -> void:
	if not scene.has_method("_start_battle"):
		return
	var bm = scene.get("battle_manager")
	if bm == null:
		return
	if bm.has_signal("turn_started") and not bm.turn_started.is_connected(_on_battle_turn_started):
		bm.turn_started.connect(_on_battle_turn_started)
	if bm.has_signal("battle_ended") and not bm.battle_ended.is_connected(_on_battle_ended):
		bm.battle_ended.connect(_on_battle_ended)

func _on_battle_turn_started(turn_number: int) -> void:
	if turn_number == _last_turn_number:
		return
	_last_turn_number = turn_number
	# 等待动画和 UI 更新
	await get_tree().create_timer(0.5).timeout
	_capture_scene("BattleScene_Turn%d" % turn_number)

func _on_battle_ended(_result: int) -> void:
	await get_tree().create_timer(0.3).timeout
	_capture_scene("BattleScene_End")

func _capture_scene(scene_name: String) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		push_warning("VisualChecker: viewport 为空")
		return

	# headless 模式下无法获取渲染贴图，跳过截图
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		print("VisualChecker: headless 模式跳过 %s 截图" % scene_name)
		return

	var img: Image = texture.get_image()
	if img == null:
		push_warning("VisualChecker: 截图失败（可能在 headless 模式）")
		return

	var dir := DirAccess.open("user://")
	if dir == null:
		push_warning("VisualChecker: 无法打开 user://")
		return
	dir.make_dir_recursive(OUTPUT_DIR)

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file_name := "%s_%s.png" % [scene_name, timestamp]
	var path := OUTPUT_DIR + file_name

	var err := img.save_png(path)
	if err == OK:
		_captured_scenes.append(scene_name)
		print("VisualChecker: 已截图 %s" % path)
	else:
		push_warning("VisualChecker: 保存截图失败 err=%d" % err)
