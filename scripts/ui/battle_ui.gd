## 战斗 UI 控制器
## 管理战斗界面的显示和交互

# implements: design/08-ui-layout-spec.md
# implements_philosophy: rule_9_progressive_disclosure
# avoids_red_line: red_6_ui_overload

class_name BattleUI
extends CanvasLayer

const CardDataResource := preload("res://scripts/core/card_data.gd")

# ==================== 信号 ====================

signal card_selected(card_index: int)
signal enemy_selected(enemy_index: int)
signal end_turn_pressed

# ==================== UI 节点引用 ====================

@onready var player_hp_label: Label = %PlayerHPLabel
@onready var player_shield_label: Label = %PlayerShieldLabel
@onready var player_energy_label: Label = %PlayerEnergyLabel
@onready var hand_container: HBoxContainer = %HandContainer
@onready var enemy_container: HBoxContainer = %EnemyContainer
@onready var end_turn_button: Button = %EndTurnButton
@onready var battle_log_label: RichTextLabel = %BattleLogLabel
@onready var turn_label: Label = %TurnLabel
@onready var draw_pile_label: Label = %DrawPileLabel
@onready var discard_pile_label: Label = %DiscardPileLabel
@onready var mo_nian_label: Label = %MoNianLabel
@onready var erosion_label: Label = %ErosionLabel
@onready var overload_bar: ProgressBar = %OverloadBar
@onready var hand_size_label: Label = %HandSizeLabel
@onready var log_panel: PanelContainer = %LogPanel

var _log_visible: bool = true

# 手牌数量（single source of truth — agent_inspector 读这里避免 race condition）
# 在 update_hand_display 末尾同步设置，与 UI 实际渲染手牌一致
var hand_count: int = 0

# ==================== 卡牌场景 ====================

const CARD_SCENE := preload("res://scenes/card.tscn")

# ==================== 初始化 ====================

func _ready() -> void:
	UITheme.apply_button(end_turn_button)
	# 结束回合按钮特殊样式：深青底+霓虹边框+辉光
	end_turn_button.add_theme_font_size_override("font_size", 27)
	var end_btn_style := StyleBoxFlat.new()
	end_btn_style.bg_color = Color(0.0, 0.15, 0.15, 0.9)
	end_btn_style.border_color = UITheme.CYAN_NEON
	end_btn_style.border_width_left = 2
	end_btn_style.border_width_top = 2
	end_btn_style.border_width_right = 2
	end_btn_style.border_width_bottom = 2
	end_btn_style.corner_radius_top_left = 4
	end_btn_style.corner_radius_top_right = 4
	end_btn_style.corner_radius_bottom_left = 4
	end_btn_style.corner_radius_bottom_right = 4
	end_btn_style.shadow_size = 8
	end_btn_style.shadow_color = Color(UITheme.CYAN_NEON.r, UITheme.CYAN_NEON.g, UITheme.CYAN_NEON.b, 0.4)
	end_btn_style.shadow_offset = Vector2(0, 0)
	end_turn_button.add_theme_stylebox_override("normal", end_btn_style)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	# 日志折叠按钮
	var log_toggle: Button = get_node_or_null("MainHBox/LogToggle")
	if log_toggle:
		UITheme.apply_button(log_toggle)
		log_toggle.pressed.connect(_on_log_toggle)
		log_toggle.tooltip_text = "展开/折叠战斗日志"

# ==================== 更新显示 ====================

## 更新玩家状态显示
func update_player_display(player: Player) -> void:
	player_hp_label.text = "HP: %d/%d" % [player.current_hp, player.max_hp]
	player_shield_label.text = "盾: %d" % player.shield
	player_energy_label.text = "能量: %d/%d" % [player.current_energy, player.max_energy]

