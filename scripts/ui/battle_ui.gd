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

# ==================== 新手引导（onboarding） ====================

# 引导步骤枚举
enum TutorialStep {
	NONE = -1,      # 无引导/已完成
	WELCOME = 0,    # 欢迎：点击卡牌
	SELECT_ENEMY = 1, # 选择敌人
	PLAY_CARD = 2,  # 打出卡牌
	END_TURN = 3,   # 结束回合
	ENERGY = 4,     # 灵力说明
	WUXING = 5,     # 五行相生
	COMPLETE = 6    # 完成
}

var _tutorial_step: TutorialStep = TutorialStep.NONE
var _tutorial_overlay: Control = null
var _tutorial_label: RichTextLabel = null
var _tutorial_arrow: TextureRect = null
var _tutorial_highlight: PanelContainer = null
var _tutorial_dismissed: bool = false

# ==================== 卡牌场景 ====================

const CARD_SCENE := preload("res://scenes/card.tscn")

# ==================== 初始化 ====================

func _ready() -> void:
	# 2026-08-10 (minimax art review #1): HUD 文字（回合/地点/HP/灵力/魔念/锁）在水墨背景上对比度过低
	# 加 font_color (TEXT_PRIMARY) + outline_size 4 + outline_color 黑，高对比任何背景
	for lbl: Label in [turn_label, player_hp_label, player_shield_label, player_energy_label, draw_pile_label, discard_pile_label, mo_nian_label, erosion_label, hand_size_label]:
		if lbl == null:
			continue
		lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		lbl.add_theme_constant_override("outline_size", 4)

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
	end_turn_button.tooltip_text = "结束当前回合，敌人将按显示的意图行动。下回合灵力回满并抽新牌。"
	# 日志折叠按钮
	var log_toggle: Button = get_node_or_null("MainHBox/LogToggle")
	if log_toggle:
		UITheme.apply_button(log_toggle)
		log_toggle.pressed.connect(_on_log_toggle)
		log_toggle.tooltip_text = "展开/折叠战斗日志"
	# 手牌容器提示
	if hand_container:
		hand_container.tooltip_text = "当前手牌。点击卡牌选择，选中目标后再次点击打出。"
	# 敌人容器提示
	if enemy_container:
		enemy_container.tooltip_text = "敌人列表。点击选择目标。敌人头上显示意图（攻击/防御/治疗等）。"
	# 灵力标签提示
	if player_energy_label:
		player_energy_label.tooltip_text = "当前灵力 / 最大灵力。每回合恢复到上限。出牌消耗灵力。单回合花费>8会增加魔念。"
	# 牌库/弃牌堆提示
	if draw_pile_label:
		draw_pile_label.tooltip_text = "牌库剩余卡牌数。用完后弃牌堆洗牌重置为新牌库。"
	if discard_pile_label:
		discard_pile_label.tooltip_text = "弃牌堆卡牌数。使用过的卡牌进入弃牌堆。"
	# 魔念/侵蚀/过载提示
	if mo_nian_label:
		mo_nian_label.tooltip_text = "魔念值。每点减少1点手牌上限。魔念≥3：心魔低语，跳过下次抽牌。"
	if erosion_label:
		erosion_label.tooltip_text = "侵蚀值。使用带侵蚀标签的卡牌后增加。侵蚀≥5：受到伤害+20%。侵蚀≥8：受到伤害+50%。侵蚀=10：立即死亡。"
	if overload_bar:
		overload_bar.tooltip_text = "过载条。显示本回合已花费灵力/10。超过8进入过载区，会增加魔念。"
	if hand_size_label:
		hand_size_label.tooltip_text = "当前手牌数 / 手牌上限（受魔念影响）"
	# 回合标签提示
	if turn_label:
		turn_label.tooltip_text = "当前回合数和战斗状态"

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
		var intent_type_tmp: Variant = enemy.current_intent.get("type", -1)
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

# ==================== 新手引导（onboarding）实现 ====================

