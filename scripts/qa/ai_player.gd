## AI Player - Loop Engineering 自动游戏操作 Agent v1
## 状态机驱动:遍历主菜单 → 选角 → 地图 → 战斗 → 奖励 → 循环
## 具备简单战斗策略、经验记录、卡点检测
## 只在 --qa-auto-run flag 存在时启用

# implements: design/01-player-experience.md
# implements_philosophy: rule_1_core_loop_first, rule_2_failure_must_have_meaning, rule_5_real_agency
# agent-infrastructure: loop-engineering

extends Node

enum State {
	IDLE,
	MAIN_MENU,
	CHARACTER_SELECT,
	MAP,
	BATTLE,
	REWARD,
	SHOP,
	EVENT,
	REST,
	SETTLEMENT,
	VICTORY,
}

const MODE_SCRIPT := "script"  # 默认：状态机 + 硬编码启发式（baseline / fallback）
const MODE_MODEL := "model"    # 外部 LLM agent 驱动决策（vlm_worker.mjs + minimax-portal/MiniMax-M3）

var _ai_player_mode: String = MODE_SCRIPT  # 2026-07-13 新增 model mode

# MapNode.NodeType 枚举（用于判断节点类型）
const _MapNodeScript = preload("res://scripts/core/map_node.gd")
const NodeType = _MapNodeScript.NodeType

var _state: State = State.IDLE
var _running: bool = false
var _start_time_ms: int = 0
var _max_runtime_ms: int = 7_200_000  # 2026-07-24 Robert: 不设时限；保留 2h 仅作「真挂死」安全网
# P1.1 Phase 2 (H6, 2026-07-05 20:40): Goal 实时进度感知
var _last_goal_progress_print_ms: int = 0
const GOAL_PROGRESS_PRINT_INTERVAL_MS: int = 5000  # 每 5 秒 print 一次进度

# 当前场景根节点缓存
var _current_scene: Node = null
var _run_id: String = ""
var _turns_in_battle: int = -1  # -1 表示还没进入战斗
var _battle_start_hp: int = 0
var _cards_played_this_battle: int = 0
var _total_damage_dealt: int = 0
var _stuck_counter: int = 0
var _last_state: State = State.IDLE
var _last_state_time_ms: int = 0
var _loop_count: int = 0
# 2026-08-01 fix(ed75d23a): 跟踪 character_select 卡住次数，超过阈值强制跳过
var _char_select_stuck_count: int = 0
# P1.1 Phase 2.1 (2026-07-24 fix e175bfa1): 防止同 state-session 重复 fire stuck
# 避免 3 分钟 stuck 触发 3 次 record_stuck → 上游生成 3 张重复 bug card
var _stuck_fired_this_session: bool = false
# 2026-07-26 fix: 允许周期性恢复重试（首次恢复失败时），只 fire 1 次 stuck event
var _stuck_recovery_retry_interval_ms: int = 10000  # 每 10 秒重试一次恢复
var _last_stuck_recovery_attempt_ms: int = 0

# ==================== 生命周期 ====================

func _ready() -> void:
	if not _is_qa_mode():
		return
	_running = true
	_start_time_ms = Time.get_ticks_msec()
	_run_id = _generate_run_id()
	ExperienceMemory.set_run_id(_run_id)
	RunGoals.set_run_id(_run_id)
	# 默认 goals(如果 RunGoals 还没设置)
	# P1.1 Phase 2 (2026-07-05 16:18): 改为按 deck 状态自动选 scene
	if RunGoals.get_goals().is_empty():
		var current_deck: Array = []
		if not GameState.deck.is_empty():
			for idx in GameState.deck:
				var card = GameState.get_collection_card(idx)
				if not card.is_empty():
					current_deck.append(card)
		var current_realm: int = GameState.current_realm if GameState.has_method("get_current_realm") else 1
		var scene_name: String = _select_goal_scene_for_deck(current_deck, current_realm)
		var loaded: int = _load_goals_from_scene(scene_name)
		if loaded == 0:
			# Fallback: P1.1 Phase 1 的硬编码（防止 load_goal_scene 失败）
			# 2026-07-24 Robert: 移除 max_runtime_seconds 时限 goal。
			# 只保留游戏 driven goals（survive/collect）+ LLM 主动 quit。
			RunGoals.add_goal("survive_n_battles", 3, "high")
			RunGoals.add_goal("collect_n_cards", 15, "normal")
	# 2026-07-13：检测 --ai-player-mode=model flag (2026-07-17 增强：支持空格分隔形式)
	_ai_player_mode = _parse_ai_player_mode()
	print("AIPlayer: 解析后的 mode = %s" % _ai_player_mode)
	if _ai_player_mode == MODE_MODEL:
		print("AIPlayer: model mode 启用（外部 LLM agent 驱动决策，run_id=%s）" % _run_id)
		print("AIPlayer: 命令行启动方式: ai_player_client.py --mode=request")
		print("AIPlayer: 本节点只做：stats tracking + 写 experience_memory + 监听 quit 信号")
		# 连接 Goal 完成信号仍需保留（reflect prompt 需要）
		if not RunGoals.goal_completed.is_connected(_on_ai_player_goal_completed):
			RunGoals.goal_completed.connect(_on_ai_player_goal_completed)
		# model 模式只跑 _observe_loop（只检测状态 + 报告 stats），不调 _run_loop（不决策）
		_observe_loop()
		return
	print("AIPlayer: script mode 启用（状态机 + 硬编码启发式，run_id=%s）" % _run_id)
	print("AIPlayer: Goals = %s" % _goals_describe())
	# P2.1 (2026-07-05): 连接 Goal 完成信号 - AI Player 在 Goal 完成时写策略评估
	if not RunGoals.goal_completed.is_connected(_on_ai_player_goal_completed):
		RunGoals.goal_completed.connect(_on_ai_player_goal_completed)
	# 等待一帧让当前场景稳定
	await get_tree().process_frame
	_detect_state()
	_run_loop()

