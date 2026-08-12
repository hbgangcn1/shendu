# implements: agent-infrastructure (非游戏设计文档)
# implements_philosophy: rule_1_core_loop_first

extends Node
# AgentSocket — agent → game input pipe
# 监听 res://.agent_input.json 文件，agent 写入 JSON 命令后由本 autoload 读取并执行
# 命令格式:
#   {"action":"click","x":640,"y":360}
#   {"action":"key","key":"space"}            # key 名称或 keycode
#   {"action":"capture","path":"res://foo.png"}
#   {"action":"change_scene","path":"res://scenes/main_menu.tscn"}
# 设计：文件式 (非 socket)，简单可靠，方便调试（cat 一下就知道发了什么）

const INPUT_FILE := "res://.agent_input.json"
const POLL_INTERVAL := 0.1  # 100ms 轮询
# 与 qa_capture.gd / scene_walker.gd / agent_inspector.gd 同款，4 处保持同步
const AGENT_FLAG := "--qa-auto-run"

var _exec_count: int = 0
# 2026-07-22 修复 AI Player stuck 100s bug：
# 战斗结束时设 _input_paused = true，跳过 _execute。
# change_scene 和 quit 仍允许（避免 AI Player 卡死时无法救场）
var _input_paused: bool = false

## 暂停 / 恢复 agent input 处理（战斗结束 fade 期问避免 LLM click 触发死循环）
func set_input_paused(paused: bool) -> void:
	_input_paused = paused
	print("AgentSocket: input_paused = %s" % paused)

func _ready() -> void:
	if AGENT_FLAG not in OS.get_cmdline_user_args():
		return  # 手动启动游戏时不轮询 agent input
	print("AgentSocket: watching %s" % INPUT_FILE)
	# 启动时清空旧文件
	_clear_file()

func _process(_delta: float) -> void:
	if not FileAccess.file_exists(INPUT_FILE):
		return
	var f := FileAccess.open(INPUT_FILE, FileAccess.READ)
	if f == null:
		return
	var content := f.get_as_text()
	f.close()
	# 读取后立即清空（agent 写新文件即可再次触发）
	_clear_file()
	if content.strip_edges().is_empty():
		return
	var json = JSON.parse_string(content)
	if json == null or not (json is Dictionary):
		push_error("AgentSocket: invalid JSON: %s" % content)
		return
	_execute(json as Dictionary)

func _clear_file() -> void:
	if FileAccess.file_exists(INPUT_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INPUT_FILE))

