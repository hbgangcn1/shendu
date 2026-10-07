## 主战斗场景脚本
## 串联战斗管理器、玩家、敌人和 UI
## 从 GameState 读取数据，结束后跳转奖励/结算

# implements: design/07-combat-system-spec.md
# implements_philosophy: rule_1_core_loop_first, rule_3_three_layer_loops

extends Node2D

const BattleReward: GDScript = preload("res://scripts/core/reward_data.gd")

var _save_system: SaveSystem = null

# ==================== 节点引用 ====================

@onready var battle_ui: BattleUI = $BattleUI

# ==================== 战斗管理 ====================

var battle_manager: BattleManager = null
var player: Player = null
var is_boss_fight: bool = false
var _battle_ended_handled: bool = false

# ==================== 初始化 ====================

func _ready() -> void:
	print("========================================")
	print("  蜃都 — 战斗")
	print("========================================")

	# 初始化存档系统
	_save_system = SaveSystem.new()
	add_child(_save_system)

	# 2026-07-22：恢复 AgentSocket input（防上一战暂停遗留）
	_enable_battle_input()
	_start_battle()

# ==================== 战斗流程 ====================

func _start_battle() -> void:
	# 从 GameState 创建玩家
	var char_data: Dictionary = GameState.get_character_data()
	var char_name: String = char_data.get("name", "玩家")
	var current_hp: int = GameState.hp if GameState.hp > 0 else char_data.get("hp", 80)
	var max_hp: int = GameState.max_hp if GameState.max_hp > 0 else char_data.get("hp", 80)

	player = Player.new(char_name, current_hp, WuXing.Element.FIRE, 10)
	player.max_hp = max_hp
	# 2026-08-12 修复 (card 2e39a09e): _start_battle() 创建 Player 但从未调 init_deck()
	# 根因：Player._init() 只设 max_energy/current_energy，draw_pile 仍是空数组；
	# battle 中永远抽不到牌，hand_cards=[] 导致 AI Player 报 "牌组永远 0 张 / reward 反馈闭环失效"
	# 验证：Player.init_deck() 实现完整（player.gd L148）从 GameState.deck 加载，
	# GameState.deck 为空时 fallback 到 CardPool.get_mvp_pool()（9 张测试卡）
	player.init_deck()

	# 根据节点类型生成敌人
	var enemies: Array = _generate_enemies()

	# 应用境界缩放
	var realm_scale: float = GameState.get_realm_enemy_scale()
	if realm_scale != 1.0:
		for enemy: Enemy in enemies:
			var original_hp: int = enemy.max_hp
			var scaled_hp := int(original_hp * realm_scale)
			enemy.max_hp = scaled_hp
			enemy.current_hp = scaled_hp
			print("敌人缩放：%s HP %d → %d (×%.2f)" % [enemy.actor_name, original_hp, scaled_hp, realm_scale])

	# 创建战斗管理器
	battle_manager = BattleManager.new()
	# 2026-07-16 fix：显式设 BattleManager.name，让 AgentInspector.get_node_or_null("BattleManager") 能找到
	battle_manager.name = "BattleManager"
	add_child(battle_manager)

	# 连接信号
	_connect_signals()

	# 开始战斗
	battle_manager.start_battle(player, enemies)

	# 初始显示
	_update_ui()

	print("战斗：初始化完成，敌人数量=%d" % enemies.size())
	print(battle_manager.get_battle_summary())

	# 首战新手引导
	if not GameState.first_battle_done:
		battle_ui.start_tutorial()
		print("战斗：首战，启动新手引导")

func _generate_enemies() -> Array:
	var enemies: Array = []
	var node_id: String = GameState.current_node_id

	# 通过 GameState.game_map 的 RealmMap.boss_node 判断是否Boss战
	if GameState.game_map:
		var realm: RealmMap = GameState.game_map.get_current_realm()
		if realm and realm.boss_node and realm.boss_node.id == node_id:
			is_boss_fight = true

	if is_boss_fight:
		# Boss战
		enemies.append(_create_boss())
	else:
		# 普通/精英战斗
		var is_elite: bool = false
		if GameState.game_map:
			var realm: RealmMap = GameState.game_map.get_current_realm()
			if realm:
				var node: MapNode = realm.get_node_by_id(node_id)
				if node and node.type == MapNode.NodeType.ELITE:
					is_elite = true

		if is_elite:
			enemies.append(_create_elite())
		else:
			# 1-2个普通怪
			enemies.append(_create_normal_enemy())
			if randf() < 0.4:
				enemies.append(_create_normal_enemy())

	return enemies

