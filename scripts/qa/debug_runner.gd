# implements: agent-infrastructure (debug script — 非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends SceneTree

func _initialize() -> void:
	print("DebugRunner _initialize called")
	var gs = get_root().get_node_or_null("GameState")
	if gs == null:
		print("GameState NOT found at /root/GameState")
		print("Root children:")
		for child in get_root().get_children():
			print("  %s (%s)" % [child.name, child.get_class()])
		quit()
		return

	print("GameState FOUND at /root/GameState")
	print("Class: %s" % gs.get_class())
	print("Script: %s" % gs.get_script().resource_path)

	# List all properties
	var props = gs.get_property_list()
	for prop in props:
		var name = prop.name
		var usage = prop.usage
		var type = prop.type
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			print("SCRIPT_VAR: %s (usage=%d, type=%d)" % [name, usage, type])
		else:
			print("OTHER: %s (usage=%d, type=%d)" % [name, usage, type])
	
	# Check specific properties
	for key in ["hp", "max_hp", "spirit_stones", "deck", "collection", "hand", "current_realm", "visited_node_ids", "player_name", "character_id", "dao_xing", "mo_nian", "current_node_id", "game_map", "is_boss_defeated", "deck_max_size", "deck_removal_count", "total_dao_xing"]:
		if gs.has(key):
			var val = gs.get(key)
			print("%s = %s (type=%s)" % [key, val, typeof(val)])
		else:
			print("%s NOT FOUND" % key)
	
	quit()