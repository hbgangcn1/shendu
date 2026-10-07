class_name QaPaths
extends RefCounted
# Run-id namespacing for Godot-side QA pipes.
# Default run ("default", i.e. no --run-id flag) degrades to the legacy fixed
# names so existing behavior is unchanged:
#   state   res://.agent_state.json
#   input   res://.agent_input.json
#   captures res://qa-captures/
# Namespaced runs append the id:
#   state   res://.agent_state.<run_id>.json
#   input   res://.agent_input.<run_id>.json
#   captures res://qa-captures/<run_id>/

const DEFAULT_RUN_ID := "default"
const RUN_ID_FLAG := "--run-id"


static func run_id() -> String:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var idx: int = 0
	while idx < user_args.size():
		var arg: String = user_args[idx]
		if arg == RUN_ID_FLAG and idx + 1 < user_args.size():
			var val: String = _sanitize(user_args[idx + 1])
			if val != "":
				return val
			return DEFAULT_RUN_ID
		if arg.begins_with(RUN_ID_FLAG + "="):
			var val2: String = _sanitize(arg.get_slice("=", 1))
			if val2 != "":
				return val2
			return DEFAULT_RUN_ID
		idx += 1
	return DEFAULT_RUN_ID


static func is_default() -> bool:
	return run_id() == DEFAULT_RUN_ID


static func state_file() -> String:
	if is_default():
		return "res://.agent_state.json"
	return "res://.agent_state.%s.json" % run_id()


static func input_file() -> String:
	if is_default():
		return "res://.agent_input.json"
	return "res://.agent_input.%s.json" % run_id()


static func capture_dir() -> String:
	if is_default():
		return "res://qa-captures/"
	return "res://qa-captures/%s/" % run_id()


static func frame_path(seq: int) -> String:
	return "%sframe_%d.png" % [capture_dir(), seq]


static func _sanitize(raw: String) -> String:
	var val: String = raw.strip_edges()
	if val == "" or val.begins_with("-"):
		return ""
	val = val.replace("/", "_").replace("\\", "_").replace("..", "_")
	return val
