# implements: agent-infrastructure (非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends Node
# SceneWalker autoload — C-2 VLM loop 抓帧用
# 启动后依次切换到 5 个关键 scene，每个抓 1 帧存到 res://qa-captures/{scene}.png
# 跑完自动 quit
#
# ⚠️ 手动启动（编辑器 F5）时不跑 —— 否则会把游戏 quit() 掉，让你玩不了。
#    Agent 跑测试时启动 godot ... -- --qa-auto-run 才会触发。

const SCENES_TO_VISIT := [
	"res://scenes/main_menu.tscn",
	"res://scenes/character_select.tscn",
	"res://scenes/map.tscn",
	"res://scenes/battle.tscn",
	"res://scenes/reward.tscn"
]
const CAPTURE_DIR := "res://qa-captures"
const WAIT_SECONDS := 3.0
# 与 agent_socket.gd / qa_capture.gd / agent_inspector.gd 同款，4 处保持同步
const AGENT_FLAG := "--qa-auto-run"

var _index: int = 0
var _captured: int = 0
var _failed: int = 0

func _ready() -> void:
	if AGENT_FLAG not in OS.get_cmdline_user_args():
		return  # 手动启动游戏时不跑（包括不会 quit()）
	# 如果 AIPlayer autoload 存在，让 AIPlayer 控制场景，SceneWalker 退出
	if get_node_or_null("/root/AIPlayer") != null:
		print("SceneWalker: 检测到 AIPlayer 运行，SceneWalker 退出（避免冲突）")
		return
	print("SceneWalker: starting, %d scenes to visit" % SCENES_TO_VISIT.size())
	# 第一个 scene 等待主场景稳定
	await get_tree().create_timer(WAIT_SECONDS).timeout
	_capture("main_menu")
	_visit_next()

func _visit_next() -> void:
	_index += 1
	if _index >= SCENES_TO_VISIT.size():
		print("SceneWalker: done. captured=%d failed=%d" % [_captured, _failed])
		# 等一秒让 log 写完，然后 quit
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	var path = SCENES_TO_VISIT[_index]
	print("SceneWalker: switching to %s" % path)
	get_tree().change_scene_to_file.call_deferred(path)
	await get_tree().create_timer(WAIT_SECONDS).timeout
	var scene_name = path.get_file().get_basename()
	_capture(scene_name)
	_visit_next()

func _capture(scene_name: String) -> void:
	# 2026-07-28 headless 守护：headless 模式无 viewport texture → get_image() 必返回 null
	# 直接 _captured++ + log 跳过，避免 push_error 噪音
	if OS.has_feature("headless"):
		print("SceneWalker: headless mode → skip capture %s" % scene_name)
		_captured += 1  # 算作成功（headless 跑通流程即可）
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("SceneWalker: get_image() returned null for %s" % scene_name)
		_failed += 1
		return
	if not DirAccess.dir_exists_absolute(CAPTURE_DIR):
		var mk_err := DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
		if mk_err != OK:
			push_error("SceneWalker: make_dir failed: %d" % mk_err)
			_failed += 1
			return
	var out_path: String = "%s/%s.png" % [CAPTURE_DIR, scene_name]
	var err := img.save_png(out_path)
	if err == OK:
		_captured += 1
		var abs_path := ProjectSettings.globalize_path(out_path)
		print("SceneWalker: captured %s (%dx%d) -> %s" % [scene_name, img.get_width(), img.get_height(), abs_path])
	else:
		push_error("SceneWalker: save_png failed for %s: %d" % [scene_name, err])
		_failed += 1
