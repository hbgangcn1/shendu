## 战斗场景截图工具运行器（VLM QA 输入）
# 被 screenshot_battle_scene.tscn 使用
# usage: godot --headless --path C:\Users\hbgan\Projects\shendu --scene res://tools/screenshot_battle_scene.tscn --quit

extends Node

const CAPTURE_DIR := "res://qa-captures"

var _frames: int = 0

func _ready() -> void:
	print("[screenshot_battle_runner] initializing GameState...")

	# Initialize minimal GameState so battle_demo can run
	GameState.reset_run()
	GameState.character_id = "chenmo"
	GameState.max_hp = 80
	GameState.hp = 80
	GameState.current_realm = 0
	GameState.current_node_id = "start"
	GameState.visited_node_ids = []

	print("[screenshot_battle_runner] loading battle_demo...")
	var packed: PackedScene = load("res://scenes/battle_demo.tscn")
	var scene: Node = packed.instantiate()
	add_child(scene)
	print("[screenshot_battle_runner] battle_demo loaded, will capture after 60 frames")

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 60:
		_capture()

func _capture() -> void:
	print("[screenshot_battle_runner] _capture called")

	# Ensure output directory exists
	print("[screenshot_battle_runner] checking dir: " + CAPTURE_DIR)
	print("[screenshot_battle_runner] dir exists? " + str(DirAccess.dir_exists_absolute(CAPTURE_DIR)))
	if not DirAccess.dir_exists_absolute(CAPTURE_DIR):
		var mk_err := DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
		print("[screenshot_battle_runner] make_dir result: " + str(mk_err))
		if mk_err != OK:
			push_error("[screenshot_battle_runner] make_dir failed: %d" % mk_err)
			get_tree().quit()
			return

	# Capture viewport
	print("[screenshot_battle_runner] capturing viewport...")
	var viewport := get_viewport()
	print("[screenshot_battle_runner] viewport: " + str(viewport))
	var tex := viewport.get_texture()
	print("[screenshot_battle_runner] texture: " + str(tex))
	var img: Image = tex.get_image()
	print("[screenshot_battle_runner] image size: " + str(img.get_size()) if img else "[screenshot_battle_runner] image null")
	if img == null:
		push_error("[screenshot_battle_runner] get_image() returned null")
		get_tree().quit()
		return

	# Save as battle.png so VLM review can pick it up directly
	var filename := "battle.png"
	var path := "%s/%s" % [CAPTURE_DIR, filename]
	print("[screenshot_battle_runner] saving to: " + path)
	var err: int = img.save_png(path)
	print("[screenshot_battle_runner] save_png err: " + str(err))
	if err == OK:
		var abs_path := ProjectSettings.globalize_path(path)
		print("[screenshot_battle_runner] saved %s (%dx%d) -> %s" % [filename, img.get_width(), img.get_height(), abs_path])
	else:
		push_error("[screenshot_battle_runner] save_png failed: %d" % err)

	get_tree().quit()