func _is_qa_mode() -> bool:
	return OS.get_cmdline_user_args().has("--qa-auto-run")

# 2026-07-13 新增：解析 --ai-player-mode=<mode> 参数
# 2026-07-17 修复：支持两种形式（Godot 4.7 在 Windows 上对 `--key=value` 形式解析有 bug）
#   形式 1: --ai-player-mode=model  （= 直接连接）
#   形式 2: --ai-player-mode model  （空格分隔，POSIX 标准）
func _parse_ai_player_mode() -> String:
	var args: Array = OS.get_cmdline_user_args()
	print("AIPlayer[debug]: cmdline_user_args = %s" % str(args))
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		# 形式 1: --ai-player-mode=model
		if arg.begins_with("--ai-player-mode="):
			var mode := arg.substr("--ai-player-mode=".length())
			if mode == MODE_MODEL or mode == MODE_SCRIPT:
				return mode
			push_warning("AIPlayer: 未知 mode '%s'，fallback 到 script mode" % mode)
			return MODE_SCRIPT
		# 形式 2: --ai-player-mode model
		if arg == "--ai-player-mode" and i + 1 < args.size():
			var mode: String = args[i + 1]
			if mode == MODE_MODEL or mode == MODE_SCRIPT:
				return mode
			push_warning("AIPlayer: 未知 mode '%s'，fallback 到 script mode" % mode)
			return MODE_SCRIPT
		i += 1
	return MODE_SCRIPT

# model 模式的观察循环：只检测状态 + 报告 stats，不做决策，不主动 quit
# 2026-07-24 Robert: 不在 Godot 端设置退出时限。
# 退出路径仅 3 个：
#   ①is_all_completed（通关/任务完成 game-driven）
#   ②LLM 通过 AgentSocket 发 quit（LLM-driven）
#   ③Runner 检测 health=stopped 后 kill -9 Godot（LLM rate limit）
# _max_runtime_ms 保留为 7_200_000ms（2h）作为「真挂死」安全网，不应主动触发。
func _observe_loop() -> void:
	while _running:
		_loop_count += 1
		var elapsed: int = Time.get_ticks_msec() - _start_time_ms
		var elapsed_sec: int = int(float(elapsed) / 1000.0)
		RunGoals.report("elapsed_seconds", elapsed_sec)
		RunGoals.report("loop_count", _loop_count)
		# 游戏自己触发通关/完成时退出（goal-driven）
		if RunGoals.should_quit():
			print("AIPlayer[model]: should_quit 返回 true, 退出")
			print("AIPlayer[model]: 最终 stats: %s" % JSON.stringify(RunGoals.get_stats(), "  "))
			_save_deck_health_snapshot()
			var tree := _get_tree_safe()
			if tree != null:
				tree.quit()
			return
		# 「真挂死」安全网：2h 仍没动 → 记录 lifecycle 退出（不应常态触发）
		if elapsed > _max_runtime_ms:
			print("AIPlayer[model]: 异常：2h 未退出 → 强制退出（可能是 LLM/agent hang）")
			ExperienceMemory.record("lifecycle", _state_name(_state), "max_runtime_hang_protection", {"elapsed_ms": elapsed})
			_save_deck_health_snapshot()
			var tree := _get_tree_safe()
			if tree != null:
				tree.quit()
			return
		_detect_state()
		_check_goal_progress()
		await _wait_ms(500)

# ==================== 主循环 ====================

func _run_loop() -> void:
	while _running:
		_loop_count += 1
		var elapsed: int = Time.get_ticks_msec() - _start_time_ms
		var elapsed_sec: int = int(float(elapsed) / 1000.0)
		RunGoals.report("elapsed_seconds", elapsed_sec)
		RunGoals.report("loop_count", _loop_count)

		# 检查是否所有 goal 都完成（或 max_runtime_seconds 触发）
		if RunGoals.should_quit():
			print("AIPlayer: should_quit 返回 true, 退出")
			print("AIPlayer: 最终 stats: %s" % JSON.stringify(RunGoals.get_stats(), "  "))
			_save_deck_health_snapshot()
			var tree := _get_tree_safe()
			if tree != null:
				tree.quit()
			return

		# 软上限兜底（script mode 仍保留 2h 安全网，但 2026-07-24 不应常态触发）
		if elapsed > _max_runtime_ms:
			print("AIPlayer: 异常：2h 未退出 → 强制退出")
			ExperienceMemory.record("lifecycle", _state_name(_state), "max_runtime_hang_protection", {"elapsed_ms": elapsed})
			_save_deck_health_snapshot()
			var tree := _get_tree_safe()
			if tree != null:
				tree.quit()
			return

		_detect_state()
		_check_stuck()
		# P1.1 Phase 2 (H6, 2026-07-05 20:40): Goal 实时进度感知 (每 5s print 一次)
		_check_goal_progress()

		match _state:
			State.MAIN_MENU:
				await _handle_main_menu()
			State.CHARACTER_SELECT:
				await _handle_character_select()
			State.MAP:
				await _handle_map()
			State.BATTLE:
				await _handle_battle()
			State.REWARD:
				await _handle_reward()
			State.SHOP:
				await _handle_shop()
			State.EVENT:
				await _handle_event()
			State.REST:
				await _handle_rest()
			State.SETTLEMENT:
				await _handle_settlement()
			State.VICTORY:
				await _handle_victory()
				RunGoals.report("victory", true)
			State.IDLE:
				await _wait_ms(500)
		await _wait_ms(200)

