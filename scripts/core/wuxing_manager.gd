## 五行系统 — 核心数据结构
## 负责：五行枚举、相生相克查询、伤害乘算
## 作为 Autoload 单例使用，全局访问 WuXing.xxx

class_name WuXingManager
extends Node

# ==================== 五行枚举 ====================

enum Element {
	METAL,   # 金 (3)
	WOOD,    # 木 (0)
	WATER,   # 水 (4)
	FIRE,    # 火 (1)
	EARTH    # 土 (2)
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

# ==================== 相生相克表 ====================

# 相生表：GENERATE[from] = to
# 木→火→土→金→水→木
const GENERATE := [
	Element.FIRE,   # 木 生 火
	Element.EARTH,  # 火 生 土
	Element.METAL,  # 土 生 金
	Element.WATER,  # 金 生 水
	Element.WOOD,   # 水 生 木
]

# 相克表：COUNTER[attacker] = 被克制的元素
# 木克土、土克水、水克火、火克金、金克木
const COUNTER := [
	Element.EARTH,  # 木 克 土
	Element.WATER,  # 火 克 ... (注：火克金)
	Element.FIRE,   # 土 克 水
	Element.METAL,  # 金 克 木
	Element.WOOD,   # 水 克 火
]
# 修正相克表：按五行传统
# 金克木、木克土、土克水、水克火、火克金
const COUNTER_FIXED := [
	Element.WOOD,   # 金 克 木
	Element.EARTH,  # 木 克 土
	Element.WATER,  # 土 克 水
	Element.FIRE,   # 水 克 火
	Element.METAL,  # 火 克 金
]

# ==================== 伤害倍率 ====================

const GENERATION_BONUS := 1.5      # 相生加成 +50%
const COUNTER_MULTIPLIER := 2.0    # 克制伤害 ×2
const COUNTERED_MULTIPLIER := 0.5  # 被克伤害 ×0.5

# ==================== 查询方法 ====================

## 获取元素中文名
func get_element_name(element: Element) -> String:
	return ELEMENT_NAMES.get(element, "未知")

## 获取元素颜色
func get_element_color(element: Element) -> Color:
	return ELEMENT_COLORS.get(element, Color.WHITE)

## 判断是否相生：from 生 to？
## 返回 true 表示 from→to 是相生关系
func is_generation(from_element: Element, to_element: Element) -> bool:
	return GENERATE[from_element] == to_element

## 获取相生的下一个元素
func get_generation_target(from_element: Element) -> Element:
	return GENERATE[from_element]

## 判断是否相克：attacker 克 defender？
func is_counter(attacker: Element, defender: Element) -> bool:
	return COUNTER_FIXED[attacker] == defender

## 判断是否被克：attacker 被 defender 克？
func is_countered_by(attacker: Element, defender: Element) -> bool:
	return COUNTER_FIXED[defender] == attacker

## 计算五行伤害倍率
## 考虑：相生加成 + 相克关系
func calculate_damage_multiplier(
	attack_element: Element,
	defender_element: Element,
	is_generation_chain: bool = false
) -> float:
	var multiplier := 1.0

	# 相生链加成
	if is_generation_chain:
		multiplier *= GENERATION_BONUS

	# 相克判定
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
