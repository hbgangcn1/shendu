## 玩家单位类
## 管理手牌、能量、抽牌堆、弃牌堆等玩家特有属性

# implements: design/07-combat-system-spec.md
# implements_philosophy: rule_1_core_loop_first, rule_3_three_layer_loops, rule_6_flow_channel
# avoids_red_line: red_6_ui_overload, red_7_difficulty_wall

class_name Player
extends Actor

const CardDataResource := preload("res://scripts/core/card_data.gd")
const MANA_REGEN: int = 4  # 每回合灵力回复量

# ==================== 信号 ====================

signal energy_changed(old_energy: int, new_energy: int, max_energy: int)
signal card_drawn(card)
signal card_played(card)
signal hand_changed(hand_size: int)
signal deck_shuffled

# ==================== 玩家属性 ====================

var max_energy: int = 10  # 当前灵力上限
var current_energy: int = 10  # 当前灵力值

# ==================== 魔念系统 ====================

var mo_nian: int = 0  # 魔念值
var erosion: int = 0  # 侵蚀值（与魔念互斥）
const MO_NIAN_OVERLOAD_THRESHOLD: int = 8  # 过载阈值：单回合灵力花费>此值→+1魔念
const MO_NIAN_CRITICAL_THRESHOLD: int = 5  # 临界阈值：魔念≥此值→心魔低语
var mo_nian_whisper_active: bool = false  # 心魔低语是否激活
var whisper_triggered_this_battle: bool = false  # 本场战斗是否已触发过低语

signal mo_nian_changed(old_value: int, new_value: int)
signal mo_nian_whisper_triggered  # 心魔低语触发

# ==================== 侵蚀系统 ====================

const EROSION_THRESHOLD_MICRO: int = 25   # 微尘阈值
const EROSION_THRESHOLD_MURKY: int = 50   # 浊念阈值
const EROSION_THRESHOLD_MADNESS: int = 75 # 疯魔阈值
const EROSION_MAX: int = 100              # 入魔

# ==================== 魔念管理 ====================

## 增加魔念（与侵蚀互斥：魔念↑则侵蚀↓）
func _add_mo_nian(amount: int, source: String = "") -> void:
	var old := mo_nian
	mo_nian += amount
	# 互斥：获得魔念时侵蚀减少
	if erosion > 0:
		erosion = maxi(0, erosion - amount)
		print("Player: 侵蚀 -%d → %d (互斥)" % [amount, erosion])
	mo_nian_changed.emit(old, mo_nian)
	print("Player: 魔念 +%d → %d [%s]" % [amount, mo_nian, source])

## 减少魔念（与侵蚀互斥：侵蚀↑则魔念↓）
func reduce_mo_nian(amount: int) -> void:
	var old := mo_nian
	mo_nian = max(0, mo_nian - amount)
	mo_nian_changed.emit(old, mo_nian)
	if mo_nian < MO_NIAN_CRITICAL_THRESHOLD:
		mo_nian_whisper_active = false
	print("Player: 魔念 -%d → %d" % [amount, mo_nian])

## 增加侵蚀（与魔念互斥：侵蚀↑则魔念↓）
func add_erosion(amount: int, source: String = "") -> void:
	var old := erosion
	erosion = mini(EROSION_MAX, erosion + amount)
	var actual_gain := erosion - old
	# 互斥：获得侵蚀时魔念减少
	if mo_nian > 0:
		var reduction := mini(mo_nian, actual_gain)
		mo_nian -= reduction
		mo_nian_changed.emit(mo_nian, mo_nian)
		print("Player: 魔念 -%d → %d (侵蚀互斥)" % [reduction, mo_nian])
	print("Player: 侵蚀 +%d → %d [%s]" % [actual_gain, erosion, source])
	_check_erosion_effects()

## 减少侵蚀
func reduce_erosion(amount: int) -> void:
	erosion = maxi(0, erosion - amount)
	print("Player: 侵蚀 -%d → %d" % [amount, erosion])

## 检查侵蚀效果
func _check_erosion_effects() -> void:
	# 微尘：手牌污染（暂用print标记，后续实现腐化牌）
	if erosion >= EROSION_THRESHOLD_MICRO and erosion < EROSION_THRESHOLD_MURKY:
		print("Player: 侵蚀达到微尘级 (%d)，手牌可能被污染" % erosion)
	# 浊念：每回合-1最大生命
	elif erosion >= EROSION_THRESHOLD_MURKY and erosion < EROSION_THRESHOLD_MADNESS:
		print("Player: 侵蚀达到浊念级 (%d)，最大生命-1" % erosion)
		max_hp = maxi(1, max_hp - 1)
	# 疯魔：抽牌费用可能+1
	elif erosion >= EROSION_THRESHOLD_MADNESS:
		print("Player: 侵蚀达到疯魔级 (%d)，卡牌费用可能增加" % erosion)