func _create_normal_enemy() -> Enemy:
	var pool := [
		Enemy.create_circuit_sprite,
		Enemy.create_fire_spirit,
		Enemy.create_urban_golem,
		Enemy.create_neon_spider,
		Enemy.create_data_jellyfish,
	]
	var factory: Variant = pool[randi() % pool.size()]
	return factory.call()

func _create_elite() -> Enemy:
	var pool := [
		Enemy.create_elite_shifting_puppet,
		Enemy.create_elite_thorn_vine,
		Enemy.create_elite_phantom_fire,
	]
	var factory: Variant = pool[randi() % pool.size()]
	return factory.call()

func _create_boss() -> Enemy:
	var realm := GameState.current_realm
	match realm:
		0:
			return Enemy.create_boss_neon_spider_queen()
		1:
			return Enemy.create_boss_furnace_giant()
		_:
			return Enemy.create_boss_tower_guardian()

# ==================== 信号连接 ====================

func _connect_signals() -> void:
	battle_manager.state_changed.connect(_on_state_changed)
	battle_manager.turn_started.connect(_on_turn_started)
	battle_manager.turn_ended.connect(_on_turn_ended)
	battle_manager.battle_ended.connect(_on_battle_ended)
	battle_manager.generation_chain_triggered.connect(_on_generation_chain)
	battle_manager.battle_log.connect(func(msg): battle_ui.add_log(msg))

	player.hp_changed.connect(_on_player_hp_changed)
	player.energy_changed.connect(_on_player_energy_changed)
	player.hand_changed.connect(_on_hand_changed)

	battle_ui.card_selected.connect(_on_card_selected)
	battle_ui.enemy_selected.connect(_on_enemy_selected)
	battle_ui.end_turn_pressed.connect(_on_end_turn_pressed)

	# 新手引导信号连接
	battle_ui.card_selected.connect(_on_tutorial_card_selected)
	battle_ui.enemy_selected.connect(_on_tutorial_enemy_selected)
	battle_ui.end_turn_pressed.connect(_on_tutorial_end_turn_pressed)
	battle_manager.turn_started.connect(_on_tutorial_turn_started)

# ==================== 事件处理 ====================

func _on_state_changed(_old: int, _new: int) -> void:
	_update_ui()

func _on_turn_started(_turn: int) -> void:
	_update_ui()

func _on_turn_ended(_turn: int) -> void:
	_update_ui()

func _on_battle_ended(result: int) -> void:
	if _battle_ended_handled:
		return
	_battle_ended_handled = true
	if result == 0:
		# 胜利 → 更新GameState
		GameState.hp = player.current_hp
		print("战斗：胜利！玩家HP=%d" % player.current_hp)

		# 自动存档
		_auto_save()

		# Boss击败后境界推进
		if is_boss_fight:
			var old_realm: int = GameState.current_realm
			# 金丹期Boss通关 → 跳转通关画面
			if old_realm >= 2:
				print("战斗：金丹期Boss击败！通关！")
				# 视觉反馈：胜利提示 + 短延迟 + 渐隐过渡
				# 修复 AI Player 反馈 (2026-07-14) "战斗结束时画面卡住 2 秒才跳到 reward 场景"
				# 原实现：硬等 1.5s 无任何视觉反馈，玩家感觉卡死
				# 新实现：log 提示 + 0.5s 短延迟（让玩家感知胜利）+ 0.4s 渐隐
				battle_ui.add_log("✨ 战斗胜利！境界通关！")
				# 修复 AI Player stuck 100s bug 2026-07-22：fade 期间禁用 BattleUI 输入 + BattleManager 处理
				_disable_battle_input()
				if is_inside_tree():
					await get_tree().create_timer(0.5).timeout
					if is_inside_tree():
						await _fade_battle_ui_and_change_scene("res://scenes/victory.tscn")
				return
			# 非最终Boss → 正常境界推进
			GameState.current_realm = mini(2, GameState.current_realm + 1)
			GameState.visited_node_ids.clear()
			GameState.current_node_id = ""
			print("战斗：Boss击败！境界 %d → %d (%s)" % [
				old_realm, GameState.current_realm, GameState.get_realm_name()
			])

		# 生成奖励
		var node_type: int = _get_node_type()
		var is_elite: bool = (node_type == 1)
		var reward: Variant = BattleReward.generate(is_elite, is_boss_fight, GameState.current_realm)

		# 存储奖励到GameState供奖励场景读取
		GameState.set_meta("last_reward", reward)

		# 视觉反馈：胜利提示 + 短延迟 + 渐隐过渡（修复 AI Player 反馈的卡顿 bug）
		battle_ui.add_log("✨ 战斗胜利！")
		# 修复 AI Player stuck 100s bug 2026-07-22：fade 期间禁用 BattleUI 输入 + BattleManager 处理
		_disable_battle_input()
		if is_inside_tree():
			await get_tree().create_timer(0.5).timeout
			if is_inside_tree():
				# 整个 BattleUI 渐隐，避免直接闪现切场景
				await _fade_battle_ui_and_change_scene("res://scenes/reward.tscn")
	else:
		# 失败 → 跳转结算
		GameState.hp = player.current_hp
		print("战斗：失败！")
		# 视觉反馈：失败提示 + 短延迟 + 渐隐过渡（同胜利流程）
		battle_ui.add_log("💀 战斗失败...")
		# 修复 AI Player stuck 100s bug 2026-07-22：fade 期间禁用 BattleUI 输入 + BattleManager 处理
		_disable_battle_input()
		if is_inside_tree():
			await get_tree().create_timer(0.5).timeout
			if is_inside_tree():
				await _fade_battle_ui_and_change_scene("res://scenes/settlement.tscn")

