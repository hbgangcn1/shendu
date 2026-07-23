## 战斗管理器
## 控制整个战斗流程的状态机
## 管理回合切换、胜负判定、五行相生链检测

# implements: design/07-combat-system-spec.md
# implements_philosophy: rule_1_core_loop_first, rule_3_three_layer_loops, rule_6_flow_channel
# avoids_red_line: red_6_ui_overload, red_7_difficulty_wall

class_name BattleManager
extends Node

const CardDataResource := preload("res://scripts/core/card_data.gd")

# ==================== 战斗状态枚举 ====================
enum BattleStateEnum {
	IDLE,
	BATTLE_START,
	PLAYER_TURN,
	CARD_SELECTION,
	RESOLUTION,
	ENEMY_TURN,
	CLEANUP,
	CHECK_END,
	NEXT_TURN,
	BATTLE_WIN,
	BATTLE_LOSE,
}

# ==================== 信号 ====================

signal state_changed(old_state: int, new_state: int)
signal turn_started(turn_number: int)
signal turn_ended(turn_number: int)
signal battle_started
signal battle_ended(result: int)  # 0=胜利 1=失败
signal generation_chain_triggered(chain: Array)  # 五行相生链触发
signal chain_length_changed(length: int)  # 相生链长度变化（UI用）
signal battle_log(message: String)  # 战斗日志（转发到UI）

# ==================== 状态属性 ====================

const MAX_TURNS := 100  # 防止无限循环的最大回合数

var current_state: BattleStateEnum = BattleStateEnum.IDLE
var turn_number: int = 0
var selected_enemy_index: int = 0  # 选中的敌人索引

# ==================== 战斗单位 ====================

var player: Player = null
var enemies: Array = []  # Actor[]

# ==================== 五行相生链 ====================

const CHAIN_CLIMAX_THRESHOLD: int = 3  # 高潮触发阈值
const CHAIN_MAX_TRIGGERS: int = 5  # 单回合相生触发上限

## 阶梯衰减表（索引=触发次数-1，抽牌和减费豁免不受衰减）
## 第1-2次无衰减，第3次75%，第4次50%，第5次25%
const CHAIN_DECAY_TABLE: Array[float] = [1.0, 1.0, 0.75, 0.5, 0.25]

var _has_last_element: bool = false  # 是否有上一张打出的卡牌
var last_played_element: WuXing.Element = WuXing.Element.METAL  # 上一张打出的卡牌元素 (占位初始值)
var generation_chain: Array = []  # 当前相生链
var pending_generation_bonus: Dictionary = {}  # 待结算的相生增益
var _chain_trigger_count: int = 0  # 本回合相生触发次数
var pending_damage_multiplier: float = 1.0  # 临时伤害倍率（相生加成，不修改 card.damage）

# ==================== 初始化 ====================

func _ready() -> void:
	pass

# ==================== 战斗流程 ====================

## 开始战斗
func start_battle(player_ref: Player, enemy_list: Array) -> void:
	player = player_ref
	enemies = enemy_list.duplicate()
	turn_number = 0

	# 连接信号
	_connect_signals()

	# 初始化玩家牌堆
	player.init_deck()

	_change_state(BattleStateEnum.BATTLE_START)
	print("BattleManager: 战斗开始！")

## 结束战斗
func end_battle(result: int) -> void:
	_change_state(BattleStateEnum.IDLE)
	battle_ended.emit(result)
	print("BattleManager: 战斗结束，结果=%d" % result)

# ==================== 状态机 ====================

func _change_state(new_state: BattleStateEnum) -> void:
	var old_state := current_state
	current_state = new_state

	match new_state:
		BattleStateEnum.BATTLE_START:
			_on_battle_start()
		BattleStateEnum.PLAYER_TURN:
			_on_player_turn_start()
		BattleStateEnum.ENEMY_TURN:
			_on_enemy_turn_start()
		BattleStateEnum.CLEANUP:
			_on_cleanup()
		BattleStateEnum.BATTLE_WIN:
			end_battle(0)
		BattleStateEnum.BATTLE_LOSE:
			end_battle(1)

	state_changed.emit(old_state, new_state)