func _execute(cmd: Dictionary) -> void:
	# 2026-07-22: input_paused 时跳过 click/key，但保留 change_scene / quit / capture
	# 2026-08-08: label-based actions (select_node / play_card / confirm_select / select_chenmo / select_suwan) 也允许
	if _input_paused:
		var action: String = cmd.get("action", "")
		# 2026-08-12 修复：reward scene actions 也在放行列表（pick_reward/skip_reward/take_card/take_relic/skip），
		# 不加的话 battle → reward 转换后 _input_paused=true（fade 中设的）会一值 hold 到下一场 battle
		# 才能 reset，AI Player 在 reward 场景永远卡住。这个 bug 隐藏了2个月。
		if action in ["change_scene", "quit", "capture", "select_node", "play_card",
				"confirm_select", "select_chenmo", "select_suwan",
				"pick_reward", "skip_reward", "take_card", "take_relic", "skip",
				"confirm_node", "end_turn"]:
			pass  # 允许
		else:
			print("AgentSocket: paused, skip action=%s" % action)
			return
	var action: String = cmd.get("action", "")
	match action:
		"click":
			_do_click(int(cmd.get("x", 0)), int(cmd.get("y", 0)))
		"key":
			_do_key(String(cmd.get("key", "")))
		"capture":
			_do_capture(String(cmd.get("path", "res://agent_capture.png")))
		"change_scene":
			_do_change_scene(String(cmd.get("path", "")))
		"quit":
			get_tree().quit()
		# 2026-08-08 fix: label-based actions for AI Player (LLM 选 label, agent_socket 反查 click 坐标)
		# 解决 click miss 根本问题：LLM 不再猜坐标，选 node_id / card index，agent_socket 拿 state.json 坐标
		"select_node":
			_do_select_node(String(cmd.get("node_id", "")))
		"play_card":
			_do_play_card(int(cmd.get("index", -1)))
		# 2026-08-08: end_turn bypass click，跟 play_card 同款 —— 直接调 BattleManager.player_end_turn()
		# client.py 原本走 self.agent.key("space")，但 battle 可能是按钮不是热键，space 不一定起作用
		"end_turn":
			_do_end_turn()
		# 2026-08-09 fix: confirm_node bypass click —— debug log 显示 LLM 在 select_node 之后
		# 调 confirm_node 但 _do_click 用 Input.parse_input_event() 不触发 ConfirmGo 按钮，
		# 导致确认面板永远不消失，LLM 陷入 wait 循环（实测 17+ 次连续 wait 都进不了 battle）
		# 修复：直接调 scene._on_confirm_go()，跟 select_node 同款 bypass
		"confirm_node":
			_do_confirm_node()
		"confirm_select":
			_do_confirm_select()
		"select_chenmo":
			_do_select_character(0)
		"select_suwan":
			_do_select_character(1)
		# 2026-08-08: 战斗胜利后奖励场景 pick reward（绕过 click，跟 select_node 同款）
		# 同时认 take_card_X / take_relic_Y / skip（reward.txt prompt 里的命名）以保持兼容
		"pick_reward":
			_do_pick_reward(int(cmd.get("index", -1)))
		"skip_reward":
			_do_skip_reward()
		"take_card":
			_do_pick_reward(int(cmd.get("index", -1)))
		"take_relic":
			_do_pick_reward(int(cmd.get("index", -1)))  # 简化：都走 pick_card handler（遗物也是 _on_card_pressed）
		"skip":
			_do_skip_reward()
		_:
			push_error("AgentSocket: unknown action: %s" % action)

## 2026-08-08: 读 agent_state.json 给 label-based action 用
## state.json 由 agent_inspector.gd 每秒写一次，含 reachable_nodes / hand_cards / selected_node_id 等
func _read_state_file() -> Dictionary:
	var state_path := "res://.agent_state.json"
	if not FileAccess.file_exists(state_path):
		return {}
	var f := FileAccess.open(state_path, FileAccess.READ)
	if f == null:
		return {}
	var content := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(content)
	if parsed == null or not (parsed is Dictionary):
		return {}
	return parsed

## 2026-08-08: label-based action handlers
func _do_select_node(node_id: String) -> void:
	if node_id.is_empty():
		push_warning("AgentSocket: select_node without node_id")
		return
	var state := _read_state_file()
	if state.is_empty():
		push_warning("AgentSocket: state.json missing/empty, can't select_node")
		return
	# 2026-08-08 fix: Input.parse_input_event() 不触发 Control._gui_input（即使加了 warp_mouse），
	# LLM click (534,290) 永远不路由到 PanelContainer 的 gui_input，_selected_node 永远不设。
	# 绕过 click，直接调 scene 的 _show_confirmation + _on_confirm_go。
	var scene := get_tree().current_scene
	if scene == null:
		push_warning("AgentSocket: no current scene for select_node")
		return
	# map scene 有 _realm_map
	var realm_map = scene.get("_realm_map")
	if realm_map == null:
		push_warning("AgentSocket: scene has no _realm_map, fall back to click")
		# fallback: click by coords
		for n in state.get("reachable_nodes", []):
			if typeof(n) == TYPE_DICTIONARY and n.get("id") == node_id:
				_do_click(int(n.get("x", 0)), int(n.get("y", 0)))
				_exec_count += 1
				return
		return
	# 直接找到 MapNode + 调 _show_confirmation
	for n in realm_map.nodes:
		if n == null:
			continue
		var nid: String = n.id if "id" in n else ""
		if nid == node_id:
			if not (bool(n.is_reachable) if "is_reachable" in n else false):
				push_warning("AgentSocket: node %s not reachable" % node_id)
				return
			print("AgentSocket: select_node %s → bypass click, call _show_confirmation" % node_id)
			scene.call("_show_confirmation", n)
			# 2026-08-08 进一步：直接调 _on_confirm_go 跳过确认面板（LLM 决策一次到位）
			scene.call("_on_confirm_go")
			_exec_count += 1
			return
	push_warning("AgentSocket: node_id %s not found in _realm_map.nodes" % node_id)

