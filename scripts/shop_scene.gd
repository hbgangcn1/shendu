## 商店场景（占位实现）
## 显示商店物品列表，支持购买

# implements: design/10-shop-system-spec.md
# implements_philosophy: rule_8_cosmetics_over_p2w
# avoids_red_line: red_1_p2w

extends Control

@onready var title_label: Label = %TitleLabel
@onready var stones_label: Label = %StonesLabel
@onready var items_container: VBoxContainer = %ItemsContainer
@onready var leave_button: Button = %LeaveButton

var _shop_items: Array = []  # Dictionary[]
var _in_removal_mode: bool = false

func _ready() -> void:
	title_label.text = "商店"
	stones_label.text = "灵石: %d" % GameState.spirit_stones

	# 应用墨韵赛博主题
	_apply_theme()

	# 生成商店物品
	_generate_items()
	_render_items()

	leave_button.pressed.connect(_on_leave)
	print("商店：加载完成，灵石=%d" % GameState.spirit_stones)

func _apply_theme() -> void:
	UITheme.apply_title_label(title_label, 36)
	UITheme.apply_body_label(stones_label, 20)
	UITheme.apply_button(leave_button)

func _generate_items() -> void:
	# 基于境界生成 3-5 件物品
	var count := randi_range(3, 5)
	var mvp_cards := CardPool.get_mvp_pool()

	for i in range(count):
		var roll := randf()
		if roll < 0.4:
			# 卡牌
			var card = mvp_cards[randi() % mvp_cards.size()]
			_shop_items.append({
				"name": card.name,
				"price": randi_range(8, 20),
				"description": "[%s] %s" % [WuXing.get_element_name(card.element), card.description],
				"effect_type": "card",
				"card_data": card,
			})
		elif roll < 0.7:
			# 回复药
			var heal_amount := randi_range(10, 25)
			_shop_items.append({
				"name": "回复药",
				"price": randi_range(5, 12),
				"description": "回复 %d HP" % heal_amount,
				"effect_type": "heal",
				"effect_value": heal_amount,
			})
		elif roll < 0.85:
			# 最大HP提升
			var hp_boost := randi_range(3, 8)
			_shop_items.append({
				"name": "境界丹",
				"price": randi_range(15, 30),
				"description": "最大HP +%d" % hp_boost,
				"effect_type": "max_hp",
				"effect_value": hp_boost,
			})
		else:
			# 洗髓（删卡）
			var removal_cost := GameState.get_removal_cost()
			_shop_items.append({
				"name": "洗髓",
				"price": removal_cost,
				"description": "从牌库中移除一张卡牌（费用递增）",
				"effect_type": "remove_card",
			})

