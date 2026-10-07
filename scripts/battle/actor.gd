## 战斗单位基类
## 所有战斗参与者（玩家、敌人）的父类
## 管理 HP、护盾、状态等通用属性
## 注意：继承 Node 以支持信号系统，但主要作为数据容器使用

# implements: design/07-combat-system-spec.md
# implements_philosophy: rule_1_core_loop_first, rule_3_three_layer_loops, rule_6_flow_channel
# avoids_red_line: red_6_ui_overload, red_7_difficulty_wall

class_name Actor
extends Node

# ==================== 信号 ====================

signal hp_changed(old_hp: int, new_hp: int, max_hp: int)
signal shield_changed(old_shield: int, new_shield: int)
signal died
signal turn_started
signal turn_ended

# ==================== 基础属性 ====================

var actor_name: String = ""
var max_hp: int = 100
var current_hp: int = 100
var shield: int = 0

# ==================== 元素属性 ====================

var element: WuXing.Element = WuXing.Element.FIRE

# ==================== 状态标记 ====================

var is_alive: bool = true
var is_defending: bool = false  # 是否处于防御姿态

# ==================== 初始化 ====================

func _init(p_name: String = "", p_hp: int = 100, p_elem: WuXing.Element = WuXing.Element.FIRE) -> void:
	actor_name = p_name
	max_hp = p_hp
	current_hp = p_hp
	element = p_elem

# ==================== HP 管理 ====================

## 受到伤害（经过护盾和五行计算）
func take_damage(base_damage: int, attack_element: WuXing.Element, is_generation_chain: bool = false, charge_stacks: int = 0) -> int:
	if not is_alive:
		return 0

	# 计算五行伤害倍率（含蓄势乘数 C）
	var multiplier := WuXing.calculate_damage_multiplier(
		attack_element, element, is_generation_chain, charge_stacks
	)

	# 应用防御姿态减伤
	if is_defending:
		multiplier *= 0.5

	var final_damage := int(round(base_damage * multiplier))

	# 先扣护盾
	var damage_to_hp := final_damage
	if shield > 0:
		if shield >= final_damage:
			shield -= final_damage
			damage_to_hp = 0
			shield_changed.emit(shield + final_damage, shield)
		else:
			damage_to_hp = final_damage - shield
			shield_changed.emit(shield, 0)
			shield = 0

	# 再扣 HP
	if damage_to_hp > 0:
		var old_hp := current_hp
		current_hp = max(0, current_hp - damage_to_hp)
		hp_changed.emit(old_hp, current_hp, max_hp)

		# 检查死亡
		if current_hp <= 0:
			_die()

	return final_damage

## 回复 HP
func heal(amount: int) -> int:
	if not is_alive:
		return 0

	var old_hp := current_hp
	current_hp = min(max_hp, current_hp + amount)
	var actual_heal := current_hp - old_hp

	if actual_heal > 0:
		hp_changed.emit(old_hp, current_hp, max_hp)

	return actual_heal

## 获得护盾
func gain_shield(amount: int) -> void:
	var old_shield := shield
	shield += amount
	shield_changed.emit(old_shield, shield)

## 清除护盾
func clear_shield() -> void:
	if shield > 0:
		shield = 0
		shield_changed.emit(0, 0)

# ==================== 回合管理 ====================

## 开始回合
func start_turn() -> void:
	if not is_alive:
		return
	is_defending = false  # 重置防御姿态
	turn_started.emit()

## 结束回合
func end_turn() -> void:
	if not is_alive:
		return
	turn_ended.emit()

# ==================== 状态查询 ====================

## 获取 HP 百分比
func get_hp_percent() -> float:
	if max_hp <= 0:
		return 0.0
	return float(current_hp) / float(max_hp)

## 获取元素中文名
func get_element_name() -> String:
	return WuXing.get_element_name(element)

## 获取状态摘要
func get_status_summary() -> String:
	return "%s HP:%d/%d 盾:%d [%s]" % [
		actor_name, current_hp, max_hp, shield, get_element_name()
	]

# ==================== 内部方法 ====================

func _die() -> void:
	is_alive = false
	died.emit()