func _do_confirm_node() -> void:
	# 2026-08-09: bypass click, directly call scene._on_confirm_go() (map.gd:118)
	# 修 LLM 在 select_node 后卡 wait 循环的 bug —— 原来 confirm_node 走 _do_click (Input.parse_input_event)
	# 不触发 ConfirmGo.pressed 信号
	var scene := get_tree().current_scene
	# 2026-08-09 debug: 临时写文件，看 _do_confirm_node 到底有没有被调
	var dbg := FileAccess.open("user://ai_player_debug.log", FileAccess.READ_WRITE)
	if dbg != null:
		dbg.seek_end()
		var has_method := scene != null and scene.has_method("_on_confirm_go")
		dbg.store_line("[confirm_node] scene=%s has_method=%s" % [str(scene), str(has_method)])
		dbg.close()
	if scene == null:
		push_warning("AgentSocket: confirm_node no current scene")
		return
	if not scene.has_method("_on_confirm_go"):
		push_warning("AgentSocket: current scene has no _on_confirm_go method (not map scene?)")
		return
	print("AgentSocket: confirm_node → scene._on_confirm_go()")
	scene.call("_on_confirm_go")
	_exec_count += 1

func _do_play_card(index: int) -> void:
	# 2026-08-08: 跟 select_node 同款，绕过 click，直接调 BattleManager.player_play_card(index)
	# 根因：Input.parse_input_event() 在 BattleUI Card 控件上同样不触发 _gui_input，
	# LLM play_card 永远只 log 不真出牌 → AI Player 永远赢不了战斗 → gate_1 永远 FAIL
	var scene := get_tree().current_scene
	if scene == null:
		push_warning("AgentSocket: play_card no current scene")
		return
	# 2026-08-08: main_battle scene 用 get_node_or_null("BattleManager")，跟 agent_inspector.gd:148 一致
	var bm = scene.get_node_or_null("BattleManager")
	if bm == null:
		push_warning("AgentSocket: play_card scene has no BattleManager child")
		return
	if not bm.has_method("player_play_card"):
		push_warning("AgentSocket: BattleManager has no player_play_card method")
		return
	var result: bool = bm.call("player_play_card", index)
	print("AgentSocket: play_card index=%d → bm.player_play_card()=%s" % [index, str(result)])
	_exec_count += 1

func _do_end_turn() -> void:
	# 2026-08-08: 跟 play_card 同款，绕过 click，直接调 BattleManager.player_end_turn()
	# client.py 原本走 self.agent.key("space") —— battle 的结束回合可能是按钮（不是热键），
	# Input.parse_input_event 同样不触发按钮的 pressed 信号，直接调方法最可靠
	var scene := get_tree().current_scene
	if scene == null:
		push_warning("AgentSocket: end_turn no current scene")
		return
	var bm = scene.get_node_or_null("BattleManager")
	if bm == null or not bm.has_method("player_end_turn"):
		push_warning("AgentSocket: BattleManager has no player_end_turn method")
		return
	print("AgentSocket: end_turn → bm.player_end_turn()")
	bm.call("player_end_turn")
	_exec_count += 1

func _do_confirm_select() -> void:
	var current := get_tree().current_scene
	if current == null:
		push_warning("AgentSocket: confirm_select no current scene")
		return
	if current.has_method("_confirm_selection"):
		print("AgentSocket: confirm_select → calling _confirm_selection()")
		current.call("_confirm_selection")
		_exec_count += 1
	else:
		push_warning("AgentSocket: current scene has no _confirm_selection method")

func _do_select_character(index: int) -> void:
	var current := get_tree().current_scene
	if current == null:
		push_warning("AgentSocket: select_character no current scene")
		return
	# character_select.gd: cards = [chenmo_card, suwan_card], focused_index 0/1
	if "_focused_index" in current:
		current.set("_focused_index", index)
	if current.has_method("_update_focus"):
		current.call("_update_focus")
		print("AgentSocket: select_character index=%d → _focused_index=%d" % [index, index])
		_exec_count += 1
	else:
		push_warning("AgentSocket: current scene has no _update_focus method")

