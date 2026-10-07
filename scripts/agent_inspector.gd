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
# 2026-08-10 fix (card 64d87a07): 场景切换计数器 + 上一场景名 — 让 AI Player / debug 工具能判断是否发生 state drift
# 场景切换计数从 0 开始，每次 _on_tree_changed 检测到 scene 变化时 +1，previous_scene 记录切换前的 scene。
var _scene_change_count: int = 0
var _previous_scene_path: String = ""
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
	# 2026-08-03 00:10 fix: headless 模式下 Timer node 依赖 Node._process 调度（也会被 headless 减慢）。
	# 用 get_tree().create_timer() — SceneTreeTimer 直接由 SceneTree 调度，不需 _process 也能跑。
	_schedule_state_write()

func _schedule_state_write() -> void:
	_write_state()
	var timer: SceneTreeTimer = get_tree().create_timer(1.0)
	await timer.timeout
	if is_instance_valid(self) and is_inside_tree():
		_schedule_state_write()

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
		# 2026-08-10 fix (card 64d87a07): 记录上一场景 + 场景切换计数
		if _last_scene_path != "":
			_previous_scene_path = _last_scene_path
			_scene_change_count += 1
			print("AgentInspector: scene change #%d: %s → %s" % [_scene_change_count, _previous_scene_path, current_path])
		else:
			print("AgentInspector: initial scene: %s" % current_path)
		_last_scene_path = current_path
		print("AgentInspector: scene change detected → ", current_path, " → immediate flush (after 2 frames)")
		_write_state()
		# 2026-08-08 fix: map scene 的 _realm_map 在 _ready() 里通过 _generate_map() 同步设，
		# 但 _on_tree_changed 2 帧后调 _write_state 时偶尔 _realm_map 还是 null（race）。
		# 影响：LLM 看不到 reachable_nodes，0 visited，game 不推进。
		# 修复：如果是 map scene 且 _realm_map 还是 null，等 0.5s 再 retry 一次。
		if "map.tscn" in current_path:
			var current_node := tree.current_scene
			if current_node and current_node.get("_realm_map") == null:
				print("AgentInspector: map scene _realm_map still null after 2 frames, retry in 0.5s")
				await get_tree().create_timer(0.5).timeout
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
	# 2026-08-10 fix (card 64d87a07): 场景切换历史（让 AI Player / debug 工具能判断 state drift）
	state["previous_scene"] = _previous_scene_path
	state["scene_change_count"] = _scene_change_count
	# 从 GameState autoload 拿（如果存在）
	var gs := get_node_or_null("/root/GameState")
	if gs:
		state["game_state_keys"] = []
		var props: Array = gs.get_property_list()
		# 2026-07-29 fix: verbose print 风暴 — 每秒 40+ 行 property list 会让 stdout buffer 满
		# → Godot 进程死掉 → AI Player session 启动后立即退出
		# 改成：只在 _ready 写一次 property 列表，运行时只写 state 不写 detail
		if _verbose_printed == false:
			print("AgentInspector: GameState property count = ", props.size())
			for prop in props:
				print("  prop: ", prop.name, " usage=", prop.usage, " type=", prop.type, " has_script_var=", bool(prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE))
				if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var prop_name: String = prop.name
					var val: Variant = gs.get(prop_name)
					print("    -> val=", val, " type=", typeof(val), " is_null=", val == null, " is_object=", val is Object)
			_verbose_printed = true
		for prop in props:
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var prop_name: String = prop.name
				var val: Variant = gs.get(prop_name)
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
		if current.name in ["Battle", "BattleScene", "BattleDemo"]:
			_write_battle_state(state, current)
		elif current.name == "GameMap" or (current.scene_file_path and "map.tscn" in current.scene_file_path):
			_write_map_state(state, current)
		elif current.name == "CharacterSelect" or (current.scene_file_path and "character_select" in current.scene_file_path):
			_write_character_select_state(state, current)
		elif current.name == "RewardScene" or (current.scene_file_path and "reward.tscn" in current.scene_file_path):
			_write_reward_state(state, current)
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
	var realm_map: Variant = current_scene.get("_realm_map")
	if realm_map == null:
		return
	var nodes: Variant = realm_map.get("nodes")
	if nodes == null or nodes.size() == 0:
		return
	# 2026-07-31 (D1 v2): 用 panel.position 代替 node.x/node.y
	# 原代码读 node.x/y 但这些字段是 0.0（_init 没设），实际位置在 _node_ui_map[id].position
	# 取 panel.position + 节点中心 (NODE_SIZE/2) 才是真正的 viewport 坐标
	var node_ui_map: Variant = current_scene.get("_node_ui_map")
	if node_ui_map == null:
		node_ui_map = {}
	const MAP_NODE_SIZE: float = 88.0
	# 2026-08-10 fix (card 6209bc47): 原 get_type_name() fallback 是 '未知' — LLM 看到误读为 '?'，不知道是 bug 还是实际未知节点类型。
	# 修复：直接读 MapNode.NODE_TYPE_NAMES const（MapNode extends RefCounted，const 可通过常量路径访问），
	# fallback 用本地图副本保证总是返回有效字符串，同时加 type_id 数字字段让 LLM 看到 raw int。
	const MAP_NODE_TYPE_NAMES := {
		0: "战斗",
		1: "精英",
		2: "事件",
		3: "商店",
		4: "休息",
		5: "Boss",
		6: "秘境",
	}
	var reachable: Array = []
	var all_nodes: Array = []
	for node in nodes:
		if node == null:
			continue
		# 计算实际 viewport 坐标（panel.position + NODE_SIZE/2）
		var actual_x: float = 0.0
		var actual_y: float = 0.0
		if node.id in node_ui_map:
			var panel: Variant = node_ui_map[node.id]
			if panel and "position" in panel:
				actual_x = panel.position.x + MAP_NODE_SIZE / 2.0
				actual_y = panel.position.y + MAP_NODE_SIZE / 2.0
		# 2026-08-10: 用 NODE_TYPE_NAMES 直接 fallback，避免 get_type_name() 返回 '未知' 导致 LLM 误读为 '?'
		var type_id: int = int(node.type) if "type" in node else -1
		var type_name: String = MAP_NODE_TYPE_NAMES.get(type_id, "未知(类型=%d)" % type_id)
		var entry: Dictionary = {
			"id": node.id if "id" in node else "",
			"type_id": type_id,
			"type_name": type_name,
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
	var selected: Variant = current_scene.get("_selected_node")
	if selected and "id" in selected:
		state["selected_node_id"] = selected.id
		state["selected_node_type"] = selected.get_type_name() if selected.has_method("get_type_name") else ""

## 2026-07-30 fix (D1): 写 character_select scene 状态
## 输出 available_characters 列表（id + name + element）
func _write_character_select_state(state: Dictionary, current_scene: Node) -> void:
	# CharacterSelect 场景的 available_characters 列表通常在场景节点上或 GameState
	# 尝试从 _characters 节点 / _char_data 列表取
	var chars_node: Node = current_scene.get_node_or_null("CharacterList")
	if chars_node:
		state["character_select_count"] = chars_node.get_child_count()
	# 当前选中（玩家高亮）
	var focused: Variant = current_scene.get("_focused_index")
	if focused != null:
		state["character_focused_index"] = int(focused)

## 2026-08-10 fix (card f5c7f29e): 写 reward scene 状态
## 原代码 reward.tscn 不写任何 state 字段，AI Player 看到 reward 场景完全黑屏，只能瞎猜该 pick_reward 还是 skip_reward。
## 修复：从 GameState.get_meta("last_reward") 读 BattleReward 实例（含 card_choices / spirit_stones / dao_xing）写到 state["reward"]，
## 含 card_choices 列表每张卡片的 name / cost / element / damage / block / heal / draw_cards，让 LLM 知道 3 张卡的差异决定 pick_reward index。
func _write_reward_state(state: Dictionary, current_scene: Node) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	# 2026-08-10 fix: 之前 gs.get("last_reward") 不会读 meta — get() 只读脚本属性，meta 必须用 get_meta()
	var reward: Variant = gs.get_meta("last_reward", null) if gs.has_meta("last_reward") else null
	if reward == null:
		state["reward"] = null
		return
	var card_choices: Array = reward.get("card_choices", []) if "card_choices" in reward else []
	var reward_dict: Dictionary = {
		"spirit_stones": int(reward.get("spirit_stones", 0)) if "spirit_stones" in reward else 0,
		"dao_xing": int(reward.get("dao_xing", 0)) if "dao_xing" in reward else 0,
		"is_elite": bool(reward.get("is_elite", false)) if "is_elite" in reward else false,
		"is_boss": bool(reward.get("is_boss", false)) if "is_boss" in reward else false,
		"card_choice_count": card_choices.size(),
		"card_choices": [],
	}
	for i in range(card_choices.size()):
		var c: Variant = card_choices[i]
		if c == null:
			continue
		var card_info: Dictionary = {
			"index": i,
			"id": c.id if "id" in c else "",
			"name": c.name if "name" in c else "",
			"cost": int(c.cost) if "cost" in c else 0,
			"element": int(c.element) if "element" in c else 0,
			"damage": int(c.damage) if "damage" in c else 0,
			"block": int(c.block) if "block" in c else 0,
			"heal": int(c.heal) if "heal" in c else 0,
			"draw_cards": int(c.draw_cards) if "draw_cards" in c else 0,
		}
		# element / rarity 转字符串便于 LLM 阅读
		if "element" in c:
			card_info["element_name"] = WuXing.get_element_name(c.element) if typeof(c.element) == TYPE_INT and WuXing.has_method("get_element_name") else ""
		if "rarity" in c:
			card_info["rarity_name"] = c.get_rarity_name() if c.has_method("get_rarity_name") else ""
		reward_dict["card_choices"].append(card_info)
	state["reward"] = reward_dict

func _write_battle_state(state: Dictionary, current_scene: Node) -> void:
	var bm: Node = current_scene.get_node_or_null("BattleManager")
	if bm == null:
		return
	# Player 状态
	var player: Variant = bm.get("player")
	if player:
		state["hp"] = player.current_hp
		state["max_hp"] = player.max_hp
		state["spirit_stones"] = player.current_energy  # battle uses current_energy
		state["max_energy"] = player.max_energy
		state["block"] = player.current_block if "current_block" in player else 0
		# 手牌数量：优先读 BattleUI.hand_count（single source of truth，避免 race）
		# 修复数据漂移 bug 2026-07-15: state JSON hand=1 vs 截图 3 张
		var ui: Node = current_scene.get_node_or_null("BattleUI")
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
		# 2026-08-10 fix (card 0241de69): 原代码 if player.hand.size() > 0 才写 hand_cards key，
		# 手牌 0 张时 key 缺失，LLM 无法区分「真的 0 张」vs「state 漂移 race」。
		# 修复：始终写 state["hand_cards"]（空时为 []），加 hand_size_capacity / hand_max_draw_count 让 LLM 知道手牌上限。
		var hand_cards: Array = []
		if player.hand:
			for i in range(player.hand.size()):
				var c: Variant = player.hand[i]
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
		# 2026-08-10: 手牌上限（Player.hand_size 默认 4，可能因心魔低语临时降至 3）
		if "hand_size" in player:
			state["hand_size_capacity"] = int(player.hand_size)
		# 玩家当前能量也写到顶层（之前只写到 spirit_stones / max_energy），便于 LLM 一眼看到灵力
		state["player_current_energy"] = int(player.current_energy) if "current_energy" in player else 0
		# 当前玩家元素（battle 内 attack 卡的 element 跟玩家元素触发相生）
		if "element" in player:
			state["player_element"] = int(player.element)
	# 敌人状态
	# 2026-08-10 fix (card 90780893): 原代码只看 enemies[0].is_alive — 第 1 个敌人 HP=0 但 enemies[1] 还活着时
	# state.enemy 缺失（key 不写），AI Player 看到 stale state.enemy={} 或 missing key 反复 query 死敌。
	# 修复：遍历所有 enemies 找第一个 alive 的作为主 enemy，找不到时记录 alive_count=0 + dead_count 让 LLM 知道战况。
	var enemies: Variant = bm.get("enemies")
	if enemies and enemies.size() > 0:
		var primary_enemy: Variant = null
		var primary_idx: int = -1
		var alive_count: int = 0
		var dead_count: int = 0
		var all_enemies: Array = []
		for i in range(enemies.size()):
			var e: Variant = enemies[i]
			if e == null:
				continue
			var is_alive_e: bool = bool(e.is_alive) if "is_alive" in e else false
			if is_alive_e:
				alive_count += 1
				if primary_enemy == null:
					primary_enemy = e
					primary_idx = i
			else:
				dead_count += 1
			all_enemies.append({
				"index": i,
				"name": e.actor_name if "actor_name" in e else "",
				"hp": int(e.current_hp) if "current_hp" in e else 0,
				"max_hp": int(e.max_hp) if "max_hp" in e else 0,
				"is_alive": is_alive_e,
			})
		state["enemy_count"] = enemies.size()
		state["enemy_alive_count"] = alive_count
		state["enemy_dead_count"] = dead_count
		state["all_enemies"] = all_enemies
		if primary_enemy != null:
			state["enemy"] = {
				"index": primary_idx,
				"name": primary_enemy.actor_name,
				"hp": primary_enemy.current_hp,
				"max_hp": primary_enemy.max_hp,
				"intent": primary_enemy.get_intent_description() if primary_enemy.has_method("get_intent_description") else "unknown",
				"intent_detail": primary_enemy.get_intent_detail() if primary_enemy.has_method("get_intent_detail") else "",
			}
			# 剩余 alive 敌人（除 primary）写入 extra_enemies，让 LLM 知道有多个目标要选
			var extra: Array = []
			for i in range(enemies.size()):
				if i == primary_idx:
					continue
				var e: Variant = enemies[i]
				if e and (bool(e.is_alive) if "is_alive" in e else false):
					extra.append({
						"index": i,
						"name": e.actor_name,
						"hp": e.current_hp,
						"max_hp": e.max_hp,
						"intent": e.get_intent_description() if e.has_method("get_intent_description") else "unknown",
					})
			if not extra.is_empty():
				state["enemy"]["extra_enemies"] = extra
	# 相生链
	var chain: Variant = bm.get("generation_chain")
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