## 状态处理：战斗开始
func _on_battle_start() -> void:
	# 检查战斗单位
	if player == null or enemies.is_empty():
		push_error("BattleManager: 战斗单位未初始化")
		_change_state(BattleStateEnum.IDLE)
		return

	# 所有敌人选择初始意图
	for enemy in enemies:
		if enemy is Enemy and enemy.is_alive:
			enemy.choose_intent({})

	battle_started.emit()
	_on_next_turn()

	## 切换到下一回合
func _on_next_turn() -> void:
	_change_state(BattleStateEnum.PLAYER_TURN)

## 状态处理：玩家回合开始
func _on_player_turn_start() -> void:
	turn_number += 1
	turn_started.emit(turn_number)

	# 重置相生链
	_has_last_element = false
	generation_chain.clear()
	_chain_trigger_count = 0

	# 玩家回合开始（重置能量、抽牌）
	player.start_turn()
	print("BattleManager: 第 %d 回合，玩家回合" % turn_number)

	# 进入选牌阶段
	_change_state(BattleStateEnum.CARD_SELECTION)

## 状态处理：选牌阶段
func _on_card_selection_start() -> void:
	# 等待玩家操作（出牌/结束回合/蓄势）
	pass

## 状态处理：结算阶段
func _on_resolution() -> void:
	# 结算由 player_play_card 触发，此状态为预留
	pass

## 状态处理：敌人回合开始
func _on_enemy_turn_start() -> void:
	# 所有敌人行动
	for enemy in enemies:
		if enemy and enemy.is_alive:
			_enemy_action(enemy)

	# 检查玩家是否死亡
	if not player.is_alive:
		_change_state(BattleStateEnum.BATTLE_LOSE)
		return

	# 进入回合结束
	_change_state(BattleStateEnum.CLEANUP)

## 状态处理：回合结束
func _on_cleanup() -> void:
	turn_ended.emit(turn_number)

	# 检查所有敌人是否死亡
	var all_enemies_dead := true
	for enemy in enemies:
		if enemy and enemy.is_alive:
			all_enemies_dead = false
			break

	if all_enemies_dead:
		_change_state(BattleStateEnum.BATTLE_WIN)
		return

	# 检查回合上限
	if turn_number >= MAX_TURNS:
		print("BattleManager: 达到最大回合数 %d" % MAX_TURNS)
		_change_state(BattleStateEnum.BATTLE_LOSE)
		return

	# 下一回合
	_on_next_turn()

# ==================== 玩家行动 ====================

## 玩家打出一张卡牌
func player_play_card(card_index: int) -> bool:
	if current_state != BattleStateEnum.CARD_SELECTION:
		print("BattleManager: 不是玩家回合，无法出牌")
		return false

	# 打出卡牌
	if not player.play_card(card_index):
		return false

	# 获取打出的卡牌（已从手牌移到弃牌堆）
	if player.discard_pile.is_empty():
		print("BattleManager: 弃牌堆为空，无法获取打出的卡牌")
		return false
	var played_card: CardDataResource = player.discard_pile.back()

	# 检测五行相生链
	_check_generation_chain(played_card)

	# 蓄势爆发检测
	player.apply_charge_burst(played_card)

	# 处理卡牌效果
	_process_card_effect(played_card)

	return true

## 玩家结束回合
func player_end_turn() -> void:
	if current_state != BattleStateEnum.CARD_SELECTION:
		return

	player.end_turn()
	_change_state(BattleStateEnum.ENEMY_TURN)

# ==================== 卡牌效果处理 ====================

