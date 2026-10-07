# implements: agent-infrastructure (debug script — 非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends SceneTree

func _initialize() -> void:
	var gs = root.get_node_or_null("GameState")
	var out = FileAccess.open("res://debug_out.txt", FileAccess.WRITE)
	if gs:
		out.store_line("GameState found!")
		var props = gs.get_property_list()
		out.store_line("Property count: " + str(props.size()))
		for prop in props:
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var val = gs.get(prop.name)
				out.store_line("  SCRIPT_VAR: " + prop.name + " = " + str(val) + " (type=" + str(typeof(val)) + ")")
		out.store_line("HAND property exists: " + str(gs.has_property("hand")))
		if gs.has_property("hand"):
			var hand_val = gs.get("hand")
			out.store_line("  hand = " + str(hand_val) + " type=" + str(typeof(hand_val)))
	else:
		out.store_line("GameState NOT found")
	out.close()
	quit()