## 更新魔念/侵蚀/过载/手牌状态显示
func update_status_display(player: Player) -> void:
	# 魔念显示（颜色分级：0-2绿/3-4黄/5-7橙/8+红）
	mo_nian_label.text = "魔念: %d" % player.mo_nian
	var mo_nian_hint: String = """魔念影响：
• 每点魔念减少1点手牌上限
• 当前手牌上限: %d
• 魔念≥3: 心魔低语，跳过下次抽牌""" % (player.hand_size - player.mo_nian)
	mo_nian_label.tooltip_text = mo_nian_hint
	if player.mo_nian <= 2:
		mo_nian_label.add_theme_color_override("font_color", Color(0.3, 0.85, 0.3))
	elif player.mo_nian <= 4:
		mo_nian_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	elif player.mo_nian <= 7:
		mo_nian_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.0))
	else:
		mo_nian_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))

	# 侵蚀显示（带进度条）
	erosion_label.text = "侵蚀: %d/10" % player.erosion
	var erosion_hint: String = """侵蚀影响：
• 每张带侵蚀标签的卡牌使用后+侵蚀值
• 侵蚀≥5: 受到伤害+20%%
• 侵蚀≥8: 受到伤害+50%%
• 侵蚀=10: 立即死亡"""
	erosion_label.tooltip_text = erosion_hint
	# 可以在这里添加进度条样式，或者创建一个新的 ProgressBar 节点
	# 临时方案：通过颜色深浅表示侵蚀程度
	var erosion_ratio: float = float(player.erosion) / 10.0
	if erosion_ratio <= 0.3:
		erosion_label.add_theme_color_override("font_color", Color(0.3, 0.85, 0.3))
	elif erosion_ratio <= 0.6:
		erosion_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	elif erosion_ratio <= 0.8:
		erosion_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.0))
	else:
		erosion_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))

	# 过载进度条（灵力花费/10，阈值8标记）
	overload_bar.max_value = 10
	overload_bar.value = player.turn_spent_mana
	# 颜色：0-7蓝/8黄/9橙/10红
	if player.turn_spent_mana <= 7:
		overload_bar.modulate = Color(0.3, 0.5, 1.0)
	elif player.turn_spent_mana == 8:
		overload_bar.modulate = Color(1.0, 0.84, 0.0)
	elif player.turn_spent_mana == 9:
		overload_bar.modulate = Color(1.0, 0.55, 0.0)
	else:
		overload_bar.modulate = Color(1.0, 0.2, 0.1)

	# 手牌数
	hand_size_label.text = "手牌: %d/%d" % [player.hand.size(), player.hand_size - player.mo_nian]

## 更新手牌显示
func update_hand_display(hand: Array) -> void:
	# 清空现有卡牌
	for child in hand_container.get_children():
		child.queue_free()

	# 添加新卡牌
	for i in range(hand.size()):
		var card: CardDataResource = hand[i]
		var card_ui: CardUI = CARD_SCENE.instantiate()
		hand_container.add_child(card_ui)
		card_ui.setup(card)
		card_ui.card_clicked.connect(_on_card_clicked.bind(i))

	# 同步设置手牌数量属性（修复 AI Player 数据漂移 bug 2026-07-15：
	# state JSON 写 hand=1 vs 截图实际 3 张）
	# hand_count 是 single source of truth，避免 queue_free 延迟删除 + draw/discard 中间状态
	hand_count = hand.size()

## 更新敌人显示
func update_enemy_display(enemies: Array) -> void:
	# 清空现有敌人
	for child in enemy_container.get_children():
		child.queue_free()

	# 添加新敌人
	for enemy: Actor in enemies:
		if enemy.is_alive:
			var enemy_ui: Control = _create_enemy_ui(enemy)
			enemy_container.add_child(enemy_ui)

## 更新回合显示
func update_turn_display(turn_number: int, state_name: String) -> void:
	turn_label.text = "回合 %d | %s" % [turn_number, state_name]

## 更新牌堆信息显示
func update_pile_display(draw_count: int, discard_count: int) -> void:
	draw_pile_label.text = "牌库: %d" % draw_count
	discard_pile_label.text = "弃牌堆: %d" % discard_count

## 显示战斗日志
func show_log(message: String) -> void:
	battle_log_label.text = message

## 添加战斗日志（保留所有消息，自动滚动，带颜色图标）
func add_log(message: String) -> void:
	var formatted: String = _format_log_message(message)
	battle_log_label.append_text(formatted + "\n")
	# 自动滚动到底部
	await get_tree().process_frame
	var scroll: ScrollContainer = battle_log_label.get_parent()
	if scroll:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

## 五行 UI 配色（按 design/00-MASTER.md §五 + Robert 2026-06-29 审核）
## 传统五色 + 高对比度可读版（适合深色背景）
const WUXING_LOG_COLORS := {
	"金": "#E8E8F0",  # 银白
	"木": "#4CAF50",  # 翠绿
	"水": "#42A5F5",  # 冰蓝
	"火": "#EF5350",  # 朱红
	"土": "#D4A04C",  # 赭黄
}

func _format_log_message(message: String) -> String:
	# 五行相生链检测：消息含「X生Y」（X/Y 为五元素），按「被生者」Y 着色
	var target_elem: String = _extract_generation_target(message)
	if target_elem != "":
		var color_hex: String = WUXING_LOG_COLORS.get(target_elem, "#FFD700")
		return "[color=%s]⚡ %s[/color]" % [color_hex, message]

	# 五行相生触发（无具体元素）
	if message.contains("相生") or message.contains("五行") or message.contains("连锁"):
		return "[color=#D4A04C]⚡ %s[/color]" % message
	# 攻击/伤害类
	if message.contains("攻击") or message.contains("伤害") or message.contains("造成") or message.contains("打击"):
		return "[color=#FF6666]⚔ %s[/color]" % message
	# 治疗类
	if message.contains("治疗") or message.contains("回复") or message.contains("恢复") or message.contains("生命"):
		return "[color=#66FF66]♥ %s[/color]" % message
	# 防御/格挡类
	if message.contains("防御") or message.contains("格挡") or message.contains("护盾") or message.contains("抵挡"):
		return "[color=#66AAFF]🛡 %s[/color]" % message
	# 魔念/侵蚀变化
	if message.contains("魔念") or message.contains("侵蚀") or message.contains("心魔"):
		return "[color=#CC88FF]🌀 %s[/color]" % message
	# 敌人行动
	if message.contains("敌人") or message.contains("意图") or message.contains("准备"):
		return "[color=#FFAA44]👁 %s[/color]" % message
	return message