func _process_card_effect(card: CardDataResource) -> void:
	# 重置临时伤害倍率
	pending_damage_multiplier = 1.0

	# 结算相生增益
	if not pending_generation_bonus.is_empty():
		_apply_generation_bonus(card, pending_generation_bonus)
		pending_generation_bonus = {}

	# 从 effects[] 数组结算（trigger/action 结构化格式）
	if card.effects.is_empty():
		# 无 effects 时 fallback 到兼容字段
		_process_compat_effects(card)
		return

	for effect in card.effects:
		var trigger: String = effect.get("trigger", "")
		# 只结算立即触发的 effect（on_play / on_attack）
		if trigger != "on_play" and trigger != "on_attack":
			continue
		var action: Dictionary = effect.get("action", {})
		var action_type: String = action.get("type", "")
		var action_value: int = int(action.get("value", 0))
		var action_element: int = int(action.get("element", card.element))

		match action_type:
			"Damage":
				# 应用相生伤害倍率（临时，不修改 card.damage）
				var final_damage := int(action_value * pending_damage_multiplier)
				# 选择目标敌人（优先选中的，否则第一个存活的）
				var target_enemy: Actor = null
				if selected_enemy_index >= 0 and selected_enemy_index < enemies.size():
					var candidate: Actor = enemies[selected_enemy_index]
					if candidate.is_alive:
						target_enemy = candidate
				if target_enemy == null:
					for enemy: Actor in enemies:
						if enemy.is_alive:
							target_enemy = enemy
							break
				if target_enemy != null:
					var is_chain := generation_chain.size() > 1
					var actual_damage: int = target_enemy.take_damage(
						final_damage, action_element as WuXing.Element, is_chain
					)
					print("BattleManager: %s 使用 %s 对 %s 造成 %d 伤害%s" % [
						player.actor_name, card.name, target_enemy.actor_name, actual_damage,
						" (含相生×%.2f)" % pending_damage_multiplier if pending_damage_multiplier > 1.0 else ""
					])
			"Block":
				player.gain_shield(action_value)
				print("BattleManager: %s 获得 %d 护盾" % [player.actor_name, action_value])
			"Draw":
				player.draw_cards(action_value)
				print("BattleManager: %s 抽 %d 张牌" % [player.actor_name, action_value])
			"Heal":
				var healed := player.heal(action_value)
				print("BattleManager: %s 回复 %d HP" % [player.actor_name, healed])
			"Purify":
				player.reduce_mo_nian(action_value)
				print("BattleManager: %s 净化，魔念 -%d" % [player.actor_name, action_value])
			"Erosion":
				player.add_erosion(action_value, card.name)
				print("BattleManager: %s 获得 %d 侵蚀 [%s]" % [player.actor_name, action_value, card.name])

## Fallback: 从兼容字段结算（effects 为空时）
func _process_compat_effects(card: CardDataResource) -> void:
	# 计算相生伤害加成（临时，不修改 card.damage）
	var damage_multiplier := 1.0
	if not pending_generation_bonus.is_empty():
		var bonus_type = pending_generation_bonus.get("type", -1)
		if bonus_type == WuXing.GenerationBonusType.DAMAGE_PERCENT:
			damage_multiplier = 1.0 + pending_generation_bonus.get("value", 0) / 100.0

	if card.damage > 0:
		var final_damage := int(card.damage * damage_multiplier)
		# 选择目标敌人（优先选中的，否则第一个存活的）
		var target_enemy: Actor = null
		if selected_enemy_index >= 0 and selected_enemy_index < enemies.size():
			var candidate: Actor = enemies[selected_enemy_index]
			if candidate.is_alive:
				target_enemy = candidate
		if target_enemy == null:
			for enemy: Actor in enemies:
				if enemy.is_alive:
					target_enemy = enemy
					break
		if target_enemy != null:
			var is_chain := generation_chain.size() > 1
			var actual_damage: int = target_enemy.take_damage(
				final_damage, card.element, is_chain
			)
			print("BattleManager: %s 使用 %s 对 %s 造成 %d 伤害%s" % [
				player.actor_name, card.name, target_enemy.actor_name, actual_damage,
				" (含相生×%.2f)" % damage_multiplier if damage_multiplier > 1.0 else ""
			])
	if card.block > 0:
		player.gain_shield(card.block)
		print("BattleManager: %s 获得 %d 护盾" % [player.actor_name, card.block])
	if card.draw_cards > 0:
		player.draw_cards(card.draw_cards)
		print("BattleManager: %s 抽 %d 张牌" % [player.actor_name, card.draw_cards])
	if card.heal > 0:
		var healed := player.heal(card.heal)
		print("BattleManager: %s 回复 %d HP" % [player.actor_name, healed])

