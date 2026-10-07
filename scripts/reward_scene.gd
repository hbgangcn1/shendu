## 奖励场景
## 战斗胜利后三选一卡牌（含翻牌动画 + hover 增强）

# implements: design/12-reward-system-spec.md
# implements_philosophy: rule_2_failure_must_have_meaning, rule_5_real_agency
# avoids_red_line: red_4_fake_choices

extends Control

const BattleReward = preload("res://scripts/core/reward_data.gd")
const CardScene := preload("res://scenes/card.tscn")

# ==================== 节点引用 ====================

@onready var title_label: Label = %TitleLabel
@onready var stones_label: Label = %StonesLabel
@onready var daoxing_label: Label = %DaoxingLabel
@onready var card_container: HBoxContainer = %CardContainer
@onready var skip_button: Button = %SkipButton

# ==================== 状态 ====================

var reward: BattleReward = null
var card_buttons: Array = []  ## 每项 {panel: PanelContainer, base_pos: Vector2, color: Color}
var _anim_locked: bool = false  ## 翻牌动画进行中时锁定交互

# ==================== 初始化 ====================

func _ready() -> void:
	# 添加半透明文字安全区背板（纯装饰，必须 IGNORE 让事件穿透到下面的卡牌和按钮）
	var backdrop := PanelContainer.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.z_index = -1
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = 240
	backdrop.offset_top = 107
	backdrop.offset_right = -240
	backdrop.offset_bottom = -107
	var bd_style := StyleBoxFlat.new()
	bd_style.bg_color = Color(0.05, 0.05, 0.1, 0.92)  # 提升不透明度，让文字更清晰
	bd_style.border_color = Color(0.3, 0.3, 0.5, 0.5)
	bd_style.border_width_left = 1
	bd_style.border_width_top = 1
	bd_style.border_width_right = 1
	bd_style.border_width_bottom = 1
	bd_style.corner_radius_top_left = 12
	bd_style.corner_radius_top_right = 12
	bd_style.corner_radius_bottom_left = 12
	bd_style.corner_radius_bottom_right = 12
	bd_style.content_margin_left = 20
	bd_style.content_margin_top = 20
	bd_style.content_margin_right = 20
	bd_style.content_margin_bottom = 20
	bd_style.shadow_color = Color(0, 0, 0, 0.5)
	bd_style.shadow_size = 8
	bd_style.shadow_offset = Vector2(0, 4)
	backdrop.add_theme_stylebox_override("panel", bd_style)
	add_child(backdrop)

	# 读取奖励
	reward = GameState.get_meta("last_reward", null)
	if not reward:
		reward = BattleReward.generate(false, false, GameState.current_realm)

	# 应用墨韵赛博主题
	UITheme.apply_title_label(title_label, 48)  # 提升标题字号
	UITheme.apply_body_label(stones_label, 24)
	UITheme.apply_body_label(daoxing_label, 24)
	UITheme.apply_button(skip_button)

	# 显示奖励信息
	title_label.text = "战斗胜利！"
	stones_label.text = "灵石 +%d" % reward.spirit_stones
	daoxing_label.text = "道行 +%d" % reward.dao_xing

	# 创建卡牌选项（初始为卡背状态）
	_create_card_choices()

	skip_button.pressed.connect(_on_skip_pressed)

	# 加 “查看牌组” 按钮（Robert 反馈 2026-06-29 奖励无牌组入口）
	var view_deck_btn := Button.new()
	view_deck_btn.text = "查看牌组"
	view_deck_btn.custom_minimum_size = Vector2(160, 48)
	view_deck_btn.add_theme_font_size_override("font_size", 18)
	UITheme.apply_button(view_deck_btn)
	view_deck_btn.pressed.connect(_on_view_deck_pressed)
	# 放在 skip_button 旁边
	skip_button.get_parent().add_child(view_deck_btn)
	skip_button.get_parent().move_child(view_deck_btn, skip_button.get_index() - 1)

	print("奖励：灵石+%d, 道行+%d, 卡牌选项=%d" % [
		reward.spirit_stones, reward.dao_xing, reward.card_choices.size()
	])

	# 翻牌动画：等待布局稳定后依次翻开
	_anim_locked = true
	await get_tree().create_timer(0.3).timeout
	_flip_cards_in_sequence()