## 开始新手引导（在首战时调用）
func start_tutorial() -> void:
	if GameState.first_battle_done:
		return
	_tutorial_step = TutorialStep.WELCOME
	_tutorial_dismissed = false
	_create_tutorial_overlay()
	_show_tutorial_step()

## 创建引导覆盖层
func _create_tutorial_overlay() -> void:
	# 半透明遮罩
	_tutorial_overlay = Control.new()
	_tutorial_overlay.layout_mode = 3  # FULL_RECT
	_tutorial_overlay.anchors_preset = 15  # FULL_RECT
	_tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tutorial_overlay)
	
	# 高亮面板（用于框住目标 UI）
	_tutorial_highlight = PanelContainer.new()
	_tutorial_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var highlight_style := StyleBoxFlat.new()
	highlight_style.bg_color = Color(0, 0, 0, 0)
	highlight_style.border_color = UITheme.GOLD
	highlight_style.border_width_left = 3
	highlight_style.border_width_top = 3
	highlight_style.border_width_right = 3
	highlight_style.border_width_bottom = 3
	highlight_style.corner_radius_top_left = 8
	highlight_style.corner_radius_top_right = 8
	highlight_style.corner_radius_bottom_left = 8
	highlight_style.corner_radius_bottom_right = 8
	highlight_style.shadow_size = 16
	highlight_style.shadow_color = Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.5)
	_tutorial_highlight.add_theme_stylebox_override("panel", highlight_style)
	_tutorial_highlight.visible = false
	_tutorial_overlay.add_child(_tutorial_highlight)
	
	# 文本标签
	_tutorial_label = RichTextLabel.new()
	_tutorial_label.layout_mode = 2  # ANCHORED
	_tutorial_label.anchors_preset = 0  # TOP_LEFT
	_tutorial_label.custom_minimum_size = Vector2(300, 120)
	_tutorial_label.bbcode_enabled = true
	_tutorial_label.scroll_active = false
	_tutorial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label_style := StyleBoxFlat.new()
	label_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	label_style.border_color = UITheme.CYAN_NEON
	label_style.border_width_left = 2
	label_style.border_width_top = 2
	label_style.border_width_right = 2
	label_style.border_width_bottom = 2
	label_style.corner_radius_top_left = 8
	label_style.corner_radius_top_right = 8
	label_style.corner_radius_bottom_left = 8
	label_style.corner_radius_bottom_right = 8
	label_style.content_margin_left = 16
	label_style.content_margin_right = 16
	label_style.content_margin_top = 12
	label_style.content_margin_bottom = 12
	_tutorial_label.add_theme_stylebox_override("normal", label_style)
	_tutorial_label.add_theme_font_size_override("normal_font_size", 22)
	_tutorial_label.add_theme_color_override("default_color", Color(0.9, 0.95, 1.0, 1.0))
	_tutorial_overlay.add_child(_tutorial_label)
	
	# 箭头指示器
	_tutorial_arrow = TextureRect.new()
	_tutorial_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_arrow.visible = false
	# 创建一个简单的三角形箭头
	# 修复 2026-07-22：Godot 4 Image.create() 有时返回错误，改用 create_empty
	# 避免 width=0 触发 set_pixel out of bounds
	var arrow_img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for x in range(32):
		for y in range(32):
			var cx: float = 16.0
			var cy: float = 16.0
			var dx: Variant = x - cx
			var dy: Variant = y - cy
			# 向下的三角形
			if abs(dx) * 2 < (16 - dy) and dy < 16:
				arrow_img.set_pixel(x, y, UITheme.GOLD)
	var arrow_tex := ImageTexture.create_from_image(arrow_img)
	_tutorial_arrow.texture = arrow_tex
	_tutorial_arrow.custom_minimum_size = Vector2(32, 32)
	_tutorial_overlay.add_child(_tutorial_arrow)

