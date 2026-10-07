# tools/vision helper — deferred QA-node mount for capture probes.
# Background: on a plain `godot --path . -- --qa-auto-run` launch, zero QA nodes
# mount, because GameState._ready calls DEBUG_RUNNER.ensure_qa_nodes() while the
# tree is still setting up children, so every root.add_child() fails
# ("Parent node is busy setting up children"). AgentSocket therefore never polls
# res://.agent_input.json and no capture PNG can be produced.
# This helper runs as the main loop (`-s res://tools/vision/godot_launch.gd`),
# loads the main scene, then mounts the QA nodes once the tree is idle, so the
# agent_socket capture protocol works unchanged.
extends SceneTree

const DEBUG_RUNNER := preload("res://scripts/qa/debug_runner.gd")

var _frames: int = 0
var _scene_requested: bool = false
var _nodes_mounted: bool = false

func _initialize() -> void:
	print("godot_launch helper: _initialize")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 2 and not _scene_requested:
		_scene_requested = true
		var main_scene: String = ProjectSettings.get_setting(
			"application/run/main_scene", "res://scenes/main.tscn")
		print("godot_launch helper: loading %s" % main_scene)
		change_scene_to_file(main_scene)
	if _frames >= 10 and not _nodes_mounted:
		_nodes_mounted = true
		var n: int = DEBUG_RUNNER.ensure_qa_nodes(self)
		print("godot_launch helper: mounted %d QA nodes" % n)
	return false