# ==================== 卡牌选项 ====================

func _create_card_choices() -> void:
	for i in range(reward.card_choices.size()):
		var card_data = reward.card_choices[i]
		var entry := _create_card_button(card_data, i)
		card_container.add_child(entry.panel)
		card_buttons.append(entry)

func _create_card_button(card_data, index: int) -> Dictionary:
	var panel: PanelContainer = CardScene.instantiate()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.custom_minimum_size = Vector2(180, 280)  # 按 spec §16 奖励卡牌 W=180 H=260
	panel.pivot_offset = Vector2(90, 140)  # 中心轴用于翻牌旋转
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# 从 effects 提取数值
	var damage: int = card_data.damage
	var block: int = card_data.block
	var heal: int = card_data.heal
	var draw_cards: int = card_data.draw_cards
	if damage == 0 and block == 0 and heal == 0 and draw_cards == 0:
		for effect in card_data.effects:
			var action: Dictionary = effect.get("action", {})
			if action.is_empty():
				action = effect
			var e_type: String = action.get("type", "")
			var e_val: int = int(action.get("value", 0))
			if e_type == "Damage": damage = e_val
			elif e_type == "Block": block = e_val
			elif e_type == "Heal": heal = e_val
			elif e_type == "Draw": draw_cards = e_val

	# 构建描述文本
	var elem_name: String = WuXing.get_element_name(card_data.element)
	var type_text: String = card_data.get_kind_name()
	var rarity_text: String = card_data.get_rarity_name()
	var desc_parts: Array = []
	if damage > 0: desc_parts.append("伤害 %d" % damage)
	if block > 0: desc_parts.append("格挡 %d" % block)
	if heal > 0: desc_parts.append("治疗 %d" % heal)
	if draw_cards > 0: desc_parts.append("抽牌 %d" % draw_cards)
	var effect_desc: String = " | ".join(desc_parts) if not desc_parts.is_empty() else ""
	var flavor_desc: String = card_data.description

	# 设置卡牌内容
	var name_label: Label = panel.get_node("%CardNameLabel")
	var cost_label: Label = panel.get_node("%CostLabel")
	var desc_label: Label = panel.get_node("%DescriptionLabel")
	if name_label: name_label.text = "[%s] %s" % [elem_name, card_data.name]
	if cost_label: cost_label.text = str(card_data.cost)
	if desc_label: desc_label.text = "%s\n%s\n%s" % [type_text + " | " + rarity_text, effect_desc, flavor_desc]

	# 设置元素颜色
	var color := WuXing.get_element_color(card_data.element)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.8)
	style.border_color = color
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	# 加载卡牌立绘
	var portrait: TextureRect = panel.get_node_or_null("%Portrait")
	if portrait:
		var img_path: String = card_data.art_path if card_data.art_path != "" else ""
		if img_path != "" and ResourceLoader.exists(img_path):
			portrait.texture = load(img_path)
		else:
			var elem_names := ["metal", "wood", "water", "fire", "earth"]
			var elem_idx: int = clampi(int(card_data.element), 0, 4)
			var fallback := "res://assets/images/card_bgs/element_%s.png" % elem_names[elem_idx]
			if ResourceLoader.exists(fallback):
				portrait.texture = load(fallback)

	# 初始状态：显示卡背，隐藏正面内容
	var backface: ColorRect = panel.get_node_or_null("%BackFace")
	if backface:
		backface.visible = true
		backface.modulate = Color(1, 1, 1, 1)

	# 记录基础位置（hover 还原用）
	var base_pos := panel.position

	# 点击事件
	panel.gui_input.connect(func(event: InputEvent):
		if _anim_locked:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_pressed(index)
	)

	# hover 增强：缩放 1.05 + Y 轴 -10 + 边框高亮
	panel.mouse_entered.connect(func():
		if _anim_locked:
			return
		style.border_color = Color(1, 1, 1, 1)  # 边框高亮
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "scale", Vector2(1.05, 1.05), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "position:y", base_pos.y - 10, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	panel.mouse_exited.connect(func():
		style.border_color = color
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "position:y", base_pos.y, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	return {"panel": panel, "base_pos": base_pos, "color": color, "style": style}

# ==================== 翻牌动画 ====================

## 依次翻开 3 张卡（Y 轴旋转 0→180°，每张间隔 0.25s）
func _flip_cards_in_sequence() -> void:
	for entry in card_buttons:
		await _flip_one_card(entry)
		await get_tree().create_timer(0.2).timeout
	_anim_locked = false

func _flip_one_card(entry: Dictionary) -> void:
	var panel: PanelContainer = entry.panel
	# 阶段 1: 卡背 1→0 (Y 轴模拟用 scale.x 0→1 翻转)
	var tw1 := create_tween()
	tw1.tween_property(panel, "scale:x", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw1.tween_callback(func():
		# 中点：切换可见性
		var backface: ColorRect = panel.get_node_or_null("%BackFace")
		if backface:
			backface.visible = false
	)
	await tw1.finished
	# 阶段 2: 正面 0→1
	var tw2 := create_tween()
	tw2.tween_property(panel, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 同时给个轻微的 Y 弹出，增强仪式感
	tw2.parallel().tween_property(panel, "scale:y", 1.05, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.chain().tween_property(panel, "scale:y", 1.0, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tw2.finished

# ==================== 交互 ====================

func _on_card_pressed(index: int) -> void:
	# 领取奖励
	GameState.spirit_stones += reward.spirit_stones
	GameState.dao_xing += reward.dao_xing

	# 选中的卡牌加入卡牌池和牌库
	if index >= 0 and index < reward.card_choices.size():
		var card = reward.card_choices[index]
		# 将 CardDataResource 转为 Dictionary 存入卡牌池
		var card_dict: Dictionary = {
			"id": card.id,
			"name": card.name,
			"description": card.description,
			"cost": card.cost,
			"element": card.element,
			"card_kind": card.card_kind,
			"rarity": card.rarity,
			"damage": card.damage,
			"block": card.block,
			"heal": card.heal,
			"draw_cards": card.draw_cards,
			"effects": card.effects,
		}
		var idx: int = GameState.add_to_collection(card_dict)
		GameState.add_to_deck(idx)
		print("奖励：卡牌「%s」加入卡牌池和牌库" % card.name)

	# 选中卡牌轻微放大 + 金色描边（视觉反馈）
	var entry: Dictionary = card_buttons[index]
	var panel: PanelContainer = entry.panel
	var style: StyleBoxFlat = entry.style
	style.border_color = Color(1.0, 0.84, 0.0)  # 金色
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	var tw := create_tween()
	tw.tween_property(panel, "scale", Vector2(1.1, 1.1), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	await get_tree().create_timer(0.3).timeout
	_return_to_map()

## 打开牌组查看窗口（透明叠加，玩家仍能看到奖励）
func _on_view_deck_pressed() -> void:
	var DeckViewScene := preload("res://scripts/ui/deck_view.gd")
	var deck_view: Control = DeckViewScene.new()
	deck_view.z_index = 150
	deck_view.anchor_left = 0.0
	deck_view.anchor_top = 0.0
	deck_view.anchor_right = 1.0
	deck_view.anchor_bottom = 1.0
	deck_view.offset_left = 0.0
	deck_view.offset_top = 0.0
	deck_view.offset_right = 0.0
	deck_view.offset_bottom = 0.0
	add_child(deck_view)
	# 关闭牌组窗口后玩家仍返回奖励场景（不退出）
	# deck_view 自己有 ✕ 关闭按钮

func _on_skip_pressed() -> void:
	if _anim_locked:
		return
	# 只领灵石和道行，不选卡
	GameState.spirit_stones += reward.spirit_stones
	GameState.dao_xing += reward.dao_xing
	_return_to_map()

func _return_to_map() -> void:
	GameState.set_meta("last_reward", null)
	get_tree().change_scene_to_file("res://scenes/map.tscn")
