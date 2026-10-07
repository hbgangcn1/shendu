## 商店库存

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name ShopInventory
extends RefCounted

const ShopEnums = preload("res://scripts/core/shop_enums.gd")

var items: Array = []                ## ShopItem[]
var max_slots: int = 6
var refresh_cost: int = 5
var refresh_count: int = 0

func get_available_items() -> Array:
	var result: Array = []
	for item in items:
		if not item.sold_out:
			result.append(item)
	return result

func mark_sold(item_id: int) -> void:
	for item in items:
		if item.id == item_id:
			item.sold_out = true
			return

func get_refresh_cost() -> int:
	return refresh_cost + refresh_count * 3

func do_refresh() -> void:
	refresh_count += 1

static func calculate_base_price(item_type, rarity: String) -> int:
	var base: int = ShopEnums.TYPE_BASE_PRICE.get(item_type, 10)
	var mult: float = ShopEnums.RARITY_PRICE_MULTIPLIER.get(rarity, 1.0)
	return int(base * mult)

static func apply_realm_coefficient(price: int, realm: int) -> int:
	var coeff: float = ShopEnums.REALM_PRICE系数[clampi(realm, 0, 2)]
	return int(price * coeff)

static func apply_fluctuation(price: int, fluctuation_percent: int = 15) -> int:
	var delta: int = price * fluctuation_percent / 100
	return price + randi_range(-delta, delta)
