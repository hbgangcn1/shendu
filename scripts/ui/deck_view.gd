## 牌组管理界面
## 双栏布局：左侧=收集，右侧=当前牌组
## 点击卡牌在两侧之间移动

# implements: design/08-ui-layout-spec.md
# implements_philosophy: rule_9_progressive_disclosure
# avoids_red_line: red_6_ui_overload

extends Control

var _pool_list: VBoxContainer
var _deck_list: VBoxContainer
var _pool_header: Label
var _deck_header: Label
var _status_label: Label

const ELEMENT_COLORS := [
	Color(1.0, 0.84, 0.0), Color(0.3, 0.85, 0.3), Color(0.35, 0.55, 1.0),
	Color(1.0, 0.35, 0.15), Color(0.75, 0.55, 0.25),
]
const ELEMENT_NAMES := ["金", "木", "水", "火", "土"]
const TEXT_COLOR := Color(0.9, 0.9, 0.95)
const TEXT_MUTED := Color(0.55, 0.55, 0.65)
const ACCENT := Color(0.4, 0.7, 1.0)
const PANEL_BG := Color(0.12, 0.12, 0.18)
const ROW_BG := Color(0.16, 0.16, 0.22)
const ROW_HOVER := Color(0.22, 0.22, 0.32)

func _ready() -> void:
	# 背景遮罩
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 主面板
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1200, 800)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.3, 0.3, 0.4)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(main_vbox)

	# === 标题栏 ===
	var title_row := HBoxContainer.new()
	main_vbox.add_child(title_row)

	var title := Label.new()
	title.text = "牌组管理"
	title.add_theme_font_size_override("font_size", 29)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(43, 43)
	close_btn.pressed.connect(_on_close)
	title_row.add_child(close_btn)

	main_vbox.add_child(HSeparator.new())

	# === 状态栏 ===
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_color", TEXT_MUTED)
	main_vbox.add_child(_status_label)

	# === 双栏区域 ===
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	main_vbox.add_child(columns)

	# 左栏：收集
	var left_panel := _create_column_panel("收集", true)
	columns.add_child(left_panel)

	# 右栏：当前牌组
	var right_panel := _create_column_panel("当前牌组", false)
	columns.add_child(right_panel)

	_refresh_all()

func _create_column_panel(title_text: String, is_pool: bool) -> PanelContainer:
	var col_panel := PanelContainer.new()
	col_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col_style := StyleBoxFlat.new()
	col_style.bg_color = Color(0.1, 0.1, 0.15)
	col_style.corner_radius_top_left = 8
	col_style.corner_radius_top_right = 8
	col_style.corner_radius_bottom_left = 8
	col_style.corner_radius_bottom_right = 8
	col_style.content_margin_left = 8
	col_style.content_margin_right = 8
	col_style.content_margin_top = 8
	col_style.content_margin_bottom = 8
	col_panel.add_theme_stylebox_override("panel", col_style)

	var col_vbox := VBoxContainer.new()
	col_vbox.add_theme_constant_override("separation", 4)
	col_panel.add_child(col_vbox)

	# 标题
	var header := HBoxContainer.new()
	col_vbox.add_child(header)

	var header_label := Label.new()
	header_label.text = title_text
	header_label.add_theme_font_size_override("font_size", 21)
	header_label.add_theme_color_override("font_color", ACCENT)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_label)

	if is_pool:
		_pool_header = header_label
	else:
		_deck_header = header_label

	col_vbox.add_child(HSeparator.new())

	# 可滚动列表
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	if is_pool:
		_pool_list = list
	else:
		_deck_list = list

	return col_panel

# ==================== 刷新显示 ====================

func _refresh_all() -> void:
	_refresh_pool()
	_refresh_deck()
	_update_status()