# ==================== 状态检测 ====================

func _detect_state() -> void:
	_current_scene = get_tree().current_scene
	if _current_scene == null:
		_state = State.IDLE
		return

	var scene_name: String = _current_scene.name
	match scene_name:
		"MainMenu":
			_state = State.MAIN_MENU
		"CharacterSelect":
			_state = State.CHARACTER_SELECT
		"GameMapScene":
			_state = State.MAP
		"BattleScene":
			_state = State.BATTLE
		"BattleDemo":
			# 2026-07-27 fix: BattleDemo 等测试场景没有真实战斗流程
			# 在 _detect_state 就识别为 IDLE，避免主循环死循环调用 _handle_battle
			_state = State.IDLE
		"RewardScene":
			_state = State.REWARD
		"ShopScene":
			_state = State.SHOP
		"EventScene":
			_state = State.EVENT
		"RestScene":
			_state = State.REST
		"SettlementScene":
			_state = State.SETTLEMENT
		"VictoryScene":
			_state = State.VICTORY
		_:
			_state = State.IDLE

	# 连接战斗结束信号
	if _state == State.BATTLE and _current_scene.has_method("_start_battle"):
		var bm = _current_scene.battle_manager
		if bm != null and not bm.battle_ended.is_connected(_on_battle_ended):
			bm.battle_ended.connect(_on_battle_ended)

# ==================== 各场景处理 ====================

func _handle_main_menu() -> void:
	print("AIPlayer: 处理主菜单")
	if not is_instance_valid(_current_scene):
		await _wait_ms(500)
		return
	# 优先用 NewGameButton(保证新游戏状态,清理旧存档)
	if AgentActions.click_button_by_name("NewGameButton"):
		print("AIPlayer: 触发新游戏按钮")
		await _wait_ms(1500)
		return
	# Fallback 到 StartButton
	if AgentActions.click_button_by_name("StartButton"):
		print("AIPlayer: 触发开始/继续游戏按钮")
		await _wait_ms(1500)
		return
	# 最后 fallback:模拟点击
	var new_game_btn: Button = _find_button("NewGameButton", "新游戏")
	if new_game_btn and new_game_btn.visible and not new_game_btn.disabled:
		await AgentInput.click_control(new_game_btn)
		await _wait_ms(1500)
		return
	print("AIPlayer: 未找到主菜单按钮")
	await _wait_ms(1000)

func _handle_character_select() -> void:
	print("AIPlayer: 处理角色选择")
	if not is_instance_valid(_current_scene):
		await _wait_ms(500)
		return
	
	# 2026-08-01 fix(ed75d23a): 跟踪卡住次数，超过 5 次强制跳过
	_char_select_stuck_count += 1
	if _char_select_stuck_count > 5:
		print("AIPlayer: character_select 卡住 %d 次，强制跳过" % _char_select_stuck_count)
		# 直接设置默认角色并切换场景（绕过 character_select.gd 的所有逻辑）
		GameState.character_id = "chenmo"
		var data: Dictionary = GameState.get_character_data()
		GameState.hp = data.get("hp", 80)
		GameState.max_hp = data.get("hp", 80)
		var starter_cards: Array = GameState.get_starter_deck()
		for card in starter_cards:
			var idx: int = GameState.add_to_collection(card)
			GameState.add_to_deck(idx)
		get_tree().change_scene_to_file("res://scenes/map.tscn")
		_char_select_stuck_count = 0
		await _wait_ms(1500)
		return
	
	# 直接调用场景的确认方法(绕过点击)
	if AgentActions.call_method("_confirm_selection"):
		print("AIPlayer: 调用 _confirm_selection")
		_char_select_stuck_count = 0  # 成功调用，重置计数器
		await _wait_ms(1500)
		return
	# fallback:先选陈默卡再确认
	var card: Control = _find_control("ChenmoCard")
	if card:
		await AgentInput.click_control(card)
		await _wait_ms(300)
	if AgentActions.click_button_by_name("ConfirmButton"):
		_char_select_stuck_count = 0  # 成功调用，重置计数器
		await _wait_ms(1500)
		return
	print("AIPlayer: 角色选择未成功（第 %d 次尝试）" % _char_select_stuck_count)
	await _wait_ms(1000)

func _handle_map() -> void:
	print("AIPlayer: 处理地图")
	if not is_instance_valid(_current_scene):
		await _wait_ms(500)
		return
	# 策略:直接访问 GameMapScene 内部状态,选中一个 reachable 节点,触发确认
	var scene := _current_scene
	# 通过调用 _show_confirmation 选中第一个 reachable 节点
	if scene.has_method("_show_confirmation") and scene.get("_realm_map") != null:
		var realm_map = scene._realm_map
		var reachable_node = null
		for n in realm_map.nodes:
			if n.is_reachable and not GameState.visited_node_ids.has(n.id):
				reachable_node = n
				break
		if reachable_node != null:
			print("AIPlayer: 选中 reachable 节点 %s (type=%s)" % [reachable_node.id, reachable_node.get_type_name()])
			scene._show_confirmation(reachable_node)
			await _wait_ms(500)
			# 触发确认前往
			var node_type = reachable_node.type
			scene._on_confirm_go()
			await _wait_ms(1500)
			# 处理 REST/EVENT 节点弹窗：弹窗不换场景，需手动关闭以触发 _update_reachable()
			if node_type == NodeType.REST:
				await _handle_rest_popup(scene)
				return
			if node_type == NodeType.EVENT:
				await _handle_event_popup(scene)
				return
			# COMBAT/ELITE/BOSS/SHOP 会直接 change_scene，无需额外处理
			return
	print("AIPlayer: 未找到 reachable 节点")
	await _wait_ms(1000)

