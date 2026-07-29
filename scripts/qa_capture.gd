# implements: agent-infrastructure (非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends Node
# ViewportCapture autoload
# 蜃都 VLM loop 的游戏内截帧来源。启动后等几帧确保主场景渲染完，
# 抓一次 viewport 到 res://qa-captures/viewport_capture.png。
# 重启 Godot 会重抓（autoload 每次启动跑一次）。
# 2026-07-29 fix: scene change 时也重抓（之前只 _ready 抓一次 → 5 天 stale）
#
# ⚠️ 手动启动（编辑器 F5）时不跑，避免在用户玩的时候偷偷写文件。
#    Agent 跑测试时启动 godot ... -- --qa-auto-run 才会触发。

const CAPTURE_DIR := "res://qa-captures"
const CAPTURE_NAME := "viewport_capture.png"
const WAIT_SECONDS := 2.0  # 给主场景时间加载/渲染
# headless mode 下的超时兜底：2026-07-26 修复 headless hang — 30s 后主动 quit
const HEADLESS_TIMEOUT_SECONDS := 30.0
# 与 agent_socket.gd / scene_walker.gd / agent_inspector.gd 同款，4 处保持同步
const AGENT_FLAG := "--qa-auto-run"

var _last_captured_scene: String = ""
var _is_agent_mode: bool = false

# 2026-07-29 v2: 双重 headless 检测
# OS.has_feature("headless") 在 Godot 4.7 + "--headless --audio-driver Dummy" 启动时返回 false
# 必须同时检查 DisplayServer.get_name() == "headless" + --headless 在 cmdline_args
func _is_headless_mode() -> bool:
	if OS.has_feature("headless"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	for arg in OS.get_cmdline_args():
		if arg == "--headless":
			return true
	return false

func _ready() -> void:
	if AGENT_FLAG not in OS.get_cmdline_user_args():
		return  # 手动启动游戏时不跑
	_is_agent_mode = true
	# 检测 headless 模式
	var is_headless := _is_headless_mode()
	if is_headless:
		print("ViewportCapture: headless mode detected, starting timeout watchdog (%ss)" % HEADLESS_TIMEOUT_SECONDS)
		# Hook scene change 立即重抓（之前只 _ready 抓一次 → viewport_capture.png 持续 stale）
		if get_tree():
			get_tree().connect("tree_changed", Callable(self, "_on_tree_changed"))
		# 2026-07-29 v3: 不要立即 quit() — 会杀 AIPlayer session
		# 改为 HEADLESS_TIMEOUT_SECONDS watchdog 在 _process 里超时再 quit
		# qa-orchestrator 本身用 --quit-after 100s 强杀，QA capture 不需要主动 quit
	await get_tree().create_timer(WAIT_SECONDS).timeout
	_capture()

func _on_tree_changed() -> void:
	if not _is_agent_mode:
		return
	var tree := get_tree()
	if tree == null:
		return
	# 2026-07-29 fix: 等 2 帧让 scene 切换完成（change_scene_to_file 是 deferred async）
	# 否则会抓切换前旧 scene 的 viewport
	await get_tree().process_frame
	await get_tree().process_frame
	var current := tree.current_scene
	if current == null:
		return
	var scene_path: String = current.scene_file_path
	if scene_path != "" and scene_path != _last_captured_scene:
		_last_captured_scene = scene_path
		print("ViewportCapture: scene change → ", scene_path, " → recapture")
		_capture()

func _capture() -> void:
	# 2026-07-28 headless 守护：headless 模式无 viewport texture → get_image() 必返回 null
	# 2026-07-29 fix: 即使 headless 也要写一个 black placeholder（拿真实 viewport size）
	# 否则 vlm_request 一直引用 stale viewport_capture.png（5 天前的截图）
	# → minimax thought 里 viewport_mismatch warning 持续存在 → 坐标缩放错
	# 2026-07-29 v3: 实际上 Godot 4.7 headless 模式下 get_texture().get_image() **可用**
	# 只是需要等几帧渲染。先尝试真实捕获，失败才 fallback 到 placeholder。
	var img: Image = null
	if _is_headless_mode():
		# headless 模式：先尝试真实捕获 viewport texture
		var texture := get_viewport().get_texture()
		if texture:
			img = texture.get_image()
		if img:
			print("ViewportCapture: headless → captured real viewport (%dx%d)" % [img.get_width(), img.get_height()])
		else:
			print("ViewportCapture: headless → get_image() returned null, fallback to black placeholder")
	if img == null:
		# fallback: 写 black placeholder
		var vp_rect := get_viewport().get_visible_rect()
		var w := int(vp_rect.size.x)
		var h := int(vp_rect.size.y)
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color.BLACK)
		print("ViewportCapture: headless → fallback black placeholder (%dx%d)" % [w, h])
	else:
		img = get_viewport().get_texture().get_image()
	if img == null:
		push_error("ViewportCapture: get_image() returned null")
		return

	# 确保输出目录存在
	if not DirAccess.dir_exists_absolute(CAPTURE_DIR):
		var mk_err := DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
		if mk_err != OK:
			push_error("ViewportCapture: make_dir failed: %d" % mk_err)
			return

	var path := "%s/%s" % [CAPTURE_DIR, CAPTURE_NAME]
	var err := img.save_png(path)
	if err == OK:
		var abs_path := ProjectSettings.globalize_path(path)
		print("ViewportCapture: saved %s (%dx%d) -> %s" % [path, img.get_width(), img.get_height(), abs_path])
	else:
		push_error("ViewportCapture: save_png failed: %d" % err)