# ==================== 敌人行动 ====================

func _enemy_action(enemy: Actor) -> void:
	if not enemy is Enemy:
		return

	# 显示敌人即将执行的意图
	var intent_desc: String = enemy.get_intent_description()
	var intent_detail: String = enemy.get_intent_detail()
	var msg: String = "%s → %s" % [enemy.actor_name, intent_desc]
	if not intent_detail.is_empty():
		msg += " (%s)" % intent_detail
	battle_log.emit(msg)

	# 执行意图
	var result: Dictionary = enemy.execute_intent(player)

	# 处理结果
	if result.get("success", false):
		var result_type = result.get("type", -1)
		match result_type:
			Enemy.IntentType.ATTACK, Enemy.IntentType.PIERCE, Enemy.IntentType.ATK_BUFF:
				var dmg: int = result.get("damage", 0)
				battle_log.emit("  → 造成 %d 伤害" % dmg)
			Enemy.IntentType.DEFEND, Enemy.IntentType.DEF_BUFF:
				var shield: int = result.get("shield", 0)
				battle_log.emit("  → 获得 %d 格挡" % shield)
			Enemy.IntentType.HEAL:
				var healed: int = result.get("healed", 0)
				battle_log.emit("  → 回复 %d 生命" % healed)
			Enemy.IntentType.WEAKEN, Enemy.IntentType.VULNERABLE, Enemy.IntentType.POISON:
				var debuff: String = result.get("debuff_type", "")
				battle_log.emit("  → 施加 %s" % debuff)
			Enemy.IntentType.PHASE_SHIFT:
				battle_log.emit("  → 气场切换")

# ==================== 五行相生链检测 ====================

func _check_generation_chain(card: CardDataResource) -> void:
	var card_element: WuXing.Element = card.element

	# 检查是否与上一张牌形成相生关系
	if _has_last_element and WuXing.is_generation(last_played_element, card_element):
		# 相生链延续
		generation_chain.append(card_element)

		# 检查单回合触发上限
		_chain_trigger_count += 1
		if _chain_trigger_count > CHAIN_MAX_TRIGGERS:
			print("BattleManager: 相生触发达上限 %d，本回合不再触发" % CHAIN_MAX_TRIGGERS)
		else:
			generation_chain_triggered.emit(generation_chain)
			chain_length_changed.emit(generation_chain.size())
			# 获取相生增益信息（含衰减后的值）
			pending_generation_bonus = WuXing.get_generation_bonus(last_played_element).duplicate()
			# 应用阶梯衰减（抽牌和减费豁免）
			var bonus_type = pending_generation_bonus.get("type", -1)
			var is_exempt: bool = (bonus_type == WuXing.GenerationBonusType.DRAW_CARDS or
					bonus_type == WuXing.GenerationBonusType.COST_REDUCE)
			var decay := 1.0 if is_exempt else _calculate_chain_decay()
			# 直接修改 bonus value，这样下游所有消费者自动使用衰减值
			pending_generation_bonus["value"] = int(pending_generation_bonus.get("value", 0) * decay)
			pending_generation_bonus["decay_applied"] = decay < 1.0
			print("BattleManager: 五行相生链触发！链长=%d 触发次数=%d 衰减=%.2f %s" % [
				generation_chain.size(), _chain_trigger_count, decay,
				"(豁免)" if is_exempt else ""
			])
	else:
		# 相生链中断，重新开始
		generation_chain.clear()
		pending_generation_bonus = {}
		generation_chain.append(card_element)
		chain_length_changed.emit(1)

	# 更新上一张牌元素
	last_played_element = card_element
	_has_last_element = true

