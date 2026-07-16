# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

extends Node

# ==================== 五行枚举 ====================

enum Element {
	METAL,   # 金 (0)
	WOOD,    # 木 (1)
	WATER,   # 水 (2)
	FIRE,    # 火 (3)
	EARTH    # 土 (4)
}

# 元素中文名
const ELEMENT_NAMES := {
	Element.METAL: "金",
	Element.WOOD: "木",
	Element.WATER: "水",
	Element.FIRE: "火",
	Element.EARTH: "土",
}

# 元素颜色（用于 UI）
const ELEMENT_COLORS := {
	Element.METAL: Color(0.75, 0.75, 0.75),   # 银白
	Element.WOOD:  Color(0.2, 0.8, 0.3),      # 翠绿
	Element.WATER: Color(0.2, 0.4, 0.9),      # 深蓝
	Element.FIRE:  Color(0.9, 0.2, 0.1),      # 赤红
	Element.EARTH: Color(0.85, 0.65, 0.2),    # 琥珀
}

# 元素图标路径（无文字版，遵循 NO_TEXT_DESIGN_PRINCIPLE.md）
const ELEMENT_ICONS := {
	Element.METAL: "res://assets/images/ui/ui_icon_metal_001.png",
	Element.WOOD:  "res://assets/images/ui/ui_icon_wood_001.png",
	Element.WATER: "res://assets/images/ui/ui_icon_water_001.png",
	Element.FIRE:  "res://assets/images/ui/ui_icon_fire_001.png",
	Element.EARTH: "res://assets/images/ui/ui_icon_earth_001.png",
}

# 元素英文名（用于图标文件名与调试）
const ELEMENT_ENGLISH_NAMES := {
	Element.METAL: "metal",
	Element.WOOD:  "wood",
	Element.WATER: "water",
	Element.FIRE:  "fire",
	Element.EARTH: "earth",
}

# ==================== 相生相克表 ====================

# 相生表：GENERATE[from] = to
# 金→水→木→火→土→金
const GENERATE := [
	Element.WATER,  # 金 生 水
	Element.FIRE,   # 木 生 火
	Element.WOOD,   # 水 生 木
	Element.EARTH,  # 火 生 土
	Element.METAL,  # 土 生 金
]

# 相克表：COUNTER[attacker] = 被克制的元素
# 金克木、木克土、土克水、水克火、火克金
const COUNTER := [
	Element.WOOD,   # 金 克 木
	Element.EARTH,  # 木 克 土
	Element.FIRE,   # 土 克 水
	Element.METAL,  # 水 克 火
	Element.WATER,  # 火 克 金
]

# ==================== 伤害倍率 ====================

const GENERATION_BONUS := 1.5      # 相生加成 +50%
const COUNTER_MULTIPLIER := 2.0    # 克制伤害 ×2
const COUNTERED_MULTIPLIER := 0.5  # 被克伤害 ×0.5

## 相生链奖励类型
enum GenerationBonusType {
	DAMAGE_PERCENT,  # 伤害加成百分比
	FLAT_BLOCK,      # 固定格挡
	DRAW_CARDS,      # 抽牌
	HEAL,            # 回复生命
	COST_REDUCE,     # 减费
}

# ==================== 查询方法 ====================

## 获取元素中文名
func get_element_name(element: Element) -> String:
	return ELEMENT_NAMES.get(element, "未知")

## 获取元素颜色
func get_element_color(element: Element) -> Color:
	return ELEMENT_COLORS.get(element, Color.WHITE)

## 判断是否相生：from 生 to？
func is_generation(from_element: Element, to_element: Element) -> bool:
	return GENERATE[from_element] == to_element

## 获取相生的下一个元素
func get_generation_target(from_element: Element) -> Element:
	return GENERATE[from_element]

## 判断是否相克：attacker 克 defender？
func is_counter(attacker: Element, defender: Element) -> bool:
	return COUNTER[attacker] == defender

## 判断是否被克：attacker 被 defender 克？
func is_countered_by(attacker: Element, defender: Element) -> bool:
	return COUNTER[defender] == attacker

## 获取相生加成信息（用于蓄势爆发 + 相生链奖励）
## 根据「被生者」元素决定奖励类型
func get_generation_bonus(element: Element) -> Dictionary:
	var target: Element = GENERATE[element]
	var bonus_type: GenerationBonusType
	var value: int
	
	# 木生火→伤害加成 | 火生土→格挡 | 土生金→抽牌 | 金生水→回复 | 水生木→减费
	match target:
		Element.FIRE:
			bonus_type = GenerationBonusType.DAMAGE_PERCENT
			value = 50
		Element.EARTH:
			bonus_type = GenerationBonusType.FLAT_BLOCK
			value = 8
		Element.METAL:
			bonus_type = GenerationBonusType.DRAW_CARDS
			value = 1
		Element.WATER:
			bonus_type = GenerationBonusType.HEAL
			value = 6
		Element.WOOD:
			bonus_type = GenerationBonusType.COST_REDUCE
			value = 1
		_:
			bonus_type = GenerationBonusType.DAMAGE_PERCENT
			value = 30
	
	return {
		"from": element,
		"to": target,
		"bonus": GENERATION_BONUS,
		"name": "%s生%s" % [ELEMENT_NAMES[element], ELEMENT_NAMES[target]],
		"description": "%s生%s" % [ELEMENT_NAMES[element], ELEMENT_NAMES[target]],
		"type": bonus_type,
		"value": value,
	}

## 计算五行伤害倍率
func calculate_damage_multiplier(
	attack_element: Element,
	defender_element: Element,
	is_generation_chain: bool = false,
	charge_stacks: int = 0
) -> float:
	var multiplier := 1.0

	if is_generation_chain:
		multiplier *= GENERATION_BONUS

	# 蓄势加成：每层 +25%，上限 1.75（按 spec 07-combat-system-spec.md:174）
	if charge_stacks > 0:
		multiplier *= min(1.0 + charge_stacks * 0.25, 1.75)

	if is_counter(attack_element, defender_element):
		multiplier *= COUNTER_MULTIPLIER
	elif is_countered_by(attack_element, defender_element):
		multiplier *= COUNTERED_MULTIPLIER

	return multiplier

## 计算最终伤害
func calculate_final_damage(
	base_damage: int,
	attack_element: Element,
	defender_element: Element,
	is_generation_chain: bool = false
) -> int:
	var multiplier := calculate_damage_multiplier(
		attack_element, defender_element, is_generation_chain
	)
	return int(round(base_damage * multiplier))
