# implements: agent-infrastructure (debug script — 非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends SceneTree

func _initialize() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs:
		print("GameState found!")
		var props = gs.get_property_list()
		print("Property count: ", props.size())
		for prop in props:
			print("  prop: ", prop.name, " usage=", prop.usage, " type=", prop.type, " has_script_var=", bool(prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE))
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var val = gs.get(prop.name)
				print("    -> val=", val, " type=", typeof(val), " is_null=", val == null, " is_object=", val is Object)
				if val != null and not (val is Object and not (val is Array) and not (val is Dictionary)):
					print("    -> WOULD BE SERIALIZED")
	quit()