## 处理休息节点弹窗：点击第一个按钮（吐纳）关闭弹窗
func _handle_rest_popup(scene: Node) -> void:
	print("AIPlayer: 处理休息节点弹窗")
	var rest_popup = scene.get_node_or_null("_rest_popup")
	if rest_popup == null or not is_instance_valid(rest_popup):
		print("AIPlayer: 未找到 _rest_popup")
		return
	# 找到第一个按钮（吐纳）并点击
	for child in rest_popup.get_children():
		if child is VBoxContainer:
			for btn in child.get_children():
				if btn is Button and btn.visible and not btn.disabled:
					print("AIPlayer: 点击休息弹窗按钮: %s" % btn.text)
					btn.pressed.emit()
					await _wait_ms(1500)
					return
	await _wait_ms(500)

## 处理事件节点弹窗：点击第一个选择按钮关闭弹窗
func _handle_event_popup(scene: Node) -> void:
	print("AIPlayer: 处理事件节点弹窗")
	var event_popup = scene.get_node_or_null("_event_popup")
	if event_popup == null or not is_instance_valid(event_popup):
		print("AIPlayer: 未找到 _event_popup")
		return
	# 找到第一个选择按钮并点击
	for child in event_popup.get_children():
		if child is VBoxContainer:
			for btn in child.get_children():
				if btn is Button and btn.visible and not btn.disabled and btn.text != "离开":
					print("AIPlayer: 点击事件选择: %s" % btn.text)
					btn.pressed.emit()
					await _wait_ms(1500)
					return
	await _wait_ms(500)

func _handle_battle() -> void:
	if not is_instance_valid(_current_scene):
		await _wait_ms(500)
		return

	# 2026-07-27 fix: BattleDemo 等测试 scene 没有真实战斗流程，直接跳过处理
	# 避免 AI Player 在 BattleDemo 中卡死 (stuck 230s+)
	if _is_test_scene():
		print("AIPlayer: 检测到测试场景 %s，跳过战斗处理" % _current_scene.name)
		await _wait_ms(500)
		return

	var bm := _get_battle_manager()
	if bm == null:
		print("AIPlayer: 未找到 BattleManager,等待")
		await _wait_ms(500)
		return

	# 如果战斗已结束(胜负状态),等待场景跳转,不重置 _turns_in_battle
	if bm.current_state == bm.BattleStateEnum.BATTLE_WIN or bm.current_state == bm.BattleStateEnum.BATTLE_LOSE:
		print("AIPlayer: 战斗已结束 (state=%d),等待场景跳转" % bm.current_state)
		await _wait_ms(500)
		return

	# 初始化战斗统计
	if _turns_in_battle == -1:
		_battle_start_hp = _get_player_hp()
		_cards_played_this_battle = 0
		_total_damage_dealt = 0
		print("AIPlayer: 进入战斗,初始HP=%d" % _battle_start_hp)

	# 只有玩家选牌阶段才行动
	if bm.current_state != bm.BattleStateEnum.CARD_SELECTION:
		await _wait_ms(300)
		return

	var player := _get_player_from_battle_manager(bm)
	if player == null:
		print("AIPlayer: 未找到 Player")
		await _wait_ms(300)
		return

	# 尝试出牌,直到无法出牌
	var played_any: bool = await _play_best_cards(bm, player)
	print("AIPlayer: _play_best_cards 返回 %s,_cards_played_this_battle=%d" % [played_any, _cards_played_this_battle])

	# 结束回合：优先通过 BattleUI 找按钮（EndTurnButton 在 BattleUI 子场景中）
	var end_turn_clicked: bool = false
	var battle_ui: Node = _current_scene.get_node_or_null("BattleUI")
	if battle_ui != null and is_instance_valid(battle_ui):
		var end_turn_btn: Button = battle_ui.get_node_or_null("%EndTurnButton")
		if end_turn_btn != null and is_instance_valid(end_turn_btn):
			if AgentActions.click_button(end_turn_btn):
				print("AIPlayer: 触发结束回合(通过 BattleUI 按钮)")
				end_turn_clicked = true
				_turns_in_battle += 1
				await _wait_ms(1000)
				return
	# Fallback: 直接调用 battle_manager.player_end_turn()
	if bm.current_state == bm.BattleStateEnum.CARD_SELECTION:
		print("AIPlayer: 直接调用 player_end_turn()")
		bm.player_end_turn()
		_turns_in_battle += 1
		await _wait_ms(1000)
		return

	if not played_any:
		await _wait_ms(300)

## 战斗策略:按费用从低到高出牌,优先攻击牌
func _play_best_cards(bm: Node, player: Node) -> bool:
	var played_any: bool = false
	var max_iter: int = 10  # 防止无限循环

	for _i in range(max_iter):
		if bm.current_state != bm.BattleStateEnum.CARD_SELECTION:
			break

		# 获取可出牌索引(按费用升序,攻击牌优先)
		var playable: Array[Dictionary] = _get_playable_cards_sorted(bm, player)
		if playable.is_empty():
			break

		var chosen: Dictionary = playable[0]
		var card_index: int = chosen.index
		var card_data = chosen.card

		print("AIPlayer: 打出卡牌 #%d %s(费用 %d,伤害 %d)" % [
			card_index,
			_get_card_name(card_data),
			_get_card_cost(card_data),
			_get_card_damage(card_data)
		])

		# 记录当前手牌数,用于检测是否成功出牌
		var hand_size_before: int = player.hand.size()
		var energy_before: int = player.current_energy

		# 通过 CardUI 直接发出 card_clicked 信号(绕过鼠标点击)
		var card_ui: Control = _find_card_ui_by_index(card_index)
		if card_ui and card_ui.has_signal("card_clicked"):
			print("AIPlayer: 触发 CardUI.card_clicked #%d" % card_index)
			card_ui.card_clicked.emit()
			await _wait_ms(500)
		else:
			# Fallback:直接调用 battle_manager.player_play_card
			var played: bool = bm.player_play_card(card_index)
			print("AIPlayer: bm.player_play_card(%d) = %s" % [card_index, played])
			await _wait_ms(500)

		# 检测是否真的出了牌(手牌减少或能量减少)
		if player.hand.size() < hand_size_before or player.current_energy < energy_before:
			played_any = true
			_cards_played_this_battle += 1
			_total_damage_dealt += _get_card_damage(card_data)
			hand_size_before = player.hand.size()
			energy_before = player.current_energy
		else:
			print("AIPlayer: 出牌 #%d 未生效,停止" % card_index)
			break

	return played_any

