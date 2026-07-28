# implements: agent-infrastructure (非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends Node
# AgentInspector — game → agent state pipe
# 每 POLL_INTERVAL 秒把游戏状态写到 res://.agent_state.json
# agent 读这个文件就知道游戏里发生了什么（比 VLM 可靠 100 倍 — 像素易错，结构化数据不易错）
# 数据源：GameState autoload + 当前 scene + viewport size + engine info

const STATE_FILE := "res://.agent_state.json"
# 2026-07-28 节流：原 0.5s + or 帧门控 → headless 模式时间门控先触发，节流无效
# 改为 1.0s（每 1s dump 一次）+ 帧门控只作为 headless 限 FPS 时的兜底（一般触发不到）
const POLL_INTERVAL := 1.0  # 1s
# 与 qa_capture.gd / scene_walker.gd / agent_socket.gd 同款，4 处保持同步
const AGENT_FLAG := "--qa-auto-run"
const THROTTLE_FRAMES := 60  # 帧门控兜底（正常情况时间门控先触发）

var _timer: float = 0.0
var _frame_count: int = 0

func _ready() -> void:
	if AGENT_FLAG not in OS.get_cmdline_user_args():
		return  # 手动启动游戏时不写 agent state
	print("AgentInspector: writing to %s every %.1fs (frame throttle as fallback)" % [STATE_FILE, POLL_INTERVAL])
	_write_state()  # 立即写一次

func _process(delta: float) -> void:
	_frame_count += 1
	_timer += delta
	# 时间门控（1.0s）为主，帧门控（60帧）作为 headless 限 FPS 时的兜底
	# 之前用 `or` 导致 0.5s 时间门控永远先触发 → 节流形同虚设 → 5min 34808 行
	if _timer >= POLL_INTERVAL or _frame_count >= THROTTLE_FRAMES:
		_timer = 0.0
		_frame_count = 0
		_write_state()

func _write_state() -> void:
	var state: Dictionary = {
		"timestamp": Time.get_unix_time_from_system(),
		"datetime": Time.get_datetime_string_from_system(),
		"scene": _get_scene_name(),
		"viewport": {
			"width": int(get_viewport().get_visible_rect().size.x),
			"height": int(get_viewport().get_visible_rect().size.y)
		},
		"engine": {
			"fps": Engine.get_frames_per_second(),
			"frame": Engine.get_process_frames()
		}
	}
	# 从 GameState autoload 拿（如果存在）
	var gs := get_node_or_null("/root/GameState")
	if gs:
		state["game_state_keys"] = []
		var props = gs.get_property_list()
		print("AgentInspector: GameState property count = ", props.size())
		for prop in props:
			print("  prop: ", prop.name, " usage=", prop.usage, " type=", prop.type, " has_script_var=", bool(prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE))
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var prop_name: String = prop.name
				var val = gs.get(prop_name)
				print("    -> val=", val, " type=", typeof(val), " is_null=", val == null, " is_object=", val is Object)
				if val != null and not (val is Object and not (val is Array) and not (val is Dictionary)):
					state["game_state_keys"].append(prop_name)
					state[prop_name] = val
	# 当前 scene 节点树摘要
	var current := get_tree().current_scene
	if current:
		state["current_scene_class"] = current.get_class()
		state["current_scene_name"] = current.name
		state["current_scene_groups"] = current.get_groups()
		# 如果在战斗场景，额外读取 BattleManager/Player 状态
		if current.name in ["BattleScene", "BattleDemo"]:
			_write_battle_state(state, current)
	# 写文件
	var json: String = JSON.stringify(state, "  ")
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	else:
		push_error("AgentInspector: failed to open %s for writing" % STATE_FILE)

func _write_battle_state(state: Dictionary, current_scene: Node) -> void:
	var bm = current_scene.get_node_or_null("BattleManager")
	if bm == null:
		return
	# Player 状态
	var player = bm.get("player")
	if player:
		state["hp"] = player.current_hp
		state["max_hp"] = player.max_hp
		state["spirit_stones"] = player.current_energy  # battle uses current_energy
		state["max_energy"] = player.max_energy
		# 手牌数量：优先读 BattleUI.hand_count（single source of truth，避免 race）
		# 修复数据漂移 bug 2026-07-15: state JSON hand=1 vs 截图 3 张
		var ui = current_scene.get_node_or_null("BattleUI")
		if ui and "hand_count" in ui:
			state["hand_count"] = int(ui.hand_count)
		else:
			state["hand_count"] = player.hand.size()
		state["deck_size"] = player.get_draw_pile_count()
		state["discard_pile_size"] = player.get_discard_pile_count()
		state["mo_nian"] = player.mo_nian
		state["erosion"] = player.erosion
		state["turn"] = bm.turn_number
	# 敌人状态
	var enemies = bm.get("enemies")
	if enemies and enemies.size() > 0:
		var enemy = enemies[0]
		if enemy and enemy.is_alive:
			state["enemy"] = {
				"name": enemy.actor_name,
				"hp": enemy.current_hp,
				"max_hp": enemy.max_hp,
				"intent": enemy.get_intent_description() if enemy.has_method("get_intent_description") else "unknown",
				"intent_detail": enemy.get_intent_detail() if enemy.has_method("get_intent_detail") else "",
			}
			if enemies.size() > 1:
				var extra: Array = []
				for i in range(1, enemies.size()):
					var e = enemies[i]
					if e and e.is_alive:
						extra.append({
							"name": e.actor_name,
							"hp": e.current_hp,
							"max_hp": e.max_hp,
							"intent": e.get_intent_description() if e.has_method("get_intent_description") else "unknown",
						})
				if not extra.is_empty():
					state["enemy"]["extra_enemies"] = extra
	# 相生链
	var chain = bm.get("generation_chain")
	if chain and chain.size() > 0:
		state["generation_chain"] = []
		for elem in chain:
			state["generation_chain"].append(int(elem))
	# 2026-07-16 fix: 原 bm.has("_chain_trigger_count") 错用 .has() on Node → SCRIPT ERROR
	# Node 无 .has() 方法。改成 has_method() 检查 + get() 取值
	if bm.has_method("get") and "_chain_trigger_count" in bm:
		state["chain_trigger_count"] = int(bm.get("_chain_trigger_count"))
	else:
		state["chain_trigger_count"] = 0
	state["battle_state"] = bm.get_state_name()

func _get_scene_name() -> String:
	var current := get_tree().current_scene
	if current == null:
		return ""
	if current.scene_file_path and current.scene_file_path != "":
		return current.scene_file_path
	return current.name