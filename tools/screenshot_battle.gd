## 战斗场景截图工具（VLM QA 输入）
# usage: godot --headless --path C:\Users\hbgan\Projects\shendu --script res://tools/screenshot_battle.gd --quit

extends SceneTree

const SCREENSHOT_DIR := "res://screenshots/"

func _init() -> void:
	print("[screenshot_battle] initializing GameState...")

	# Initialize minimal GameState so battle_demo can run
	GameState.reset_to_defaults()
	GameState.character_id = "chenmo"
	GameState.max_hp = 80
	GameState.hp = 80
	GameState.current_realm = 0
	GameState.current_node_id = "start"
	GameState.visited_node_ids = []

	# Give player a starter deck (use MVP card IDs)
	var starter_deck: Array[String] = [
		"MC-ME-001", "MC-ME-002",
		"MC-WO-001", "MC-WO-002",
		"MC-WA-001", "MC-WA-002",
		"MC-FI-001", "MC-FI-002",
		"MC-EA-001", "MC-EA-002"
	]
	GameState.deck = starter_deck.duplicate()

	print("[screenshot_battle] loading battle_demo...")
	var packed: PackedScene = load("res://scenes/battle_demo.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)

	# Wait for rendering to stabilize
	await process_frame
	await process_frame
	await create_timer(1.0).timeout

	# Ensure screenshot directory exists
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("screenshots"):
		dir.make_dir("screenshots")

	# Capture viewport
	var viewport := get_root()
	var img: Image = viewport.get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := SCREENSHOT_DIR + "battle_%s.png" % timestamp
	var err: int = img.save_png(path)
	if err == OK:
		print("[screenshot_battle] saved: " + path)
	else:
		print("[screenshot_battle] save failed, err=" + str(err))

	quit()
