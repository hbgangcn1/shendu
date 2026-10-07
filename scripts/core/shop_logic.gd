## 商店购买逻辑
## 处理购买流程、卡组管理、删除卡牌

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name ShopLogic
extends Node

const ShopEnums = preload("res://scripts/core/shop_enums.gd")

signal purchase_completed(item: ShopItem)
signal purchase_failed(reason: String)
signal card_removed(card_index: int)
signal shop_refreshed(inventory: ShopInventory)

func can_purchase(item: ShopItem, spirit_stones: int, deck_size: int, max_deck_size: int = 30) -> Dictionary:
	var result := {"can_buy": true, "reason": ""}
	if item.sold_out:
		result.can_buy = false
		result.reason = "已售出"
	elif spirit_stones < item.get_display_price():
		result.can_buy = false
		result.reason = "灵石不足（需要%d，当前%d）" % [item.get_display_price(), spirit_stones]
	elif item.type == ShopEnums.ShopItemType.CARD and deck_size >= max_deck_size:
		result.can_buy = false
		result.reason = "卡组已满（%d/%d）" % [deck_size, max_deck_size]
	return result

func execute_purchase(item: ShopItem, player_state: Dictionary) -> bool:
	var check := can_purchase(item, player_state.get("spirit_stones", 0), player_state.get("deck_size", 0))
	if not check.can_buy:
		purchase_failed.emit(check.reason)
		return false
	var price := item.get_display_price()
	player_state["spirit_stones"] = player_state.get("spirit_stones", 0) - price
	match item.type:
		ShopEnums.ShopItemType.CARD:
			_add_card_to_deck(item.card_data, player_state)
		ShopEnums.ShopItemType.PILL:
			_apply_pill_effect(item.pill_data, player_state)
		ShopEnums.ShopItemType.ENGRAVE:
			_apply_engrave_effect(item.engrave_data, player_state)
	item.sold_out = true
	purchase_completed.emit(item)
	return true

func _add_card_to_deck(card_data: Dictionary, player_state: Dictionary) -> void:
	var deck: Array = player_state.get("deck", [])
	deck.append(card_data)
	player_state["deck"] = deck
	player_state["deck_size"] = deck.size()
	print("Shop: 卡牌「%s」加入卡组" % card_data.get("name", "?"))

func _apply_pill_effect(pill_data: Dictionary, player_state: Dictionary) -> void:
	var sub_type: int = pill_data.get("sub_type", 0)
	var value: int = pill_data.get("effect_value", 0)
	match sub_type:
		0:
			var old_hp: int = player_state.get("hp", 80)
			var max_hp: int = player_state.get("max_hp", 80)
			player_state["hp"] = mini(max_hp, old_hp + value)
			print("Shop: 回复 %d HP → %d" % [value, player_state["hp"]])
		1:
			var old_mana: int = player_state.get("current_mana", 10)
			var max_mana: int = player_state.get("max_mana", 10)
			player_state["current_mana"] = mini(max_mana, old_mana + value)
			print("Shop: 回复 %d 灵力 → %d" % [value, player_state["current_mana"]])
		2:
			player_state["pending_card_removal"] = value
			print("Shop: 获得 %d 次删除卡牌机会" % value)
		3:
			player_state["next_battle_draw_bonus"] = player_state.get("next_battle_draw_bonus", 0) + value
			print("Shop: 下场战斗额外抽 %d 张牌" % value)

func _apply_engrave_effect(engrave_data: Dictionary, player_state: Dictionary) -> void:
	var sub_type: int = engrave_data.get("sub_type", 0)
	var bonus: float = engrave_data.get("bonus_value", 0.0)
	var element: String = engrave_data.get("target_element", "all")
	var engravings: Array = player_state.get("engravings", [])
	engravings.append({
		"sub_type": sub_type,
		"bonus_value": bonus,
		"target_element": element,
		"name": engrave_data.get("name", "刻印"),
	})
	player_state["engravings"] = engravings
	print("Shop: 获得刻印「%s」" % engrave_data.get("name", "?"))

func remove_card(card_index: int, player_state: Dictionary) -> bool:
	var deck: Array = player_state.get("deck", [])
	if card_index < 0 or card_index >= deck.size():
		return false
	var removed: Array = player_state.get("removed_cards", [])
	removed.append(deck[card_index])
	player_state["removed_cards"] = removed
	deck.remove_at(card_index)
	player_state["deck"] = deck
	player_state["deck_size"] = deck.size()
	var removals: int = player_state.get("pending_card_removal", 0)
	if removals > 0:
		player_state["pending_card_removal"] = removals - 1
	card_removed.emit(card_index)
	print("Shop: 删除卡牌[%d]，卡组剩余 %d 张" % [card_index, deck.size()])
	return true
