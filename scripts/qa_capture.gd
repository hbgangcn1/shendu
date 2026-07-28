# implements: agent-infrastructure (非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends Node
# ViewportCapture autoload
# 蜃都 VLM loop 的游戏内截帧来源。启动后等几帧确保主场景渲染完，
# 抓一次 viewport 到 res://qa-captures/viewport_capture.png。
# 重启 Godot 会重抓（autoload 每次启动跑一次）。
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

func _ready() -> void:
	if AGENT_FLAG not in OS.get_cmdline_user_args():
		return  # 手动启动游戏时不跑
	# 检测 headless 模式
	var is_headless := OS.has_feature("headless")
	if is_headless:
		print("ViewportCapture: headless mode detected, starting timeout watchdog (%ss)" % HEADLESS_TIMEOUT_SECONDS)
		# 启动超时 watchdog
	await get_tree().create_timer(WAIT_SECONDS).timeout
	_capture()
	if is_headless:
		# headless 下捕获完（或失败）后主动退出，防止卡死
		print("ViewportCapture: headless capture done, quitting")
		get_tree().quit()

func _capture() -> void:
	# 2026-07-28 headless 守护：headless 模式无 viewport texture → get_image() 必返回 null
	# 跳过早退，避免 log 噪音累积（之前 5min 内累积 1 个 ERROR + 占 log 几十行）
	if OS.has_feature("headless"):
		print("ViewportCapture: headless mode → skip get_image()")
		return
	# 用 main viewport 的 texture（get_viewport() 返回 root viewport）
	var img: Image = get_viewport().get_texture().get_image()
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