func _render_items() -> void:
	for child in items_container.get_children():
		child.queue_free()

	if _shop_items.is_empty():
		var label := Label.new()
		label.text = "🏪 商店暂无物品\n下次再来逛逛吧"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
		items_container.add_child(label)
		return

	for i in range(_shop_items.size()):
		var item: Dictionary = _shop_items[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(560, 90)

		var item_name: String = item.get("name", "未知物品")
		var price: int = item.get("price", 0)
		var desc: String = item.get("description", "")
		var can_afford: bool = GameState.spirit_stones >= price

		var card_data_ref = item.get("card_data", null)
		var elem_name := ""
		if card_data_ref:
			elem_name = "[%s] " % WuXing.get_element_name(card_data_ref.element)

		# 加商品图标（左侧 TextureRect 60×60）
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(60, 60)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.position = Vector2(8, 15)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if card_data_ref:
			# 优先用 card art_path
			if card_data_ref.art_path != "" and ResourceLoader.exists(card_data_ref.art_path):
				icon.texture = load(card_data_ref.art_path)
			else:
				# fallback 元素背景
				var elem_names := ["metal", "wood", "water", "fire", "earth"]
				var elem_idx: int = clampi(int(card_data_ref.element), 0, 4)
				var fallback := "res://assets/images/card_bgs/element_%s.png" % elem_names[elem_idx]
				if ResourceLoader.exists(fallback):
					icon.texture = load(fallback)
		else:
			# 消耗品图标：使用 shop_icons_sheet 或元素默认
			var elem_idx_2 := i % 5
			var elem_names_2 := ["metal", "wood", "water", "fire", "earth"]
			var fallback2 := "res://assets/images/card_bgs/element_%s.png" % elem_names_2[elem_idx_2]
			if ResourceLoader.exists(fallback2):
				icon.texture = load(fallback2)
		btn.add_child(icon)

		btn.text = "%s — %d 灵石\n%s%s" % [item_name, price, elem_name, desc]
		UITheme.apply_button(btn)
		btn.add_theme_font_size_override("font_size", 18)
		btn.disabled = not can_afford

		if not can_afford:
			btn.modulate = Color(0.5, 0.5, 0.5)

		btn.pressed.connect(_on_buy_item.bind(i))
		items_container.add_child(btn)

func _on_buy_item(index: int) -> void:
	if index >= _shop_items.size():
		return

	var item: Dictionary = _shop_items[index]
	var price: int = item.get("price", 0)

	if GameState.spirit_stones < price:
		print("商店：灵石不足")
		return

	GameState.spirit_stones -= price
	stones_label.text = "灵石: %d" % GameState.spirit_stones

	# 应用物品效果
	var effect_type: String = item.get("effect_type", "")
	var effect_value: int = item.get("effect_value", 0)
	match effect_type:
		"heal":
			GameState.hp = mini(GameState.max_hp, GameState.hp + effect_value)
			print("商店：回复 %d HP → %d/%d" % [effect_value, GameState.hp, GameState.max_hp])
		"max_hp":
			GameState.max_hp += effect_value
			GameState.hp += effect_value
			print("商店：最大HP +%d → %d/%d" % [effect_value, GameState.hp, GameState.max_hp])
		"card":
			var card_data = item.get("card_data", null)
			if card_data:
				# 将 CardDataResource 转为 Dictionary
				var card_dict: Dictionary = {
					"id": card_data.id,
					"card_name": card_data.name,
					"description": card_data.description,
					"cost": card_data.cost,
					"element": card_data.element,
					"card_kind": card_data.card_kind,
					"rarity": card_data.rarity,
					"damage": card_data.damage,
					"block": card_data.block,
					"heal": card_data.heal,
					"draw_cards": card_data.draw_cards,
					"effects": card_data.effects,
				}
				var idx: int = GameState.add_to_collection(card_dict)
				GameState.add_to_deck(idx)
				print("商店：获得卡牌「%s」加入卡牌池和牌库" % item.get("name", "?"))
		"remove_card":
			# 进入删卡选择模式
			_enter_removal_mode(index)
			return  # 不立即移除物品，等删卡完成后处理
		_:
			print("商店：未知效果类型 %s" % effect_type)

	# 移除已购物品
	_shop_items.remove_at(index)
	_render_items()

func _on_leave() -> void:
	if _in_removal_mode:
		_exit_removal_mode()
		return
	get_tree().change_scene_to_file("res://scenes/map.tscn")

# ==================== 删卡功能 ====================

func _enter_removal_mode(item_index: int) -> void:
	_in_removal_mode = true
	set_meta("removal_item_index", item_index)

	for child in items_container.get_children():
		child.queue_free()

	# 标题
	var header := Label.new()
	header.text = "选择要移除的卡牌（费用: %d 灵石）" % GameState.get_removal_cost()
	UITheme.apply_body_label(header, 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items_container.add_child(header)

	if GameState.deck.is_empty():
		var empty_label := Label.new()
		empty_label.text = "牌库为空"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items_container.add_child(empty_label)
		# 加返回按钮
		var empty_back := Button.new()
		empty_back.text = "返回商店"
		empty_back.custom_minimum_size = Vector2(533, 53)
		UITheme.apply_button(empty_back)
		empty_back.pressed.connect(_exit_removal_mode)
		items_container.add_child(empty_back)
		return

	# ScrollContainer 装卡牌按钮（超长可滚动）
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 上限 80vh，超出滚动
	scroll.custom_minimum_size = Vector2(560, min(560, int(560 * GameState.deck.size() / 8.0)))
	items_container.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(list_vbox)

	for i in range(GameState.deck.size()):
		var ci: int = GameState.deck[i]
		var card: Dictionary = GameState.get_collection_card(ci)
		var card_name: String = card.get("name", card.get("card_name", "?"))
		var card_desc: String = card.get("description", "")
		var card_cost: int = card.get("cost", 0)
		var card_element: int = card.get("element", 0)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(520, 60)
		var elem_name_str := WuXing.get_element_name(card_element)
		btn.text = "%s [%s] 费用 %d\n%s" % [card_name, elem_name_str, card_cost, card_desc]
		UITheme.apply_button(btn)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_select_card_to_remove.bind(i))
		list_vbox.add_child(btn)

	# 固定底部返回按钮（不会被滚动）
	var back_btn := Button.new()
	back_btn.text = "← 返回商店"
	back_btn.custom_minimum_size = Vector2(533, 53)
	UITheme.apply_button(back_btn)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_exit_removal_mode)
	items_container.add_child(back_btn)

	print("商店：进入删卡模式，牌库 %d 张" % GameState.deck.size())

func _on_select_card_to_remove(deck_index: int) -> void:
	var cost := GameState.get_removal_cost()
	if GameState.spirit_stones < cost:
		print("商店：灵石不足，需要 %d" % cost)
		return
	
	GameState.spirit_stones -= cost
	GameState.remove_from_deck(deck_index)
	stones_label.text = "灵石: %d" % GameState.spirit_stones
	
	print("商店：移除卡牌成功，花费 %d 灵石" % cost)
	
	var item_index: int = get_meta("removal_item_index", -1)
	if item_index >= 0 and item_index < _shop_items.size():
		_shop_items.remove_at(item_index)
	_exit_removal_mode()

func _exit_removal_mode() -> void:
	_in_removal_mode = false
	_render_items()