func _on_generation_chain(chain: Array) -> void:
	var chain_length: int = chain.size()
	var bonus_info: Dictionary = {}
	if chain_length >= 2:
		# chain[-2] 是上一张牌的元素（生者），chain[-1] 是当前牌（被生者）
		var prev_element: WuXing.Element = chain[chain_length - 2]
		bonus_info = WuXing.get_generation_bonus(prev_element)
	
	var message: String = "五行相生链触发！链长: %d" % chain_length
	if not bonus_info.is_empty():
		var description: String = bonus_info.get("description", "")
		var bonus_type: int = bonus_info.get("type", -1)
		var bonus_value: int = bonus_info.get("value", 0)
		var type_name: String = ""
		match bonus_type:
			WuXing.GenerationBonusType.DAMAGE_PERCENT:
				type_name = "伤害加成"
			WuXing.GenerationBonusType.FLAT_BLOCK:
				type_name = "格挡"
			WuXing.GenerationBonusType.DRAW_CARDS:
				type_name = "抽牌"
			WuXing.GenerationBonusType.HEAL:
				type_name = "回复"
			WuXing.GenerationBonusType.COST_REDUCE:
				type_name = "减费"
		if not type_name.is_empty():
			if bonus_type == WuXing.GenerationBonusType.DAMAGE_PERCENT:
				# 伤害类型显示乘数：value 是百分比，转为 ×1.XX 格式
				var effective_multiplier := 1.0 + bonus_value / 100.0
				message += "\n[%s] 伤害 ×%.2f" % [description, effective_multiplier]
			else:
				message += "\n[%s] %s +%d" % [description, type_name, bonus_value]
	
	battle_ui.add_log(message)

func _on_player_hp_changed(_old: int, new_hp: int, _max: int) -> void:
	# 同步HP到GameState
	GameState.hp = maxi(0, new_hp)
	_update_ui()

func _on_player_energy_changed(_old: int, _new: int, _max: int) -> void:
	_update_ui()

func _on_hand_changed(_hand: int) -> void:
	_update_ui()

func _on_card_selected(card_index: int) -> void:
	if battle_manager.can_play_card():
		battle_manager.player_play_card(card_index)
		_update_ui()

func _on_enemy_selected(enemy_index: int) -> void:
	# 存储选中的敌人索引，供下次出牌使用
	battle_manager.selected_enemy_index = enemy_index
	print("选中敌人: %d" % enemy_index)

func _on_end_turn_pressed() -> void:
	battle_manager.player_end_turn()
	_update_ui()

# ==================== 新手引导回调 ====================

func _on_tutorial_card_selected(card_index: int) -> void:
	battle_ui.on_card_clicked_during_tutorial()

func _on_tutorial_enemy_selected(enemy_index: int) -> void:
	battle_ui.on_enemy_selected_during_tutorial()

func _on_tutorial_end_turn_pressed() -> void:
	battle_ui.on_end_turn_pressed_during_tutorial()

func _on_tutorial_turn_started(turn: int) -> void:
	battle_ui.on_turn_started_during_tutorial(turn)

# ==================== 存档 ====================

## 自动存档
func _auto_save() -> void:
	var save_data: Dictionary = {
		"character_id": GameState.character_id,
		"hp": GameState.hp,
		"max_hp": GameState.max_hp,
		"spirit_stones": GameState.spirit_stones,
		"dao_xing": GameState.dao_xing,
		"total_dao_xing": GameState.total_dao_xing,
		"current_realm": GameState.current_realm,
		"current_node_id": GameState.current_node_id,
		"visited_node_ids": GameState.visited_node_ids.duplicate(),
		"collection": GameState.collection.duplicate(true),
		"deck": GameState.deck.duplicate(),
		"deck_max_size": GameState.deck_max_size,
		"deck_removal_count": GameState.deck_removal_count,
		"is_boss_defeated": GameState.is_boss_defeated.duplicate(),
	}
	if _save_system.auto_save(save_data):
		print("战斗：自动存档成功")
	else:
		print("战斗：自动存档失败")