func _refresh_pool() -> void:
	for child in _pool_list.get_children():
		child.queue_free()

	_pool_header.text = "收集（%d）" % GameState.collection.size()

	if GameState.collection.is_empty():
		var empty := Label.new()
		empty.text = "暂无卡牌，完成战斗获取新卡牌"
		empty.add_theme_color_override("font_color", TEXT_MUTED)
		empty.add_theme_color_override("font_color", TEXT_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 53)
		_pool_list.add_child(empty)
		return

	# 收集卡牌池数据并排序：五行顺序→费用→名称
	var pool_entries: Array = []  # [{card, index}]
	var in_deck: Dictionary = {}
	for ci in GameState.deck:
		in_deck[ci] = true

	for i in range(GameState.collection.size()):
		var card: Dictionary = GameState.collection[i]
		# 已在牌库中的卡牌不在卡牌池显示
		if in_deck.has(i):
			continue
		pool_entries.append({"card": card, "index": i})

	# 排序：五行顺序(METAL=0→WOOD=1→WATER=2→FIRE=3→EARTH=4)→费用→名称
	pool_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Dictionary = a["card"]
		var cb: Dictionary = b["card"]
		var elem_a: int = ca.get("element", 0)
		var elem_b: int = cb.get("element", 0)
		if elem_a != elem_b:
			return elem_a < elem_b
		var cost_a: int = ca.get("cost", 0)
		var cost_b: int = cb.get("cost", 0)
		if cost_a != cost_b:
			return cost_a < cost_b
		return ca.get("name", ca.get("card_name", "")) < cb.get("name", cb.get("card_name", ""))
	)

	for entry in pool_entries:
		_pool_list.add_child(_create_card_row(entry["card"], entry["index"], true, false))

	_pool_header.text = "收集（%d）" % pool_entries.size()

	if pool_entries.is_empty() and not GameState.collection.is_empty():
		var empty := Label.new()
		empty.text = "所有卡牌均已编入牌组"
		empty.add_theme_color_override("font_color", TEXT_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 53)
		_pool_list.add_child(empty)
		return

func _refresh_deck() -> void:
	for child in _deck_list.get_children():
		child.queue_free()

	_deck_header.text = "当前牌组（%d/%d）" % [GameState.deck.size(), GameState.deck_max_size]

	if GameState.deck.is_empty():
		var empty := Label.new()
		empty.text = "牌组为空，点击左侧卡牌加入"
		empty.add_theme_color_override("font_color", TEXT_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 53)
		_deck_list.add_child(empty)
		return

	# 收集牌库数据并排序：五行顺序→费用→名称
	var deck_entries: Array = []  # [{card, deck_index}]
	for i in range(GameState.deck.size()):
		var ci: int = GameState.deck[i]
		var card: Dictionary = GameState.get_collection_card(ci)
		deck_entries.append({"card": card, "deck_index": i})

	# 排序：五行顺序(METAL=0→WOOD=1→WATER=2→FIRE=3→EARTH=4)→费用→名称
	deck_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Dictionary = a["card"]
		var cb: Dictionary = b["card"]
		var elem_a: int = ca.get("element", 0)
		var elem_b: int = cb.get("element", 0)
		if elem_a != elem_b:
			return elem_a < elem_b
		var cost_a: int = ca.get("cost", 0)
		var cost_b: int = cb.get("cost", 0)
		if cost_a != cost_b:
			return cost_a < cost_b
		return ca.get("name", ca.get("card_name", "")) < cb.get("name", cb.get("card_name", ""))
	)

	for entry in deck_entries:
		_deck_list.add_child(_create_card_row(entry["card"], entry["deck_index"], false, false))

func _update_status() -> void:
	var remaining: int = GameState.deck_remaining()
	var _cost: int = GameState.get_removal_cost()
	_status_label.text = "牌组: %d/%d（剩余容量 %d）  灵石: %d" % [
		GameState.deck.size(), GameState.deck_max_size, remaining, GameState.spirit_stones
	]

# ==================== 卡牌行 ====================