## 计算相生衰减系数
## 基于本回合触发次数（trigger_count），使用阶梯衰减表
## 触发1-2次无衰减，第3次75%，第4次50%，第5次25%
func _calculate_chain_decay() -> float:
	var idx := _chain_trigger_count - 1
	if idx < 0 or idx >= CHAIN_DECAY_TABLE.size():
		return 1.0
	return CHAIN_DECAY_TABLE[idx]

## 应用相生增益效果（ DAMAGE_PERCENT 改为临时计算，不修改 card.damage）
func _apply_generation_bonus(card: CardDataResource, bonus: Dictionary) -> void:
	if bonus.is_empty():
		return

	var bonus_type = bonus.get("type", -1)
	var bonus_value = bonus.get("value", 0)
	var description = bonus.get("description", "")

	match bonus_type:
		WuXing.GenerationBonusType.DAMAGE_PERCENT:
			# 伤害百分比加成：存储到 pending_multiplier，由 _process_card_effect 统一应用
			pending_damage_multiplier = 1.0 + bonus_value / 100.0
			print("BattleManager: [%s] 伤害 ×%.2f" % [description, pending_damage_multiplier])
		WuXing.GenerationBonusType.FLAT_BLOCK:
			# 固定格挡加成（直接发放，不修改 card）
			player.gain_shield(bonus_value)
			print("BattleManager: [%s] 格挡 +%d" % [description, bonus_value])
		WuXing.GenerationBonusType.DRAW_CARDS:
			# 抽牌
			player.draw_cards(bonus_value)
			print("BattleManager: [%s] 抽 %d 张牌" % [description, bonus_value])
		WuXing.GenerationBonusType.HEAL:
			# 回复生命
			var healed = player.heal(bonus_value)
			print("BattleManager: [%s] 回复 %d 生命" % [description, healed])
		WuXing.GenerationBonusType.COST_REDUCE:
			# 费用减免（返还灵力）
			var refund = min(bonus_value, card.cost)
			if refund > 0:
				player.current_energy += refund
				print("BattleManager: [%s] 费用 -%d，返还 %d 灵力" % [description, bonus_value, refund])

# ==================== 暴击系统 ====================

## 触发暴击：伤害×2 + 获得运气牌
func _trigger_crit(card: CardDataResource) -> void:
	# 伤害翻倍
	card.damage *= 2
	print("BattleManager: 🔥 暴击！%s 伤害翻倍 → %d" % [card.name, card.damage])

	# 生成运气牌加入手牌
	var luck_card := _create_luck_card()
	player.hand.append(luck_card)
	player.hand_changed.emit(player.hand.size())
	print("BattleManager: 获得运气牌「%s」" % luck_card.name)

## 生成临时运气牌（0费，效果随机，本回合有效）
func _create_luck_card() -> CardDataResource:
	var card := CardDataResource.new()
	card.id = "LUCK_%d" % randi()
	card.name = "运气牌"
	card.cost = 0
	card.element = player.element
	card.description = "暴击馈赠。随机效果。"

	# 随机效果：伤害/格挡/抽牌/回血
	var roll := randi() % 4
	match roll:
		0:  # 伤害
			card.damage = randi_range(8, 15)
			card.effects = [{"trigger": "on_play", "action": {"type": "Damage", "value": card.damage}}]
			card.description = "造成 %d 火焰伤害" % card.damage
		1:  # 格挡
			card.block = randi_range(6, 12)
			card.effects = [{"trigger": "on_play", "action": {"type": "Block", "value": card.block}}]
			card.description = "获得 %d 格挡" % card.block
		2:  # 抽牌
			card.draw_cards = randi_range(1, 3)
			card.effects = [{"trigger": "on_play", "action": {"type": "Draw", "value": card.draw_cards}}]
			card.description = "抽 %d 张牌" % card.draw_cards
		3:  # 回血
			card.heal = randi_range(5, 10)
			card.effects = [{"trigger": "on_play", "action": {"type": "Heal", "value": card.heal}}]
			card.description = "回复 %d 生命" % card.heal

	return card

