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
# 2026-07-29 fix: scene change 时立即 flush state（不让 1s 节流 race condition 制造 state drift）
# 真因：1s 节流 + Godot 切 scene（sub-100ms）→ viewport_capture.png 是新 scene 但 state.json 残留旧 scene
# → AI Player client 写 vlm_request 时拿 stale state → minimax 返回 click_X_Y 但 client 按旧 scene apply → dead-lock
var _last_scene_path: String = ""
# 2026-07-29 fix: verbose print 风暴 — 只在 _ready 写一次 property 列表，运行时只写 state
var _verbose_printed: bool = false

func _ready() -> void:
	if AGENT_FLAG not in OS.get_cmdline_user_args():
		return  # 手动启动游戏时不写 agent state
	print("AgentInspector: writing to %s every %.1fs (frame throttle as fallback)" % [STATE_FILE, POLL_INTERVAL])
	# Hook scene change 立即 flush（解决 1s 节流 race condition）
	if get_tree():
		get_tree().connect("tree_changed", Callable(self, "_on_tree_changed"))
	_write_state()  # 立即写一次

func _on_tree_changed() -> void:
	# tree_changed 触发条件：任何节点 add/remove/rename + current_scene 切换
	# 但触发频繁，所以我们要 deduplicate by scene path
	# 关键：tree 还没初始化 / node freed 时 get_tree() 可能为 null → 三重 guard
	var tree := get_tree()
	if tree == null:
		return  # tree 还没初始化（启动早期或 tree shutdown）
	# 2026-07-29 fix: tree_changed 触发时 current_scene 可能是切换前的旧 scene
	# （change_scene_to_file 是 deferred async）→ 写 state.scene 是 stale
	# 10:26 LLM 看到 viewport_capture=character_select 但 state.scene=main.tscn → state drift 仍在
	# fix: 等 2 帧让 scene 切换完成再 flush
	await get_tree().process_frame
	await get_tree().process_frame
	if tree.current_scene == null:
		return
	var current_path: String = _get_scene_name()
	if current_path != "" and current_path != _last_scene_path:
		_last_scene_path = current_path
		print("AgentInspector: scene change detected → ", current_path, " → immediate flush (after 2 frames)")
		_write_state()

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
		# 2026-07-29 fix: verbose print 风暴 — 每秒 40+ 行 property list 会让 stdout buffer 满
		# → Godot 进程死掉 → AI Player session 启动后立即退出
		# 改成：只在 _ready 写一次 property 列表，运行时只写 state 不写 detail
		if _verbose_printed == false:
			print("AgentInspector: GameState property count = ", props.size())
			for prop in props:
				print("  prop: ", prop.name, " usage=", prop.usage, " type=", prop.type, " has_script_var=", bool(prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE))
				if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var prop_name: String = prop.name
					var val = gs.get(prop_name)
					print("    -> val=", val, " type=", typeof(val), " is_null=", val == null, " is_object=", val is Object)
			_verbose_printed = true
		for prop in props:
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var prop_name: String = prop.name
				var val = gs.get(prop_name)
				if val != null and not (val is Object and not (val is Array) and not (val is Dictionary)):
					state["game_state_keys"].append(prop_name)
					state[prop_name] = val
	# 当前 scene 节点树摘要
	var current := get_tree().current_scene
	if current:
		state["current_scene_class"] = current.get_class()
		state["current_scene_name"] = current.name
		state["current_scene_groups"] = current.get_groups()
		# 2026-07-30 fix (D1): 不同 scene 写对应 state，让 headless LLM 能基于 state 决策
		# 之前只有 BattleScene/BattleDemo 有专属 state writer，map scene 啥也没写 → LLM 看黑截图瞎猜
		if current.name in ["BattleScene", "BattleDemo", "Battle"] or (current.scene_file_path and "battle.tscn" in current.scene_file_path):
			_write_battle_state(state, current)
		elif current.name == "GameMap" or (current.scene_file_path and "map.tscn" in current.scene_file_path):
			_write_map_state(state, current)
		elif current.name == "CharacterSelect" or (current.scene_file_path and "character_select" in current.scene_file_path):
			_write_character_select_state(state, current)
	# 写文件
	var json: String = JSON.stringify(state, "  ")
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	else:
		push_error("AgentInspector: failed to open %s for writing" % STATE_FILE)