func _create_card_row(card: Dictionary, index: int, is_pool: bool, is_in_deck: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 100)  # 提升高度以容纳 mini card
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var row_style := StyleBoxFlat.new()
	# 左栏（收集）偏灰，右栏（当前牌组）偏蓝，便于区分
	row_style.bg_color = ROW_HOVER if not is_pool else ROW_BG
	row_style.corner_radius_top_left = 6
	row_style.corner_radius_top_right = 6
	row_style.corner_radius_bottom_left = 6
	row_style.corner_radius_bottom_right = 6
	row_style.border_width_left = 1
	row_style.border_width_top = 1
	row_style.border_width_right = 1
	row_style.border_width_bottom = 1
	row_style.border_color = ACCENT if is_pool else Color(0.3, 0.5, 0.9, 0.5)
	row_style.content_margin_left = 8
	row_style.content_margin_right = 8
	row_style.content_margin_top = 6
	row_style.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# 元素色条（4px 宽，跨越整行）
	var elem: int = card.get("element", 0)
	var color_bar := ColorRect.new()
	color_bar.color = ELEMENT_COLORS[elem] if elem < ELEMENT_COLORS.size() else Color.WHITE
	color_bar.custom_minimum_size = Vector2(4, 88)
	hbox.add_child(color_bar)

	# Mini card 缩略图（60×90，复用卡牌立绘资源）
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(60, 88)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var img_path: String = card.get("image_path", "")
	if img_path != "" and ResourceLoader.exists(img_path):
		portrait.texture = load(img_path)
	else:
		var elem_names := ["metal", "wood", "water", "fire", "earth"]
		var elem_idx: int = clampi(elem, 0, 4)
		var fallback := "res://assets/images/card_bgs/element_%s.png" % elem_names[elem_idx]
		if ResourceLoader.exists(fallback):
			portrait.texture = load(fallback)
	portrait.modulate = Color(0.7, 0.7, 0.7, 1) if is_in_deck else Color.WHITE
	hbox.add_child(portrait)

	# 信息列
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	# 元素名 + 卡名（同一行）
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	info_vbox.add_child(title_row)

	var elem_label := Label.new()
	elem_label.text = "[%s]" % (ELEMENT_NAMES[elem] if elem < ELEMENT_NAMES.size() else "?")
	elem_label.add_theme_font_size_override("font_size", 15)
	elem_label.add_theme_color_override("font_color", ELEMENT_COLORS[elem] if elem < ELEMENT_COLORS.size() else Color.WHITE)
	title_row.add_child(elem_label)

	var name_label := Label.new()
	name_label.text = card.get("name", card.get("card_name", "?"))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", TEXT_COLOR if not is_in_deck else TEXT_MUTED)
	title_row.add_child(name_label)

	# 费用 + 效果（同一行）
	var cost_val: int = card.get("cost", 0)
	var stats := Label.new()
	var damage: int = int(card.get("damage", 0))
	var block: int = int(card.get("block", 0))
	var heal: int = int(card.get("heal", 0))
	var draw_count: int = int(card.get("draw_cards", 0))
	var stats_text: String = "费 %d" % cost_val
	if damage > 0: stats_text += "  伤害 %d" % damage
	if block > 0: stats_text += "  格挡 %d" % block
	if heal > 0: stats_text += "  治疗 %d" % heal
	if draw_count > 0: stats_text += "  抽牌 %d" % draw_count
	stats.text = stats_text
	stats.add_theme_font_size_override("font_size", 14)
	stats.add_theme_color_override("font_color", ACCENT if damage > 0 else TEXT_MUTED)
	info_vbox.add_child(stats)

	# 描述（截断）
	var desc_label := Label.new()
	var desc: String = card.get("description", "")
	desc_label.text = desc.left(35) + ("…" if desc.length() > 35 else "")
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", TEXT_MUTED)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(desc_label)

	# 操作按钮
	var action_btn := Button.new()
	action_btn.custom_minimum_size = Vector2(80, 40)
	action_btn.add_theme_font_size_override("font_size", 15)
	UITheme.apply_button(action_btn)

	if is_pool:
		if is_in_deck:
			action_btn.text = "已入"
			action_btn.disabled = true
		elif GameState.is_deck_full():
			action_btn.text = "已满"
			action_btn.disabled = true
		else:
			action_btn.text = "加入"
			action_btn.pressed.connect(_on_add_to_deck.bind(index))
	else:
		# 移出按钮：边框用红色（避免背景大块红的误删感）
		action_btn.text = "移出"
		var remove_style := StyleBoxFlat.new()
		remove_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
		remove_style.border_color = Color(0.85, 0.3, 0.2, 0.8)  # CINNAR 类色
		remove_style.border_width_left = 1
		remove_style.border_width_top = 1
		remove_style.border_width_right = 1
		remove_style.border_width_bottom = 1
		remove_style.corner_radius_top_left = 3
		remove_style.corner_radius_top_right = 3
		remove_style.corner_radius_bottom_left = 3
		remove_style.corner_radius_bottom_right = 3
		action_btn.add_theme_stylebox_override("normal", remove_style)
		action_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		action_btn.pressed.connect(_on_remove_from_deck.bind(index))

	hbox.add_child(action_btn)

	# 悬停效果
	row.mouse_entered.connect(func():
		row_style.bg_color = ROW_HOVER
	)
	row.mouse_exited.connect(func():
		row_style.bg_color = ROW_HOVER if not is_pool else ROW_BG
	)

	return row

# ==================== 操作 ====================

func _on_add_to_deck(collection_index: int) -> void:
	GameState.add_to_deck(collection_index)
	_refresh_all()

func _on_remove_from_deck(deck_index: int) -> void:
	var ci: int = GameState.deck[deck_index]
	var card: Variant = GameState.collection[ci]
	var card_name: String = card.get("name", card.get("card_name", "未知"))
	# 二次确认弹窗
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认移出"
	dialog.dialog_text = "确定要将「%s」从牌组中移出吗？" % card_name
	dialog.ok_button_text = "移出"
	dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.popup_centered(Vector2(350, 120))
	dialog.confirmed.connect(func():
		GameState.remove_from_deck(deck_index)
		_refresh_all()
		print("移出卡牌：%s" % card_name)
	)

func _on_close() -> void:
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