## 获取可出牌并按优先级排序
func _get_playable_cards_sorted(_bm: Node, player: Node) -> Array[Dictionary]:  # _bm 备用
	var result: Array[Dictionary] = []
	var hand = player.hand
	for i in range(hand.size()):
		var card = hand[i]
		var cost: int = _get_card_cost(card)
		if cost <= player.current_energy:
			result.append({
				"index": i,
				"card": card,
				"cost": cost,
				"damage": _get_card_damage(card),
				"block": _get_card_block(card),
				"kind": _get_card_kind(card),
			})

	# 排序:低费用优先,同费用攻击牌优先,同类型伤害高的优先
	result.sort_custom(func(a, b):
		if a.cost != b.cost:
			return a.cost < b.cost
		if a.damage != b.damage:
			return a.damage > b.damage
		return a.block > b.block
	)
	return result

## 战斗结束回调(由 BattleManager 信号触发)
func _on_battle_ended(result: int) -> void:
	var won: bool = result == 0
	var player := _get_player_from_battle_manager(_get_battle_manager())
	var hp_percent: float = 0.0
	if player != null and player.max_hp > 0:
		hp_percent = float(player.current_hp) / float(player.max_hp)

	ExperienceMemory.record_battle_result(won, _turns_in_battle, hp_percent, {
		"cards_played": _cards_played_this_battle,
		"damage_dealt": _total_damage_dealt,
		"start_hp": _battle_start_hp,
		"end_hp": player.current_hp if player != null else 0,
	})
	if won:
		RunGoals.increment("battles_won")
	else:
		RunGoals.report("defeat", true)

	if won and _cards_played_this_battle > 0:
		ExperienceMemory.record_trick("battle", "低费攻击牌优先出牌策略有效", {
			"cards_played": _cards_played_this_battle,
			"damage_dealt": _total_damage_dealt,
		})

	_turns_in_battle = 0

func _get_battle_manager() -> Node:
	var scene = _current_scene
	if scene == null:
		return null
	if scene.has_method("_start_battle") and scene.get("battle_manager") != null:
		return scene.battle_manager
	return null

func _get_player_from_battle_manager(bm: Node) -> Node:
	if bm == null:
		return null
	if bm.get("player") != null:
		return bm.player
	return null

func _get_player_hp() -> int:
	var player = _get_player_from_battle_manager(_get_battle_manager())
	if player != null:
		return player.current_hp
	return 0

func _get_card_name(card) -> String:
	if card == null:
		return "?"
	# card 是 CardDataResource(Resource)
	if card.name != "":
		return card.name
	if card.get("card_name") != null:
		return card.card_name
	return "?"

func _get_card_cost(card) -> int:
	if card == null:
		return 99
	return int(card.cost)

func _get_card_damage(card) -> int:
	if card == null:
		return 0
	return int(card.damage)

func _get_card_block(card) -> int:
	if card == null:
		return 0
	return int(card.block)

func _get_card_kind(card) -> int:
	if card == null:
		return 0
	return int(card.card_kind)

func _find_card_ui_by_index(index: int) -> Control:
	if _current_scene == null:
		return null
	var battle_ui_node = _current_scene.get_node_or_null("BattleUI")
	if battle_ui_node == null:
		return null
	var hand_container = battle_ui_node.get_node_or_null("%HandContainer")
	if hand_container == null:
		return null
	var children = hand_container.get_children()
	if index >= 0 and index < children.size():
		return children[index] as Control
	return null

func _handle_reward() -> void:
	print("AIPlayer: 处理奖励")
	if not is_instance_valid(_current_scene):
		await _wait_ms(500)
		return
	# 等待翻牌动画完成(约 2.5 秒)
	await _wait_ms(2500)
	RunGoals.increment("cards_collected")
	# 优先直接触发跳过按钮(绕过点击)
	if AgentActions.click_button_by_name("SkipButton"):
		print("AIPlayer: 触发跳过奖励")
		await _wait_ms(2000)
		return
	# Fallback:模拟点击
	var skip: Button = _find_button("SkipButton", "跳过")
	if skip and is_instance_valid(skip) and skip.visible and not skip.disabled:
		await AgentInput.click_control(skip)
		await _wait_ms(2000)
	else:
		await AgentInput.click_at(Vector2(960, 600))
		await _wait_ms(2000)

func _handle_shop() -> void:
	print("AIPlayer: 处理商店")
	RunGoals.increment("shops_visited")
	if AgentActions.click_button_by_name("LeaveButton"):
		await _wait_ms(1500)
		return
	await _wait_ms(1000)

