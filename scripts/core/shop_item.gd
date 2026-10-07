## 商店商品实例

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name ShopItem
extends RefCounted

const ShopEnums = preload("res://scripts/core/shop_enums.gd")

var id: int
var type  # ShopEnums.ShopItemType
var card_data: Dictionary
var pill_data: Dictionary
var engrave_data: Dictionary
var base_price: int
var final_price: int
var rarity: String
var sold_out: bool = false
var is_discount: bool = false

func get_name() -> String:
	match type:
		ShopEnums.ShopItemType.CARD:
			return card_data.get("name", "未知卡牌")
		ShopEnums.ShopItemType.PILL:
			return pill_data.get("name", "未知丹药")
		ShopEnums.ShopItemType.ENGRAVE:
			return engrave_data.get("name", "未知刻印")
	return "未知"

func get_description() -> String:
	match type:
		ShopEnums.ShopItemType.CARD:
			return card_data.get("description", "")
		ShopEnums.ShopItemType.PILL:
			return pill_data.get("description", "")
		ShopEnums.ShopItemType.ENGRAVE:
			return engrave_data.get("description", "")
	return ""

func get_display_price() -> int:
	if is_discount:
		return final_price / 2
	return final_price