# ==================== 辅助 ====================

func _get_node_type() -> int:
	if GameState.game_map:
		var realm: RealmMap = GameState.game_map.get_current_realm()
		if realm:
			var node: MapNode = realm.get_node_by_id(GameState.current_node_id)
			if node:
				return node.type
	return 0  # 默认COMBAT

func _update_ui() -> void:
	if battle_ui == null:
		return
	battle_ui.update_player_display(player)
	battle_ui.update_hand_display(player.get_hand())
	battle_ui.update_enemy_display(battle_manager.enemies)
	# 顶栏：回合 N + 场景名（从 MapNode.metadata 读取；fallback 为状态名）
	battle_ui.update_turn_display(battle_manager.turn_number, _get_location_name())
	battle_ui.update_pile_display(player.get_draw_pile_count(), player.get_discard_pile_count())
	battle_ui.update_status_display(player)

## 禁用战斗输入（战斗结束时调用，避免 LLM 在渐隐期发 click 触发已无效的信号链路）
## 修复 AI Player stuck 100s bug 2026-07-22
func _disable_battle_input() -> void:
	# 1. BattleUI 设为不可交互 + 不处理（fade 期间 AI Player 的 click 直接被 Godot 吞掉）
	# CanvasLayer 没有 mouse_filter 属性（继承自 CanvasLayer 而非 Control），仅设 process_mode
	if battle_ui:
		battle_ui.process_mode = Node.PROCESS_MODE_DISABLED
	# 2. BattleManager 停止处理（不响应 end_turn / play_card 等）
	if battle_manager:
		battle_manager.process_mode = Node.PROCESS_MODE_DISABLED
	# 3. AgentSocket 暂时不接受 click/key 命令（避免 LLM 抢在 change_scene 之前发）
	var socket := get_node_or_null("/root/AgentSocket")
	if socket and socket.has_method("set_input_paused"):
		socket.set_input_paused(true)

## 恢复战斗输入（新 battle 开始时调用）
func _enable_battle_input() -> void:
	# BattleUI 恢复处理
	if battle_ui:
		battle_ui.process_mode = Node.PROCESS_MODE_INHERIT
	# BattleManager 恢复处理
	if battle_manager:
		battle_manager.process_mode = Node.PROCESS_MODE_INHERIT
	# AgentSocket 恢复接受 click/key
	var socket := get_node_or_null("/root/AgentSocket")
	if socket and socket.has_method("set_input_paused"):
		socket.set_input_paused(false)

## 渐隐 BattleUI 后切换场景
## 修复 b00eda7a stuck bug (2026-07-25)：
## battle_ui 是 CanvasLayer（不是 CanvasItem），没有 modulate 属性。
## 原 tween_property(battle_ui, "modulate:a", ...) 创建无 Tweeners 的 Tween，
## 导致 await fade_tween.finished 永远阻塞，change_scene_to_file 永远不执行。
## AI Player 在 BATTLE_WIN state 停留 3+ 分钟（observed: exp_20260725_105535_6）。
## 修复：fade BattleUI 下所有 Control 子节点（CanvasItem 才有 modulate:a）。
func _fade_battle_ui_and_change_scene(scene_path: String) -> void:
	var fade_targets: Array[Control] = []
	if battle_ui:
		for child in battle_ui.get_children():
			if child is Control:
				fade_targets.append(child)
	if not fade_targets.is_empty():
		var fade_tween := create_tween()
		fade_tween.set_parallel(true)
		for ctrl in fade_targets:
			fade_tween.tween_property(ctrl, "modulate:a", 0.0, 0.4)
		await fade_tween.finished
	else:
		# Fallback：如果 BattleUI 没有 Control 子节点（理论不可能），硬等 0.4s
		await get_tree().create_timer(0.4).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(scene_path)

## 读取当前战斗节点的场景名
func _get_location_name() -> String:
	if GameState.game_map:
		var realm: RealmMap = GameState.game_map.get_current_realm()
		if realm:
			var node: MapNode = realm.get_node_by_id(GameState.current_node_id)
			if node and node.metadata.has("location_name"):
				return node.metadata["location_name"]
	# Fallback：状态名
	return battle_manager.get_state_name()

# ==================== 输入处理 ====================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_SPACE:
			if battle_manager.can_play_card():
				battle_manager.player_end_turn()
				_update_ui()