## 显示当前引导步骤
func _show_tutorial_step() -> void:
	if _tutorial_step == TutorialStep.NONE or _tutorial_step == TutorialStep.COMPLETE:
		_end_tutorial()
		return
	
	var step_data: Dictionary = _get_tutorial_step_data(_tutorial_step)
	if step_data.is_empty():
		_next_tutorial_step()
		return
	
	# 更新文本
	_tutorial_label.text = step_data.get("text", "")
	
	# 定位标签和高亮
	var target_node: Control = step_data.get("target_node", null)
	var label_pos: Vector2 = step_data.get("label_pos", Vector2(50, 50))
	var highlight_rect: Rect2 = step_data.get("highlight_rect", Rect2())
	var arrow_pos: Vector2 = step_data.get("arrow_pos", Vector2())
	var arrow_rotation: float = step_data.get("arrow_rotation", 0.0)
	
	_tutorial_label.global_position = label_pos
	
	if highlight_rect != Rect2():
		_tutorial_highlight.global_position = highlight_rect.position
		_tutorial_highlight.custom_minimum_size = highlight_rect.size
		_tutorial_highlight.visible = true
	else:
		_tutorial_highlight.visible = false
	
	if arrow_pos != Vector2():
		_tutorial_arrow.global_position = arrow_pos
		_tutorial_arrow.rotation = arrow_rotation
		_tutorial_arrow.visible = true
	else:
		_tutorial_arrow.visible = false

## 获取引导步骤数据
func _get_tutorial_step_data(step: TutorialStep) -> Dictionary:
	match step:
		TutorialStep.WELCOME:
			var hand_node: Node = get_node_or_null("MainHBox/GameArea/BottomPanel/BottomVBox/HandContainer")
			return {
				"text": "[color=#FFD700]欢迎来到蜃都战斗！[/color]\n\n点击手牌中的 [color=#4CAF50]卡牌[/color] 来选择它。",
				"target_node": hand_node,
				"label_pos": Vector2(50, 50),
				"highlight_rect": Rect2(hand_node.global_position - Vector2(10, 10), hand_node.size + Vector2(20, 20)) if hand_node else Rect2(),
				"arrow_pos": Vector2(hand_node.global_position.x + hand_node.size.x / 2, hand_node.global_position.y - 40) if hand_node else Vector2(),
				"arrow_rotation": -PI / 2,
			}
		TutorialStep.SELECT_ENEMY:
			var enemy_node: Node = get_node_or_null("MainHBox/GameArea/EnemyArea/EnemyContainer")
			return {
				"text": "很好！现在点击敌人 [color=#EF5350]选择目标[/color]。\n敌人头上会显示 [color=#FFAA44]意图[/color]（攻击/防御/治疗等）。",
				"target_node": enemy_node,
				"label_pos": Vector2(50, 50),
				"highlight_rect": Rect2(enemy_node.global_position - Vector2(10, 10), enemy_node.size + Vector2(20, 20)) if enemy_node else Rect2(),
				"arrow_pos": Vector2(enemy_node.global_position.x + enemy_node.size.x / 2, enemy_node.global_position.y - 40) if enemy_node else Vector2(),
				"arrow_rotation": -PI / 2,
			}
		TutorialStep.PLAY_CARD:
			return {
				"text": "目标选中后，再次点击 [color=#4CAF50]卡牌[/color] 即可 [color=#FFD700]打出[/color]。\n消耗的 [color=#42A5F5]灵力[/color] 显示在左下角。",
				"target_node": get_node_or_null("MainHBox/GameArea/BottomPanel/BottomVBox/HandContainer"),
				"label_pos": Vector2(50, 50),
				"arrow_pos": Vector2(),
			}
		TutorialStep.END_TURN:
			var btn: Node = get_node_or_null("MainHBox/GameArea/BottomPanel/BottomVBox/EndTurnButton")
			return {
				"text": "打完牌后，点击 [color=#FFD700]结束回合[/color] 按钮。\n敌人将按 [color=#FFAA44]意图[/color] 行动。\n\n下回合灵力会 [color=#42A5F5]回满[/color] 并 [color=#4CAF50]抽新牌[/color]。",
				"target_node": btn,
				"label_pos": Vector2(btn.global_position.x - 350, btn.global_position.y - 140) if btn else Vector2(50, 50),
				"highlight_rect": Rect2(btn.global_position - Vector2(10, 10), btn.size + Vector2(20, 20)) if btn else Rect2(),
				"arrow_pos": Vector2(btn.global_position.x + btn.size.x / 2, btn.global_position.y - 40) if btn else Vector2(),
				"arrow_rotation": -PI / 2,
			}
		TutorialStep.ENERGY:
			var energy_label: Node = get_node_or_null("MainHBox/GameArea/BottomPanel/BottomVBox/PlayerInfoRow/PlayerEnergyLabel")
			return {
				"text": "[color=#42A5F5]灵力[/color] 每回合恢复到上限（默认 10）。\n出牌消耗灵力，规划好每回合的花费。\n\n[color=#D4A04C]过载[/color]：单回合花费 > 8 会增加 [color=#CC88FF]魔念[/color]。",
				"target_node": energy_label,
				"label_pos": Vector2(50, 50),
				"highlight_rect": Rect2(energy_label.global_position - Vector2(10, 10), energy_label.size + Vector2(20, 20)) if energy_label else Rect2(),
			}
		TutorialStep.WUXING:
			return {
				"text": "[color=#D4A04C]五行相生[/color] 机制：\n金生水、水生木、木生火、火生土、土生金。\n\n连续打出相生元素的卡牌会触发 [color=#FFD700]相生链[/color]，获得额外增益（伤害加成/抽牌/减费等）。\n\n链长越长，增益越强（但有衰减）。",
				"target_node": get_node_or_null("MainHBox/GameArea/BottomPanel/BottomVBox/StatusRow/MoNianLabel"),
				"label_pos": Vector2(50, 50),
			}
		TutorialStep.COMPLETE:
			return {
				"text": "[color=#4CAF50]基础教程完成！[/color]\n\n记住：\n• 点卡牌 → 选敌人 → 再点卡牌 → 结束回合\n• 关注敌人意图，针对性防御\n• 善用五行相生链\n• 管理魔念与侵蚀\n\n祝道友修行顺遂！",
				"label_pos": Vector2(50, 50),
			}
		_:
			return {}