func _handle_event() -> void:
	print("AIPlayer: 处理事件")
	RunGoals.increment("events_visited")
	if not is_instance_valid(_current_scene):
		await _wait_ms(500)
		return
	# 事件 UI 的按钮是动态创建的,找名为"Button"的第一个按钮触发
	for child: Node in _current_scene.get_children():
		var btn := _find_first_button(child)
		if btn:
			AgentActions.click_button(btn)
			await _wait_ms(1500)
			return
	await AgentInput.click_at(Vector2(960, 700))
	await _wait_ms(1000)

func _handle_rest() -> void:
	print("AIPlayer: 处理休息")
	RunGoals.increment("rests_visited")
	if not is_instance_valid(_current_scene):
		await _wait_ms(500)
		return
	# 休息节点有吐纳/净化/跳过三个按钮,找第一个触发
	for child: Node in _current_scene.get_children():
		var btn := _find_first_button(child)
		if btn:
			AgentActions.click_button(btn)
			await _wait_ms(1500)
			return
	await AgentInput.click_at(Vector2(960, 600))
	await _wait_ms(1000)

func _find_first_button(node: Node) -> Button:
	if node is Button and node.visible and not node.disabled:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_first_button(child)
		if found:
			return found
	return null

func _handle_settlement() -> void:
	print("AIPlayer: 处理结算")
	if AgentActions.click_button_by_name("ReplayButton"):
		await _wait_ms(1500)
		return
	if AgentActions.click_button_by_name("QuitButton"):
		await _wait_ms(1500)
		return
	await _wait_ms(1000)

func _handle_victory() -> void:
	print("AIPlayer: 处理通关")
	if AgentActions.click_button_by_name("BackButton"):
		await _wait_ms(1500)
		return
	await _wait_ms(1000)

# ==================== 卡点检测 ====================

var _last_battle_turn: int = -1  # 记录上一次的战斗回合数

# 2026-07-26 fix(3274d1ec): BattleDemo 是 dev/test scene（scenes/battle_demo.tscn，
# 348 字节），没有真实的 turn 流转。AI Player 跑进 BattleDemo 后会永远卡 230s+
# （battle_turn 不推进 → per-turn reset 不触发）。视为非真实卡点：跳过 stuck 检测。
const TEST_SCENE_NAMES: PackedStringArray = ["BattleDemo"]

func _is_test_scene() -> bool:
	if _current_scene == null:
		return false
	return TEST_SCENE_NAMES.has(_current_scene.name)

func _check_stuck() -> void:
	# BattleDemo 等测试 scene：跳过 stuck 检测（避免撑大 stuck metric）
	if _is_test_scene():
		return
	# 战斗内按回合重置卡点计数器：每个新回合是新的上下文
	var battle_turn_changed: bool = false
	if _state == State.BATTLE:
		# 如果 _turns_in_battle 增加了，说明进入新回合，重置计数器
		if _last_battle_turn != _turns_in_battle:
			_stuck_counter = 0
			_last_state_time_ms = Time.get_ticks_msec()
			_last_battle_turn = _turns_in_battle
			battle_turn_changed = true
			# 新回合开启新的 stuck-session 配额
			_stuck_fired_this_session = false
	
	if not battle_turn_changed:
		if _state == _last_state:
			_stuck_counter += 1
		else:
			_stuck_counter = 0
			_last_state = _state
			_last_state_time_ms = Time.get_ticks_msec()
			# 状态切换开启新的 stuck-session 配额
			_stuck_fired_this_session = false

	# 状态特定的卡点阈值 (循环间隔约 200ms)
	var threshold: int
	match _state:
		State.BATTLE:
			# 战斗中单回合卡点阈值：~65s (325 次循环)
			# 正常出牌+结束回合约 10-30s，65s 允许充足缓冲
			threshold = 325
		State.MAP:
			# 地图节点选择偶尔需要思考，~20s (100 次循环)
			threshold = 100
		_:
			# 其他状态：~10s (50 次循环)
			threshold = 50

	if _stuck_counter > threshold and not _stuck_fired_this_session:
		var elapsed: int = Time.get_ticks_msec() - _last_state_time_ms
		ExperienceMemory.record_stuck(_state_name(_state), "在同一状态停留过久", {
			"state": _state_name(_state),
			"elapsed_ms": elapsed,
			"scene": str(_current_scene.name) if _current_scene else "null",
			"battle_turn": _turns_in_battle if _state == State.BATTLE else -1,
		})
		_stuck_counter = 0
		_stuck_fired_this_session = true
		# 分层恢复策略：BATTLE 优先 EndTurnButton（更可能解开卡点），其他状态 fallback 屏幕中央
		print("AIPlayer: 检测到卡点 (%s, %.1fs, turn=%d), 尝试分层恢复" % [_state_name(_state), elapsed / 1000.0, _turns_in_battle])
		_stuck_recovery()
	# 2026-07-26 fix: stuck event 已 fire，但恢复失败（回合没推进）时允许周期性重试恢复
	elif _stuck_fired_this_session and _stuck_counter > threshold:
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_stuck_recovery_attempt_ms >= _stuck_recovery_retry_interval_ms:
			print("AIPlayer: 周期性恢复重试 (%s, turn=%d)" % [_state_name(_state), _turns_in_battle])
			_last_stuck_recovery_attempt_ms = now_ms
			_stuck_recovery()

# ==================== Goal 进度感知 (P1.1 Phase 2 H6, 2026-07-05 20:40) ====================

