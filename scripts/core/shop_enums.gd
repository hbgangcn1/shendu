## 商店系统枚举和常量

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

enum ShopItemType { CARD, PILL, ENGRAVE }
enum CardSubType { ATTACK, DEFEND, UTILITY, SPECIAL }
enum PillSubType { HP_RESTORE, MANA_RESTORE, REMOVE_CARD, DRAW_BONUS }
enum EngraveSubType { DAMAGE_UP, BLOCK_UP, COST_DOWN, ELEMENT_BONUS }

# ==================== 稀有度价格倍率 ====================

const RARITY_PRICE_MULTIPLIER := {
	"common": 1.0,
	"rare": 1.3,
	"epic": 1.6,
	"legend": 2.0,
}

# 基础价格（按类型）
const TYPE_BASE_PRICE := {
	ShopItemType.CARD: 12,
	ShopItemType.PILL: 8,
	ShopItemType.ENGRAVE: 20,
}

# 境界价格系数
const REALM_PRICE系数 := [1.0, 1.3, 1.6]  # 炼气/筑基/金丹

# ==================== 丹药效果定义 ====================

const PILL_EFFECTS := {
	PillSubType.HP_RESTORE: {"name": "回春丹", "value": 15, "description": "回复15点生命"},
	PillSubType.MANA_RESTORE: {"name": "聚灵丹", "value": 5, "description": "回复5点灵力"},
	PillSubType.REMOVE_CARD: {"name": "净化符", "value": 1, "description": "删除1张卡牌"},
	PillSubType.DRAW_BONUS: {"name": "慧眼丹", "value": 2, "description": "下场战斗额外抽2张牌"},
}

# ==================== 稀有度分布（按境界） ====================

const RARITY_DISTRIBUTION := {
	0: {"common": 70, "rare": 25, "epic": 4, "legend": 1},  # 炼气
	1: {"common": 55, "rare": 30, "epic": 12, "legend": 3},  # 筑基
	2: {"common": 40, "rare": 35, "epic": 20, "legend": 5},  # 金丹
}