## 2026-08-08: reward scene actions（绕过 click，直接调 reward_scene 的 _on_card_pressed / _on_skip_pressed）
## AI Player win battle 后 reward.tscn 加载，3 张卡 + skip 按钮。Input.parse_input_event 不触发 Card Panel 的 _gui_input（跟 map node 同问题），
## 所以 bypass click，直接调 scene._on_card_pressed(index) 或 scene._on_skip_pressed()。reward_scene.gd:254 (_on_card_pressed)、:317 (_on_skip_pressed)。
func _do_pick_reward(index: int) -> void:
	var current := get_tree().current_scene
	if current == null:
		push_warning("AgentSocket: pick_reward no current scene")
		return
	if not current.has_method("_on_card_pressed"):
		push_warning("AgentSocket: current scene has no _on_card_pressed method (not reward scene?)")
		return
	if index < 0 or index > 2:
		push_warning("AgentSocket: pick_reward index=%d out of range [0,2]" % index)
		return
	print("AgentSocket: pick_reward index=%d → scene._on_card_pressed" % index)
	current.call("_on_card_pressed", index)
	_exec_count += 1

func _do_skip_reward() -> void:
	var current := get_tree().current_scene
	if current == null:
		push_warning("AgentSocket: skip_reward no current scene")
		return
	if not current.has_method("_on_skip_pressed"):
		push_warning("AgentSocket: current scene has no _on_skip_pressed method (not reward scene?)")
		return
	print("AgentSocket: skip_reward → scene._on_skip_pressed")
	current.call("_on_skip_pressed")
	_exec_count += 1

func _do_click(x: int, y: int) -> void:
	# 2026-08-08 fix: Input.parse_input_event 单独使用不触发 Control._gui_input（mouse_filter=STOP 的 Control 需要先 warp_mouse）
	# 不加 warp_mouse，Control 不知道鼠标在哪个元素上 → click 不会路由到 PanelContainer 的 gui_input
	# 根因：AI Player session 里 LLM click (534,290) 匹配 R0_L0_N0 的 panel.position，
	#      但 _selected_node 不更新，visited_node_ids 一直是空。
	Input.warp_mouse(Vector2(x, y))
	# 模拟鼠标左键按下+释放
	var ev_down := InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.position = Vector2(x, y)
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.position = Vector2(x, y)
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	_exec_count += 1
	print("AgentSocket[%d]: click (%d, %d)" % [_exec_count, x, y])

func _do_key(key_name: String) -> void:
	var keycode: int = OS.find_keycode_from_string(key_name) if key_name != "" else KEY_NONE
	if keycode == KEY_NONE:
		push_warning("AgentSocket: unknown key: %s" % key_name)
		return
	var ev_down := InputEventKey.new()
	ev_down.keycode = keycode
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	var ev_up := InputEventKey.new()
	ev_up.keycode = keycode
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	_exec_count += 1
	print("AgentSocket[%d]: key %s (code %d)" % [_exec_count, key_name, keycode])

func _do_capture(path: String) -> void:
	# 2026-07-28 headless 守护：headless 模式无 viewport texture
	if OS.has_feature("headless"):
		print("AgentSocket: headless mode → skip capture")
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("AgentSocket: get_image() returned null")
		return
	var err: int = img.save_png(path)
	if err == OK:
		_exec_count += 1
		print("AgentSocket[%d]: capture -> %s (%dx%d)" % [_exec_count, path, img.get_width(), img.get_height()])
	else:
		push_error("AgentSocket: save_png failed: %d" % err)

func _do_change_scene(scene_path: String) -> void:
	if scene_path.is_empty():
		push_error("AgentSocket: change_scene needs 'path'")
		return
	get_tree().change_scene_to_file.call_deferred(scene_path)
	_exec_count += 1
	print("AgentSocket[%d]: change_scene -> %s" % [_exec_count, scene_path])