## 实时检查 Goal 进度（在主循环每 iteration 调一次）
## 每 5 秒 print 一次 进度 (避免 log spam)
func _check_goal_progress() -> void:
	var goals: Array = RunGoals.get_goals()
	if goals.is_empty():
		return
	var stats: Dictionary = RunGoals.get_stats()
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_goal_progress_print_ms < GOAL_PROGRESS_PRINT_INTERVAL_MS:
		return
	_last_goal_progress_print_ms = now_ms

	var progress_lines: Array[String] = []
	for g in goals:
		if g.completed:
			continue
		var pct: float = compute_goal_pct(g, stats)
		progress_lines.append("%s=%.0f%%" % [g.description, pct * 100.0])
	if progress_lines.size() > 0:
		print("AIPlayer: Goal 进度 — %s" % " | ".join(progress_lines))

## 静态进度计算函数 (unit-testable，独立于 Node 生命周期)
## 返回 [0.0, 1.0] 区间值（>= 1.0 表示已达成）
static func compute_goal_pct(g: Goal, stats: Dictionary) -> float:
	if g.value <= 0:
		return 1.0 if g.check(stats) else 0.0
	match g.type:
		Goal.TYPE_SURVIVE_N_BATTLES:
			return min(1.0, float(stats.get("battles_won", 0)) / float(g.value))
		Goal.TYPE_MAX_RUNTIME_SECONDS:
			return min(1.0, float(stats.get("elapsed_seconds", 0)) / float(g.value))
		Goal.TYPE_COLLECT_N_CARDS:
			return min(1.0, float(stats.get("cards_collected", 0)) / float(g.value))
		Goal.TYPE_TRIGGER_N_CHAINS:
			return min(1.0, float(stats.get("chains_triggered", 0)) / float(g.value))
		Goal.TYPE_REACH_REALM_N:
			return min(1.0, float(stats.get("realm", 0)) / float(g.value))
		Goal.TYPE_VISIT_NODE_TYPES:
			var visited: Variant = stats.get("node_types_visited", [])
			var visited_size: int = visited.size() if visited is Array else 0
			return min(1.0, float(visited_size) / float(g.value))
		Goal.TYPE_LOOP_COUNT_N:
			return min(1.0, float(stats.get("loop_count", 0)) / float(g.value))
		_:
			return 0.0

func _state_name(s: State) -> String:
	match s:
		State.MAIN_MENU: return "main_menu"
		State.CHARACTER_SELECT: return "character_select"
		State.MAP: return "map"
		State.BATTLE: return "battle"
		State.REWARD: return "reward"
		State.SHOP: return "shop"
		State.EVENT: return "event"
		State.REST: return "rest"
		State.SETTLEMENT: return "settlement"
		State.VICTORY: return "victory"
		_: return "idle"

func _generate_run_id() -> String:
	return Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")

func _goals_describe() -> String:
	var parts: Array = []
	for goal in RunGoals.get_goals():
		parts.append(goal.description)
	return ", ".join(parts)

## P2.1 (2026-07-05): AI Player 在 Goal 完成时的反应
## 不同于 _default_goal_callback (RunGoals 内置, 写 type="goal")
## 本函数按 goal.type 路由不同 type 的策略评估:
##   - "tactic" (战斗) | "progress" (卡组) | "strategy" (max_runtime/complete_run)
##   - "loss" (first_loss) | "goal_strategy" (fallback)
## 设计哲学: 让 ExperienceMemory 区分[这局怎么赢/输的],下次启动能调优。
func _on_ai_player_goal_completed(goal: Goal, stats: Dictionary) -> void:
	if _run_id.is_empty():
		_run_id = "ai_player_unknown"
	var elapsed: int = Time.get_ticks_msec() - _start_time_ms
	var elapsed_sec: int = int(float(elapsed) / 1000.0)
	match goal.type:
		Goal.TYPE_SURVIVE_N_BATTLES:
			var efficiency: float = float(goal.value) / max(1.0, float(elapsed_sec))
			ExperienceMemory.record(
				"trick", "ai_player",
				"完成 %d 场战斗(elapsed=%ds, 效率 %.2f 场/秒)" % [goal.value, elapsed_sec, efficiency],
				{"goal_type": goal.type, "goal_value": goal.value, "elapsed_sec": elapsed_sec,
					"battles_won": int(stats.get("battles_won", 0))},
				0.7
			)
		Goal.TYPE_MAX_RUNTIME_SECONDS:
			ExperienceMemory.record(
				"strategy_profile", "ai_player",
				"达到运行上限 %ds（实际 elapsed=%ds）" % [goal.value, elapsed_sec],
				{"goal_type": goal.type, "goal_value": goal.value,
					"actual_elapsed": elapsed_sec, "elapsed_sec": elapsed_sec},
				0.6
			)
		Goal.TYPE_COLLECT_N_CARDS:
			ExperienceMemory.record(
				"progress", "ai_player",
				"卡组达到 %d 张(battles_won=%d)" % [goal.value, int(stats.get("battles_won", 0))],
				{"goal_type": goal.type, "goal_value": goal.value,
					"cards_collected": int(stats.get("cards_collected", 0)),
					"battles_won": int(stats.get("battles_won", 0)),
					"elapsed_sec": elapsed_sec},
				0.65
			)
		Goal.TYPE_COMPLETE_RUN:
			ExperienceMemory.record(
				"strategy_profile", "ai_player",
				"通关(elapsed=%ds)" % elapsed_sec,
				{"goal_type": goal.type, "victory": bool(stats.get("victory", false)),
					"defeat": bool(stats.get("defeat", false)), "elapsed_sec": elapsed_sec},
				0.75
			)
		Goal.TYPE_FIRST_LOSS:
			ExperienceMemory.record(
				"loss", "ai_player",
				"第一次失败(elapsed=%ds, battles_won=%d)" % [elapsed_sec, int(stats.get("battles_won", 0))],
				{"goal_type": goal.type, "elapsed_sec": elapsed_sec,
					"battles_won": int(stats.get("battles_won", 0))},
				0.7
			)
		_:
			ExperienceMemory.record(
				"goal", "ai_player",
				"%s 完成" % goal.description,
				{"goal_type": goal.type, "elapsed_sec": elapsed_sec,
					"stats_snapshot": stats.duplicate()},
				0.6
			)