## 清除全部魔念
func clear_mo_nian() -> void:
	var old := mo_nian
	mo_nian = 0
	mo_nian_whisper_active = false
	mo_nian_changed.emit(old, mo_nian)
	print("Player: 魔念清除")

# ==================== 灵力系统 ====================

var max_mana: int = 10  # 最大灵力上限（绝对上限）
var turn_spent_mana: int = 0  # 本回合已花费灵力
var same_element_streak: int = 0  # 连续同属性出牌计数
var cards_played_this_turn: int = 0  # 本回合已出牌数
var last_played_element: WuXing.Element = WuXing.Element.METAL  # 上一张打出的卡牌元素
var zero_mana_streak: int = 0  # 连续灵力为 0 的回合数
var exhausted: bool = false  # 枯竭状态

# ==================== 蓄势系统 ====================

var charge_stacks: int = 0  # 蓄势层数
var charge_shield: float = 0.0  # 蓄势减伤比例（0.0-1.0）
var charge_ready: bool = false  # 蓄势爆发就绪

# ==================== 牌堆管理 ====================

var draw_pile: Array = []      # 抽牌堆
var hand: Array = []           # 手牌
var discard_pile: Array = []   # 弃牌堆
var exhaust_pile: Array = []   # 消耗堆（永久移除的卡）

var hand_size: int = 4         # 每回合抽牌数 (减少初始手牌 1 张)

# ==================== 初始化 ====================

func _init(
	p_name: String = "玩家",
	p_hp: int = 80,
	p_elem: WuXing.Element = WuXing.Element.FIRE,
	p_energy: int = 10
) -> void:
	super._init(p_name, p_hp, p_elem)
	max_energy = p_energy
	current_energy = p_energy


# ==================== 牌堆操作 ====================

## 初始化牌堆（从 GameState.deck 加载，转换 Dictionary→CardDataResource）
func init_deck() -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()

	# 优先使用 GameState.get_deck_cards()（从卡牌池中选取的出战卡组）
	var deck_cards: Array = GameState.get_deck_cards()
	if not deck_cards.is_empty():
		for card_data in deck_cards:
			var card: CardDataResource = _ensure_card_resource(card_data)
			if card:
				draw_pile.append(card)
	else:
		# fallback：从 MVP 卡池加载
		var mvp_cards := CardPool.get_mvp_pool()
		for card in mvp_cards:
			draw_pile.append(card)

	# 洗牌
	_shuffle_draw_pile()
	print("Player: 初始化牌堆 %d 张卡牌（来源: %s）" % [
		draw_pile.size(),
		"GameState牌库" if not GameState.get_deck_cards().is_empty() else "CardPool MVP"
	])

## 确保卡牌数据是 CardDataResource 类型
## GameState.deck 可能是 Dictionary（starter deck）或 CardDataResource（奖励卡）
func _ensure_card_resource(data) -> CardDataResource:
	if data is CardDataResource:
		return data
	if data is Dictionary:
		var card := CardDataResource.new()
		card.id = data.get("id", "")
		card.name = data.get("name", data.get("card_name", ""))
		card.description = data.get("description", "")
		card.cost = data.get("cost", 0)
		# element：可能是 string 或 int
		var elem_val: Variant = data.get("element", 0)
		if elem_val is String:
			card.set_element_from_string(elem_val)
		else:
			card.element = elem_val as WuXing.Element
		# card_kind：可能是 string 或 int
		var kind_val: Variant = data.get("card_kind", data.get("card_type", "attack"))
		if kind_val is String:
			card.set_kind_from_string(kind_val)
		else:
			card.card_kind = kind_val
		# rarity：可能是 string 或 int
		var rar_val: Variant = data.get("rarity", "common")
		if rar_val is String:
			card.set_rarity_from_string(rar_val)
		else:
			card.rarity = rar_val
		card.damage = data.get("damage", 0)
		card.block = data.get("block", 0)
		card.heal = data.get("heal", 0)
		card.draw_cards = data.get("draw_cards", 0)
		card.art_path = data.get("art_path", data.get("image_path", ""))
		# is_exhaust 退回到 tags.has("exhaust")
		if data.get("is_exhaust", false):
			if not card.tags.has("exhaust"):
				card.tags.append("exhaust")
		card.effects = data.get("effects", [])
		# 从兼容字段生成 effects（starter deck 没有 effects 数组）
		if card.effects.is_empty():
			if card.damage > 0:
				card.effects.append({
					"trigger": "on_play",
					"action": {"type": "Damage", "target": "enemy", "value": card.damage, "element": card.element}
				})
			if card.block > 0:
				card.effects.append({
					"trigger": "on_play",
					"action": {"type": "Block", "target": "self", "value": card.block}
				})
			if card.heal > 0:
				card.effects.append({
					"trigger": "on_play",
					"action": {"type": "Heal", "target": "self", "value": card.heal}
				})
			if card.draw_cards > 0:
				card.effects.append({
					"trigger": "on_play",
					"action": {"type": "Draw", "target": "self", "value": card.draw_cards}
				})
		return card
	push_warning("Player: 无法转换卡牌数据类型: %s" % str(typeof(data)))
	return null