# ==================== 信号连接 ====================

func _connect_signals() -> void:
	# 玩家死亡
	if player and not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

	# 心魔低语
	if player and not player.mo_nian_whisper_triggered.is_connected(_on_mo_nian_whisper):
		player.mo_nian_whisper_triggered.connect(_on_mo_nian_whisper)

	# 敌人死亡
	for enemy in enemies:
		if enemy and not enemy.died.is_connected(_on_enemy_died):
			enemy.died.connect(_on_enemy_died.bind(enemy))

func _disconnect_signals() -> void:
	# 断开玩家死亡信号
	if player and player.died.is_connected(_on_player_died):
		player.died.disconnect(_on_player_died)

	# 断开心魔低语
	if player and player.mo_nian_whisper_triggered.is_connected(_on_mo_nian_whisper):
		player.mo_nian_whisper_triggered.disconnect(_on_mo_nian_whisper)

	# 断开敌人死亡信号
	for enemy in enemies:
		if enemy and enemy.died.is_connected(_on_enemy_died):
			enemy.died.disconnect(_on_enemy_died)

func _exit_tree() -> void:
	_disconnect_signals()

func _on_player_died() -> void:
	_change_state(BattleStateEnum.BATTLE_LOSE)

## 心魔低语处理：跳过下一次抽牌（简化实现：减少手牌上限1张，持续1回合）
func _on_mo_nian_whisper() -> void:
	print("BattleManager: 心魔低语！魔念=%d" % player.mo_nian)
	player.hand_size = max(3, player.hand_size - 1)
	print("BattleManager: 手牌上限临时降至 %d" % player.hand_size)
	if not turn_started.is_connected(_on_whisper_recover):
		turn_started.connect(_on_whisper_recover, CONNECT_ONE_SHOT)

func _on_whisper_recover(_turn: int) -> void:
	player.hand_size = 4
	print("BattleManager: 心魔低语效果结束，手牌上限恢复")

func _on_enemy_died(enemy: Actor) -> void:
	print("BattleManager: %s 被击败！" % enemy.actor_name)
	# 检查是否所有敌人都死了（在 CLEANUP 状态处理）

# ==================== 查询方法 ====================

## 获取当前状态名称
func get_state_name() -> String:
	match current_state:
		BattleStateEnum.IDLE:
			return "空闲"
		BattleStateEnum.BATTLE_START:
			return "战斗开始"
		BattleStateEnum.PLAYER_TURN:
			return "玩家回合"
		BattleStateEnum.CARD_SELECTION:
			return "选牌中"
		BattleStateEnum.RESOLUTION:
			return "结算中"
		BattleStateEnum.ENEMY_TURN:
			return "敌人回合"
		BattleStateEnum.CLEANUP:
			return "回合结束"
		BattleStateEnum.CHECK_END:
			return "检查结束"
		BattleStateEnum.NEXT_TURN:
			return "下一回合"
		BattleStateEnum.BATTLE_WIN:
			return "战斗胜利"
		BattleStateEnum.BATTLE_LOSE:
			return "战斗失败"
	return "未知"

## 是否可以出牌
func can_play_card() -> bool:
	return current_state == BattleStateEnum.CARD_SELECTION

## 获取战斗状态摘要
func get_battle_summary() -> String:
	var summary := "=== 战斗状态 ===\n"
	summary += "状态: %s | 回合: %d\n" % [get_state_name(), turn_number]
	summary += "玩家: %s\n" % player.get_status_summary()

	for i in range(enemies.size()):
		var enemy: Actor = enemies[i]
		if enemy.is_alive:
			summary += "敌人%d: %s\n" % [i + 1, enemy.get_status_summary()]

	if generation_chain.size() > 1:
		summary += "相生链: %d 层\n" % generation_chain.size()

	return summary