# ==================== P1.1 Phase 2 — AI Player 自动选 Goal Scene (2026-07-05 16:18) ====================
## 决策因素: deck_size + element_distribution + realm
## 纯函数: deck + realm -> scene name (string)
## 不直接修改 AI Player 行为,只是 helper; 调用方负责载入场景
##
## 决策树 (按优先级):
##   1. deck < 5  → "deck_health_check" (优先填充 deck)
##   2. deck > 20 → "battle_full_clear" (挑战高难度)
##   3. 偏科 ≥ 60% → "chain_test" (探索更多元素)
##   4. realm ≥ 3 → "battle_deep" (高境界挑战)
##   5. realm == 2 → "battle_should_lose" (中期允许失败)
##   6. 其他 → "battle_baseline" (默认平衡)
func _select_goal_scene_for_deck(deck: Array, realm: int) -> String:
	if deck.size() < 5:
		return "deck_health_check"
	if deck.size() > 20:
		return "battle_full_clear"
	# 元素分布检测 (5 种元素: 木火土金水, enum 1-5)
	var element_counts := {}
	for card in deck:
		var elem := int(card.get("element", 0))
		if elem > 0:
			element_counts[elem] = int(element_counts.get(elem, 0)) + 1
	if not element_counts.is_empty():
		var max_count := 0
		for elem in element_counts:
			if int(element_counts[elem]) > max_count:
				max_count = int(element_counts[elem])
		# 偏科阈值 60% (例 6/10 张同一元素)
		if deck.size() > 0 and float(max_count) / float(deck.size()) >= 0.6:
			return "chain_test"
	# Realm 阶段
	if realm >= 3:
		return "battle_deep"
	if realm == 2:
		return "battle_should_lose"
	return "battle_baseline"

## P1.1 Phase 2 helper: 加载选中的 goal scene 到 RunGoals
## 返回加载的 goal 数量; 失败返回 0
## 不影响 _ready 现有行为 (只在显式调用时生效)
func _load_goals_from_scene(scene_name: String) -> int:
	var goals := RunGoals.load_goal_scene(scene_name)
	if goals.is_empty():
		return 0
	for goal in goals:
		RunGoals.add_goal(goal.type, goal.value, goal.priority)
	return goals.size()

func _save_deck_health_snapshot() -> void:
	if GameState.collection.is_empty():
		return
	var deck: Array = []
	for idx in GameState.deck:
		var card = GameState.get_collection_card(idx)
		if not card.is_empty():
			deck.append(card)
	var analysis := DeckAnalyzer.analyze(deck)
	ExperienceMemory.record("deck_health_final", "settlement", "最终牌组健康度 %d/100" % analysis.health_score, {
		"health_score": analysis.health_score,
		"avg_cost": analysis.avg_cost,
		"defense_ratio": analysis.defense_ratio,
		"attack_ratio": analysis.attack_ratio,
		"cost_dist": analysis.cost_distribution,
		"element_dist": analysis.element_distribution,
		"issues": analysis.issues,
	})

# ==================== 工具方法 ====================

func _find_button(unique_name: String, text_hint: String = "") -> Button:
	if not is_instance_valid(_current_scene):
		return null
	var node: Node = _current_scene.get_node_or_null("%" + unique_name)
	if node is Button and is_instance_valid(node):
		return node as Button
	# 备用:按文字搜索
	if text_hint != "":
		for btn: Node in _current_scene.get_tree().get_nodes_in_group("Button"):
			if btn is Button and is_instance_valid(btn) and (btn as Button).text.contains(text_hint):
				return btn as Button
	return null

func _find_control(unique_name: String) -> Control:
	var node: Node = _current_scene.get_node_or_null("%" + unique_name)
	if node is Control:
		return node as Control
	return null

func _get_tree_safe() -> SceneTree:
	if is_instance_valid(self) and get_tree() != null:
		return get_tree()
	return null

func _wait_ms(ms: int) -> void:
	var tree := _get_tree_safe()
	if tree == null:
		return
	await tree.create_timer(float(ms) / 1000.0).timeout

# ==================== 卡点恢复逻辑（2026-07-26 fix） ====================

func _stuck_recovery() -> void:
	if _state == State.BATTLE:
		# 先尝试 EndTurnButton（按 unique_name 精确点击，需在 BattleUI 子场景中查找）
		var end_turn_clicked: bool = false
		var battle_ui: Node = _current_scene.get_node_or_null("BattleUI")
		if battle_ui != null and is_instance_valid(battle_ui):
			var end_turn_btn: Button = battle_ui.get_node_or_null("%EndTurnButton")
			if end_turn_btn != null and is_instance_valid(end_turn_btn):
				if AgentActions.click_button(end_turn_btn):
					end_turn_clicked = true
		if not end_turn_clicked:
			# Fallback 2：直接调用 battle_manager.player_end_turn()（如果还在选牌阶段）
			var bm := _get_battle_manager()
			if bm != null and bm.current_state == bm.BattleStateEnum.CARD_SELECTION:
				print("AIPlayer: stuck 恢复 - 直接调用 bm.player_end_turn()")
				bm.player_end_turn()
				_turns_in_battle += 1
				end_turn_clicked = true
		if not end_turn_clicked:
			# Fallback 3：屏幕中央
			AgentInput.click_at(Vector2(960, 540))
	else:
		AgentInput.click_at(Vector2(960, 540))