## 洗牌
func _shuffle_draw_pile() -> void:
	draw_pile.shuffle()
	deck_shuffled.emit()

## 抽牌
func draw_cards(_count: int = -1) -> Array:
	# 补牌模式：只抽到手牌上限（hand_size - 魔念），不固定抽N张
	var draw_count := maxi(1, hand_size - mo_nian - hand.size())

	var drawn: Array = []
	for i in range(draw_count):
		if draw_pile.is_empty():
			# 弃牌堆洗入抽牌堆
			if discard_pile.is_empty():
				break  # 无牌可抽
			_reshuffle_discard()

		var card: CardDataResource = draw_pile.pop_back()
		hand.append(card)
		drawn.append(card)
		card_drawn.emit(card)

	if drawn.size() > 0:
		hand_changed.emit(hand.size())

	return drawn
func play_card(card_index: int) -> bool:
	if card_index < 0 or card_index >= hand.size():
		return false

	var card: CardDataResource = hand[card_index]

	# 打牌上限检查（15张/回合安全阀）
	if cards_played_this_turn >= 15:
		print("Player: 达到打牌上限 15 张")
		return false

	# 检查能量
	if card.cost > current_energy:
		print("Player: 能量不足，需要 %d，当前 %d" % [card.cost, current_energy])
		return false

	# 扣灵力
	var old_energy := current_energy
	current_energy -= card.cost
	turn_spent_mana += card.cost
	energy_changed.emit(old_energy, current_energy, max_energy)

	# 追踪灵力耗尽
	if current_energy == 0:
		zero_mana_streak += 1
	else:
		zero_mana_streak = 0

	# 魔念过载检测：单回合灵力花费 > 阈值（方案A：超出×0.5）
	if turn_spent_mana > MO_NIAN_OVERLOAD_THRESHOLD:
		var overload_gain := int((turn_spent_mana - MO_NIAN_OVERLOAD_THRESHOLD) * 0.5)
		if overload_gain > 0:
			_add_mo_nian(overload_gain, "过载A(花费%d)" % turn_spent_mana)

	# 移到弃牌堆（除非是消耗牌）
	hand.remove_at(card_index)
	if card.is_exhaust():
		exhaust_pile.append(card)
	else:
		discard_pile.append(card)

	card_played.emit(card)
	hand_changed.emit(hand.size())
	cards_played_this_turn += 1

	# 连续同属性追踪（过载方案C）
	if card.element == last_played_element:
		same_element_streak += 1
	else:
		same_element_streak = 1
	last_played_element = card.element
	# 连续3同属性→+1魔念
	if same_element_streak >= 3:
		_add_mo_nian(1, "过载C(连续%d同属性)" % same_element_streak)

	return true

## 弃掉所有手牌
func discard_hand() -> void:
	while hand.size() > 0:
		var card: CardDataResource = hand.pop_back()
		discard_pile.append(card)
	hand_changed.emit(0)

## 消耗一张手牌（永久移除）
func exhaust_card(card_index: int) -> bool:
	if card_index < 0 or card_index >= hand.size():
		return false

	var card: CardDataResource = hand[card_index]
	hand.remove_at(card_index)
	exhaust_pile.append(card)
	hand_changed.emit(hand.size())
	return true

# ==================== 回合管理 ====================

## 开始回合（灵力回复、抽牌）
func start_turn() -> void:
	# 枯竭惩罚：减少回复量
	var regen := MANA_REGEN
	if exhausted:
		regen = max(2, regen - 1)
		exhausted = false

	# 灵力回复（累加而非重置）
	var old_energy := current_energy
	current_energy = min(max_mana, current_energy + regen + mana_regen_bonus)
	energy_changed.emit(old_energy, current_energy, max_energy)

	# 重置灵力加成
	mana_regen_bonus = 0

	# 重置本回合消耗追踪
	turn_spent_mana = 0
	# 重置回合内追踪
	same_element_streak = 0
	cards_played_this_turn = 0
	last_played_element = WuXing.Element.METAL

	# 蓄势爆发准备
	if charge_stacks > 0:
		charge_ready = true

	# 魔念临界检测：≥阈值→心魔低语（每场战斗仅触发1次）
	if mo_nian >= MO_NIAN_CRITICAL_THRESHOLD and not mo_nian_whisper_active and not whisper_triggered_this_battle:
		mo_nian_whisper_active = true
		whisper_triggered_this_battle = true
		mo_nian_whisper_triggered.emit()
		print("Player: 心魔低语触发！魔念=%d" % mo_nian)

	# 末法天劫（化神期 - 暂未实现）
	# TODO: 化神期被动 - 每回合灵力回复减半

	super.start_turn()
	draw_cards()

	print("Player: 回合开始，灵力 %d，手牌 %d 张" % [current_energy, hand.size()])