## 从消息中提取「X生Y」的被生者元素
func _extract_generation_target(message: String) -> String:
	var regex := RegEx.new()
	regex.compile("([金木水火土])生([金木水火土])")
	var result := regex.search(message)
	if result:
		return result.get_string(2)
	return ""

# ==================== UI 交互 ====================

func _on_card_clicked(card_index: int) -> void:
	print("BattleUI: 卡牌点击 signal 收到, index=%d" % card_index)
	card_selected.emit(card_index)

func _on_end_turn_pressed() -> void:
	print("BattleUI: 结束回合 button pressed")
	end_turn_pressed.emit()

func _on_log_toggle() -> void:
	_log_visible = !_log_visible
	if log_panel:
		log_panel.visible = _log_visible
	var toggle: Button = get_node_or_null("MainHBox/LogToggle")
	if toggle:
		toggle.text = "\u25B6" if _log_visible else "\u25C0"

# ==================== 内部方法 ====================

func _create_enemy_ui(enemy: Actor) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 293)
	# 重要：不设 size_flags_vertical 默认是 FILL，会把整个 EnemyArea 的纵向空间
	# 全撑开（约 600px 空向）。SHRINK_CENTER 让它保持 min size + 纵向居中。
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := UITheme.panel_style.duplicate()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.92)
	style.border_color = Color(0.5, 0.5, 0.6)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var enemy_index: int = enemy_container.get_child_count()
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			enemy_selected.emit(enemy_index)
	)
	panel.mouse_entered.connect(func():
		style.border_color = UITheme.GOLD
	)
	panel.mouse_exited.connect(func():
		style.border_color = Color(0.5, 0.5, 0.6)
	)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# 敌人立绘
	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(160, 160)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	if enemy is Enemy and enemy.image_path != "" and ResourceLoader.exists(enemy.image_path):
		sprite.texture = load(enemy.image_path)
	vbox.add_child(sprite)

	# 敌人名称
	var name_label := Label.new()
	name_label.text = enemy.actor_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# HP 显示
	var hp_label := Label.new()
	hp_label.text = "❤️ HP: %d/%d" % [enemy.current_hp, enemy.max_hp]
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 17)
	hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	vbox.add_child(hp_label)

	# 护盾显示
	if enemy.shield > 0:
		var shield_label := Label.new()
		shield_label.text = "🛡️ 盾: %d" % enemy.shield
		shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(shield_label)

	# 意图显示（如果有）
	var intent_label := Label.new()
	if enemy is Enemy:
		var intent_desc: String = enemy.get_intent_description()
		var intent_detail: String = enemy.get_intent_detail()
		var intent_icon := "👁 "
		var intent_type_tmp = enemy.current_intent.get("type", -1)
		match intent_type_tmp:
			Enemy.IntentType.ATTACK, Enemy.IntentType.PIERCE, Enemy.IntentType.ATK_BUFF:
				intent_icon = "⚔️ "
			Enemy.IntentType.DEFEND, Enemy.IntentType.DEF_BUFF:
				intent_icon = "🛡️ "
			Enemy.IntentType.HEAL:
				intent_icon = "💚 "
			Enemy.IntentType.WEAKEN, Enemy.IntentType.VULNERABLE, Enemy.IntentType.POISON:
				intent_icon = "💀 "
		if not intent_detail.is_empty():
			intent_label.text = "%s意图: %s (%s)" % [intent_icon, intent_desc, intent_detail]
		else:
			intent_label.text = "%s意图: %s" % [intent_icon, intent_desc]
		# 根据意图类型设置颜色
		match intent_type_tmp:
			Enemy.IntentType.ATTACK, Enemy.IntentType.PIERCE, Enemy.IntentType.ATK_BUFF:
				intent_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # 红色-攻击
			Enemy.IntentType.DEFEND, Enemy.IntentType.DEF_BUFF:
				intent_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))  # 蓝色-防御
			Enemy.IntentType.HEAL:
				intent_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))  # 绿色-治疗
			Enemy.IntentType.WEAKEN, Enemy.IntentType.VULNERABLE, Enemy.IntentType.POISON:
				intent_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))  # 紫色-debuff
			_:
				intent_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))  # 灰色-其他
	else:
		intent_label.text = ""
	intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(intent_label)

	return panel

## 设置 UI 可见性
func set_ui_visible(p_visible: bool) -> void:
	visible = p_visible
