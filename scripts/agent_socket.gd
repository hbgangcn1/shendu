# implements: agent-infrastructure (非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends Node
# AgentSocket — agent → game input pipe
# 监听 res://.agent_input.json 文件，agent 写入 JSON 命令后由本 autoload 读取并执行
# 命令格式:
#   {"action":"click","x":640,"y":360}
#   {"action":"key","key":"space"}            # key 名称或 keycode
#   {"action":"capture","path":"res://foo.png"}
#   {"action":"change_scene","path":"res://scenes/main_menu.tscn"}
# 设计：文件式 (非 socket)，简单可靠，方便调试（cat 一下就知道发了什么）

const INPUT_FILE := "res://.agent_input.json"
const POLL_INTERVAL := 0.1  # 100ms 轮询
# 与 qa_capture.gd / scene_walker.gd / agent_inspector.gd 同款，4 处保持同步
const AGENT_FLAG := "--qa-auto-run"

var _exec_count: int = 0
# 2026-07-22 修复 AI Player stuck 100s bug：
# 战斗结束时设 _input_paused = true，跳过 _execute。
# change_scene 和 quit 仍允许（避免 AI Player 卡死时无法救场）
var _input_paused: bool = false

## 暂停 / 恢复 agent input 处理（战斗结束 fade 期问避免 LLM click 触发死循环）
func set_input_paused(paused: bool) -> void:
	_input_paused = paused
	print("AgentSocket: input_paused = %s" % paused)

func _ready() -> void:
	if AGENT_FLAG not in OS.get_cmdline_user_args():
		return  # 手动启动游戏时不轮询 agent input
	print("AgentSocket: watching %s" % INPUT_FILE)
	# 启动时清空旧文件
	_clear_file()

func _process(_delta: float) -> void:
	if not FileAccess.file_exists(INPUT_FILE):
		return
	var f := FileAccess.open(INPUT_FILE, FileAccess.READ)
	if f == null:
		return
	var content := f.get_as_text()
	f.close()
	# 读取后立即清空（agent 写新文件即可再次触发）
	_clear_file()
	if content.strip_edges().is_empty():
		return
	var json = JSON.parse_string(content)
	if json == null or not (json is Dictionary):
		push_error("AgentSocket: invalid JSON: %s" % content)
		return
	_execute(json as Dictionary)

func _clear_file() -> void:
	if FileAccess.file_exists(INPUT_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INPUT_FILE))

func _execute(cmd: Dictionary) -> void:
	# 2026-07-22: input_paused 时跳过 click/key，但保留 change_scene / quit / capture
	# 避免 LLM 在 fade 期间发 click 触发已死信号链路造成 100s stuck
	if _input_paused:
		var action: String = cmd.get("action", "")
		if action in ["change_scene", "quit", "capture"]:
			pass  # 允许
		else:
			print("AgentSocket: paused, skip action=%s" % action)
			return
	var action: String = cmd.get("action", "")
	match action:
		"click":
			_do_click(int(cmd.get("x", 0)), int(cmd.get("y", 0)))
		"key":
			_do_key(String(cmd.get("key", "")))
		"capture":
			_do_capture(String(cmd.get("path", "res://agent_capture.png")))
		"change_scene":
			_do_change_scene(String(cmd.get("path", "")))
		"quit":
			get_tree().quit()
		_:
			push_error("AgentSocket: unknown action: %s" % action)

func _do_click(x: int, y: int) -> void:
	# 模拟鼠标左键按下+释放
	var ev_down := InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.position = Vector2(x, y)
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.position = Vector2(x, y)
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	_exec_count += 1
	print("AgentSocket[%d]: click (%d, %d)" % [_exec_count, x, y])

func _do_key(key_name: String) -> void:
	var keycode: int = OS.find_keycode_from_string(key_name) if key_name != "" else KEY_NONE
	if keycode == KEY_NONE:
		push_warning("AgentSocket: unknown key: %s" % key_name)
		return
	var ev_down := InputEventKey.new()
	ev_down.keycode = keycode
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	var ev_up := InputEventKey.new()
	ev_up.keycode = keycode
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	_exec_count += 1
	print("AgentSocket[%d]: key %s (code %d)" % [_exec_count, key_name, keycode])

func _do_capture(path: String) -> void:
	# 2026-07-28 headless 守护：headless 模式无 viewport texture
	if OS.has_feature("headless"):
		print("AgentSocket: headless mode → skip capture")
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("AgentSocket: get_image() returned null")
		return
	var err: int = img.save_png(path)
	if err == OK:
		_exec_count += 1
		print("AgentSocket[%d]: capture -> %s (%dx%d)" % [_exec_count, path, img.get_width(), img.get_height()])
	else:
		push_error("AgentSocket: save_png failed: %d" % err)

func _do_change_scene(scene_path: String) -> void:
	if scene_path.is_empty():
		push_error("AgentSocket: change_scene needs 'path'")
		return
	get_tree().change_scene_to_file.call_deferred(scene_path)
	_exec_count += 1
	print("AgentSocket[%d]: change_scene -> %s" % [_exec_count, scene_path])
