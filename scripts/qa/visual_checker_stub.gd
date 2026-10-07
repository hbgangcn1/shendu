## Visual Checker Stub — 画面审核触发器
## 负责在关键场景截图并保存到 review 目录，供外部 VLM 分析
## 只在 --qa-auto-run flag 存在时启用

# implements: design/NO_TEXT_DESIGN_PRINCIPLE.md
# implements_philosophy: rule_9_progressive_disclosure
# agent-infrastructure: loop-engineering

extends Node

const OUTPUT_DIR := "user://qa-captures/"
const OUTPUT_DIR_PREFIX := "user://qa-captures/"
const DEFAULT_RUN_ID := "default"
const RUN_ID_FLAG := "--run-id"
const MANIFEST_NAME := "manifest.json"
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
	var bm: Variant = scene.get("battle_manager")
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
	var output_dir: String = _output_dir()
	dir.make_dir_recursive(output_dir)

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file_name := "%s_%s.png" % [scene_name, timestamp]
	var path := output_dir + file_name

	var err := img.save_png(path)
	if err == OK:
		_captured_scenes.append(scene_name)
		print("VisualChecker: 已截图 %s" % path)
		_append_manifest(output_dir, path, scene_name, timestamp)
	else:
		push_warning("VisualChecker: 保存截图失败 err=%d" % err)

## 与 QaPaths.run_id() 同规则读取 run id：--run-id <id> 或 --run-id=<id>，缺省为 "default"
func _run_id() -> String:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var idx: int = 0
	while idx < user_args.size():
		var arg: String = user_args[idx]
		if arg == RUN_ID_FLAG and idx + 1 < user_args.size():
			var val: String = _sanitize_run_id(user_args[idx + 1])
			if val != "":
				return val
			return DEFAULT_RUN_ID
		if arg.begins_with(RUN_ID_FLAG + "="):
			var val2: String = _sanitize_run_id(arg.get_slice("=", 1))
			if val2 != "":
				return val2
			return DEFAULT_RUN_ID
		idx += 1
	return DEFAULT_RUN_ID

func _sanitize_run_id(raw: String) -> String:
	var val: String = raw.strip_edges()
	if val == "" or val.begins_with("-"):
		return ""
	val = val.replace("/", "_").replace("\\", "_").replace("..", "_")
	return val

## run-scoped 截图目录：default 沿用旧路径，其余为 user://qa-captures/<R>/
func _output_dir() -> String:
	var r: String = _run_id()
	if r == DEFAULT_RUN_ID:
		return OUTPUT_DIR
	return OUTPUT_DIR_PREFIX + r + "/"

## 每次截图后向该 run 目录的 manifest.json 追加一行（path/scene/turn/ts）
func _append_manifest(output_dir: String, path: String, scene_name: String, timestamp: String) -> void:
	var turn: int = _capture_turn(scene_name)
	var entry := {
		"path": path,
		"scene": scene_name,
		"turn": turn,
		"ts": Time.get_unix_time_from_system(),
		"timestamp": timestamp,
	}
	var manifest_path: String = output_dir + MANIFEST_NAME
	var mf: FileAccess
	if FileAccess.file_exists(manifest_path):
		mf = FileAccess.open(manifest_path, FileAccess.READ_WRITE)
	else:
		mf = FileAccess.open(manifest_path, FileAccess.WRITE)
	if mf == null:
		push_warning("VisualChecker: 无法写入 manifest")
		return
	mf.seek_end()
	mf.store_string(JSON.stringify(entry) + "\n")
	mf.close()

func _capture_turn(scene_name: String) -> int:
	if scene_name.begins_with("BattleScene_Turn"):
		var suffix: String = scene_name.trim_prefix("BattleScene_Turn")
		if suffix.is_valid_int():
			return suffix.to_int()
	if _last_turn_number >= 0:
		return _last_turn_number
	return 0