## 结束回合（保留未打出的手牌）
func end_turn() -> void:
	# 浊念效果：侵蚀≥50时每回合-1最大生命
	if erosion >= EROSION_THRESHOLD_MURKY:
		max_hp = maxi(1, max_hp - 1)
		if current_hp > max_hp:
			current_hp = max_hp
		print("Player: 浊念侵蚀，最大生命降至 %d" % max_hp)

	# 过载B：回合结束时灵力>8 → 超出×0.5 魔念
	if current_energy > 8:
		var overflow := current_energy - 8
		var mo_nian_gain := int(overflow * 0.5)
		if mo_nian_gain > 0:
			_add_mo_nian(mo_nian_gain, "过载B(灵力%d)" % current_energy)

	# 枯竭检测：连续 2 回合灵力为 0
	if zero_mana_streak >= 2:
		exhausted = true
		print("Player: 进入枯竭状态")

	# 清除蓄势减伤
	charge_shield = 0.0
	charge_ready = false

	# 不弃牌——未打出的手牌保留到下一回合
	super.end_turn()
	print("Player: 回合结束，保留 %d 张手牌" % hand.size())

# ==================== 牌堆查询 ====================

## 获取抽牌堆数量
func get_draw_pile_count() -> int:
	return draw_pile.size()

## 获取弃牌堆数量
func get_discard_pile_count() -> int:
	return discard_pile.size()

## 获取手牌数量
func get_hand_count() -> int:
	return hand.size()

## 获取手牌列表
func get_hand() -> Array:
	return hand.duplicate()

## 获取状态摘要
func get_status_summary() -> String:
	return "%s HP:%d/%d 盾:%d 能量:%d/%d 手牌:%d 魔念:%d [%s]" % [
		actor_name, current_hp, max_hp, shield,
		current_energy, max_energy,
		hand.size(), mo_nian,
		get_element_name()
	]

# ==================== 蓄势系统 ====================

var mana_regen_bonus: int = 0  # 下回合灵力回复加成（蓄势+2）


## 蓄势：结束回合，获得减伤+下回合灵力加成
func enter_charge_mode() -> void:
	charge_stacks += 1
	charge_shield = 0.5  # 50% 减伤
	mana_regen_bonus += 2  # 下回合回复+2
	# 连续蓄势×2：额外回复5HP
	if charge_stacks >= 2:
		heal(5)
		print("Player: 连续蓄势×2，回复 5 HP")
	print("Player: 蓄势 %d 层，减伤 50%%，下回合灵力+2" % charge_stacks)
	force_end_turn()

var pending_charge_bonuses: Array = []  # 蓄势爆发产生的合成相生增益

## 蓄势爆发：消耗所有蓄势标记，每层额外触发一次合成相生检测
func apply_charge_burst(card: CardDataResource) -> void:
	if charge_stacks > 0 and charge_ready:
		# 每层蓄势：生成一个合成相生增益（基于当前卡牌元素）
		var synth_bonuses: Array = []
		for i in range(charge_stacks):
			var synth: Dictionary = WuXing.get_generation_bonus(card.element)
			if not synth.is_empty():
				synth_bonuses.append(synth)
		# 交给 battle_manager 结算（通过信号或直接调用）
		# 这里先存起来，由 battle_manager 的 _process_card_effect 处理
		pending_charge_bonuses = synth_bonuses
		print("Player: 蓄势爆发！%d 层合成相生待结算" % charge_stacks)
		charge_stacks = 0
		charge_ready = false

## 获取并清除蓄势爆发增益
func consume_charge_bonuses() -> Array:
	var result := pending_charge_bonuses.duplicate()
	pending_charge_bonuses.clear()
	return result

## 强制结束回合
func force_end_turn() -> void:
	discard_hand()
	super.end_turn()
	print("Player: 强制结束回合")

# ==================== 内部方法 ====================

## 弃牌堆洗入抽牌堆
func _reshuffle_discard() -> void:
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	_shuffle_draw_pile()
	print("Player: 弃牌堆洗入抽牌堆")