## 2026-07-30 fix (D1): 写 map scene 状态
## 让 LLM 在 headless 模式下能基于 state.json 选节点（不再依赖 viewport_capture.png 黑截图）
## 输出：
##   reachable_nodes: [{id, type_name, x, y, column, layer, is_reachable, is_visited}]
##   current_node_id, visited_node_ids （从 GameState 来）
##   selected_node_id （如果玩家已点击未确认）
func _write_map_state(state: Dictionary, current_scene: Node) -> void:
	var realm_map = current_scene.get("_realm_map")
	if realm_map == null:
		return
	var nodes = realm_map.get("nodes")
	if nodes == null or nodes.size() == 0:
		return
	# 2026-07-31 (D1 v2): 用 panel.position 代替 node.x/node.y
	# 原代码读 node.x/y 但这些字段是 0.0（_init 没设），实际位置在 _node_ui_map[id].position
	# 取 panel.position + 节点中心 (NODE_SIZE/2) 才是真正的 viewport 坐标
	var node_ui_map = current_scene.get("_node_ui_map")
	if node_ui_map == null:
		node_ui_map = {}
	const MAP_NODE_SIZE = 88.0
	var reachable: Array = []
	var all_nodes: Array = []
	for node in nodes:
		if node == null:
			continue
		# 计算实际 viewport 坐标（panel.position + NODE_SIZE/2）
		var actual_x: float = 0.0
		var actual_y: float = 0.0
		if node.id in node_ui_map:
			var panel = node_ui_map[node.id]
			if panel and "position" in panel:
				actual_x = panel.position.x + MAP_NODE_SIZE / 2.0
				actual_y = panel.position.y + MAP_NODE_SIZE / 2.0
		var entry: Dictionary = {
			"id": node.id if "id" in node else "",
			"type_name": node.get_type_name() if node.has_method("get_type_name") else "未知",
			"x": actual_x,
			"y": actual_y,
			"column": int(node.column) if "column" in node else 0,
			"layer": int(node.layer) if "layer" in node else 0,
			"is_reachable": bool(node.is_reachable) if "is_reachable" in node else false,
			"is_visited": bool(node.is_visited) if "is_visited" in node else false,
		}
		all_nodes.append(entry)
		if entry["is_reachable"] and not entry["is_visited"]:
			reachable.append(entry)
	state["map_nodes"] = all_nodes
	state["reachable_nodes"] = reachable
	# 当前选中（如果玩家点了未确认）— 让 LLM 知道下一步是不是 confirm
	var selected = current_scene.get("_selected_node")
	if selected and "id" in selected:
		state["selected_node_id"] = selected.id
		state["selected_node_type"] = selected.get_type_name() if selected.has_method("get_type_name") else ""

## 2026-07-30 fix (D1): 写 character_select scene 状态
## 输出 available_characters 列表（id + name + element）
func _write_character_select_state(state: Dictionary, current_scene: Node) -> void:
	# CharacterSelect 场景的 available_characters 列表通常在场景节点上或 GameState
	# 尝试从 _characters 节点 / _char_data 列表取
	var chars_node = current_scene.get_node_or_null("CharacterList")
	if chars_node:
		state["character_select_count"] = chars_node.get_child_count()
	# 当前选中（玩家高亮）
	var focused = current_scene.get("_focused_index")
	if focused != null:
		state["character_focused_index"] = int(focused)

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
		state["block"] = player.current_block if "current_block" in player else 0
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
		# 2026-07-30 fix (D1): 手牌详情 — LLM 需要知道哪张能出
		# 之前只有 hand_count (数量)，没有 cards id/cost/damage/block → LLM 不知道出什么
		if player.hand and player.hand.size() > 0:
			var hand_cards: Array = []
			for i in range(player.hand.size()):
				var c = player.hand[i]
				if c == null:
					continue
				var card_info: Dictionary = {
					"index": i,
					"id": c.id if "id" in c else "",
					"name": c.name if "name" in c else "",
					"cost": int(c.cost) if "cost" in c else 0,
					"damage": int(c.damage) if "damage" in c else 0,
					"block": int(c.block) if "block" in c else 0,
					"playable": int(c.cost) <= int(player.current_energy) if "cost" in c and "current_energy" in player else false,
				}
				hand_cards.append(card_info)
			state["hand_cards"] = hand_cards
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