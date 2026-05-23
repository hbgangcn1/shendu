## 卡牌数据资源类
## 定义单张卡牌的所有属性

class_name CardData
extends Resource

# ==================== 基础属性 ====================

@export var id: String = ""             # 唯一标识
@export var card_name: String = ""      # 中文名
@export var description: String = ""    # 描述文本
@export var cost: int = 0               # 灵力消耗
@export var element: int = 0            # 五行属性（WuXing.Element 枚举值）
@export var card_type: int = 0          # 卡牌类型（见下方枚举）
@export var rarity: int = 0             # 稀有度（见下方枚举）

# ==================== 效果数值 ====================

@export var damage: int = 0             # 伤害值
@export var block: int = 0              # 格挡值
@export var draw_cards: int = 0         # 抽牌数
@export var heal: int = 0               # 回复生命

# ==================== 卡牌类型枚举 ====================

enum CardType {
	ATTACK,    # 攻击牌 ⚔
	DEFENSE,   # 防御牌 🛡
	SPECIAL,   # 特殊牌 ◆
	SUPPORT,   # 辅助牌 ✦
}

# ==================== 稀有度枚举 ====================

enum Rarity {
	COMMON,    # 普通（灰白）
	RARE,      # 稀有（蓝）
	EPIC,      # 史诗（紫）
	LEGENDARY, # 传说（金橙）
}

# ==================== 辅助方法 ====================

## 获取类型中文名
func get_type_name() -> String:
	match card_type:
		CardType.ATTACK: return "攻击"
		CardType.DEFENSE: return "防御"
		CardType.SPECIAL: return "特殊"
		CardType.SUPPORT: return "辅助"
	return "未知"

## 获取稀有度中文名
func get_rarity_name() -> String:
	match rarity:
		Rarity.COMMON: return "普通"
		Rarity.RARE: return "稀有"
		Rarity.EPIC: return "史诗"
		Rarity.LEGENDARY: return "传说"
	return "未知"

## 获取五行元素枚举
func get_element() -> int:
	return element

## 是否是攻击牌
func is_attack() -> bool:
	return card_type == CardType.ATTACK

## 是否是防御牌
func is_defense() -> bool:
	return card_type == CardType.DEFENSE

## 获取卡牌摘要（调试用）
func get_summary() -> String:
	var elem_name: String = WuXing.get_element_name(element)
	return "[%s]%s (%s) 费%d 伤%d 盾%d" % [
		elem_name, card_name, get_type_name(), cost, damage, block
	]
