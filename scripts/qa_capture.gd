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
	# 2026-07-30 fix: 移除重复的 get_image() 调用（bug 导致 Parameter 't' is null）
	# 2026-07-31 fix: 【关键】非 headless 路径也写黑图 — 因为 if _is_headless_mode() 永远不进 headless 分支，
	#   导致 img 仍为 null，然后 fallback 写黑图。原本这条分支是给 headless 失败兜底，
	#   但 _capture() 设计目的就是为了拿真实 viewport（不然 ai_player_client 截图发给 minimax 没意义）。
	#   修复：非 headless 模式下，先 await process_frame 让 viewport 渲染，然后强制 get_image()，失败才写 placeholder + warning
	var img: Image = null
	var is_black := false
	if _is_headless_mode():
		# headless 模式：尝试真实捕获 viewport texture
		# 2026-08-08 architectural reality: Godot 4.7 --headless 强制 dummy renderer，
		# texture_2d_get 内部 handle 永远 null → get_image() 必返回 null
		# force_draw() / frame_post_draw 在 dummy 下都是 no-op，无法绕过
		# 唯一可行路径：把 scene + UI 信息写进 state.json（不再依赖视觉）
		var texture := get_viewport().get_texture()
		if texture:
			img = texture.get_image()
		if img:
			print("ViewportCapture: headless → captured real viewport (%dx%d)" % [img.get_width(), img.get_height()])
		else:
			print("ViewportCapture: headless → dummy renderer returns null, fallback to black placeholder")
	else:
		# 非 headless（2026-07-31）：Godot 4.7 GUI 模式 viewport texture 可用 — 必须拿真实画面给 minimax
		# 7/31 验证：5:36 force-run non-headless session 后，agent_state.json viewport=1920x1218 但
		# viewport_capture.png 仍 11935 字节黑图（因为下面 if img==null fallback 分支被执行）。
		# 修：await process_frame 让 viewport 完成渲染 → force get_image() → 失败 push_error + return（不写黑图）
		await RenderingServer.frame_post_draw
		var texture2 := get_viewport().get_texture()
		if texture2:
			img = texture2.get_image()
		if img:
			print("ViewportCapture: non-headless → captured real viewport (%dx%d)" % [img.get_width(), img.get_height()])
		else:
			push_error("ViewportCapture: non-headless get_image() returned null — display 异常，不写黑图避免误导 minimax")
			return
	if img == null:
		# headless fallback: 写 black placeholder 拿真实 viewport size
		var vp_rect := get_viewport().get_visible_rect()
		var w := int(vp_rect.size.x)
		var h := int(vp_rect.size.y)
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color.BLACK)
		is_black = true
		print("ViewportCapture: headless → fallback black fill (%dx%d)" % [w, h])

	# 输出目录按 run-id 隔离（默认 run 与旧路径完全一致）
	var capture_dir: String = QaPaths.capture_dir()
	if not DirAccess.dir_exists_absolute(capture_dir):
		var mk_err := DirAccess.make_dir_recursive_absolute(capture_dir)
		if mk_err != OK:
			push_error("ViewportCapture: make_dir failed: %d" % mk_err)
			return

	var path := capture_dir + CAPTURE_NAME
	var err := img.save_png(path)
	if err == OK:
		var abs_path := ProjectSettings.globalize_path(path)
		print("ViewportCapture: saved %s (%dx%d) -> %s" % [path, img.get_width(), img.get_height(), abs_path])
		if is_black:
			var mf := FileAccess.open(path + ".black", FileAccess.WRITE)
			if mf != null:
				mf.close()
	else:
		push_error("ViewportCapture: save_png failed: %d" % err)