## 进入下一引导步骤
func _next_tutorial_step() -> void:
	# 修复 2026-07-22: Godot 4 不支持 TutorialStep(int_value) 构造语法
	# 用 (int_value) as TutorialStep 显式转换回 enum
	var next_value: int = int(_tutorial_step) + 1
	if next_value > int(TutorialStep.COMPLETE):
		_end_tutorial()
		return
	_tutorial_step = next_value as TutorialStep
	_show_tutorial_step()

## 结束引导
func _end_tutorial() -> void:
	if _tutorial_overlay:
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
	_tutorial_step = TutorialStep.NONE
	GameState.first_battle_done = true
	print("BattleUI: 新手引导完成，标记 first_battle_done = true")

## 外部调用：卡牌被点击时推进引导
func on_card_clicked_during_tutorial() -> void:
	if _tutorial_step == TutorialStep.WELCOME:
		_next_tutorial_step()
	elif _tutorial_step == TutorialStep.PLAY_CARD:
		_next_tutorial_step()

## 外部调用：敌人被点击时推进引导
func on_enemy_selected_during_tutorial() -> void:
	if _tutorial_step == TutorialStep.SELECT_ENEMY:
		_next_tutorial_step()

## 外部调用：结束回合按钮被点击时推进引导
func on_end_turn_pressed_during_tutorial() -> void:
	if _tutorial_step == TutorialStep.END_TURN:
		_next_tutorial_step()

## 外部调用：回合开始时推进引导（显示灵力/五行说明）
func on_turn_started_during_tutorial(turn: int) -> void:
	if turn == 1 and _tutorial_step == TutorialStep.ENERGY:
		_next_tutorial_step()
	elif turn == 2 and _tutorial_step == TutorialStep.WUXING:
		_next_tutorial_step()
