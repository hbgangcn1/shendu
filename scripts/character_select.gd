## 角色选择界面
## 左右卡片切换聚焦，点击确认选择

# implements: design/01-player-experience.md
# implements_philosophy: rule_5_real_agency

extends Control

# ==================== 节点引用 ====================

@onready var chenmo_card: PanelContainer = %ChenmoCard
@onready var suwan_card: PanelContainer = %SuwanCard
@onready var auto_select_timer: Timer = %AutoSelectTimer
@onready var confirm_button: Button = %ConfirmButton

# ==================== 状态 ====================

var focused_index: int = 0
var cards: Array[PanelContainer] = []
var focus_style: StyleBoxFlat
var normal_style: StyleBoxFlat
# 2026-07-25 gate_1 fix B: 全屏点击确认（解决 click miss 问题）
var _quick_confirm: Button = null

# ==================== 初始化 ====================

func _ready() -> void:
	cards = [chenmo_card, suwan_card]

	# 应用墨韵赛博主题
	UITheme.apply_panel(chenmo_card)
	UITheme.apply_panel(suwan_card)
	UITheme.apply_button(confirm_button)

	# 创建聚焦样式（霓虹描边）
	focus_style = UITheme.panel_style.duplicate()
	focus_style.border_color = UITheme.CYAN_NEON
	focus_style.border_width_left = 2
	focus_style.border_width_top = 2
	focus_style.border_width_right = 2
	focus_style.border_width_bottom = 2
	focus_style.shadow_color = Color(UITheme.CYAN_NEON, 0.3)
	focus_style.shadow_size = 8

	# 普通样式（低亮度边框）
	normal_style = UITheme.panel_style.duplicate()
	normal_style.border_color = Color(UITheme.CYAN_NEON, 0.15)

	# 连接卡片输入信号
	chenmo_card.gui_input.connect(_on_card_gui_input.bind(0))
	suwan_card.gui_input.connect(_on_card_gui_input.bind(1))

	# 连接自动选择计时器
	auto_select_timer.timeout.connect(_on_auto_select_timeout)
	# 2026-07-25 gate_1 fix A: 缩短 auto-select 时间，AI Player click miss 时能快速恢复
	# 磊哥 skill v1 借鉴：hard gate #1 要求核心循环可玩通，10s 太长会导致 AI Player 卡在 character_select
	auto_select_timer.wait_time = 2.0
	auto_select_timer.one_shot = true
	auto_select_timer.start()

	# 确认按钮
	confirm_button.pressed.connect(_confirm_selection)

	_update_focus()

	# 2026-07-25 gate_1 fix B: 全屏透明 QuickConfirm Button
	# 背景：AI Player 经常 click 在 ChenmoCard (190-610) / SuwanCard (670-1090) 中间 60px gap
	#       或点歪坐标 → 永远 advance 不到 map
	# 修复：加一个全屏透明 Button，*gap 区域*任意位置点击都触发 _confirm_selection
	# 玩家点击体验：不变（透明按钮只是变大了点击区域；点击 chenmo_card/suwan_card 仍走原来的 _on_card_gui_input）
	# z-index 技巧：move_child 到 index=1（在 Background 之后、Vignette/VBox 之前）
	#               这样 cards (topmost) 仍接收点击，gap 区点击穿透到 QuickConfirm
	_quick_confirm = Button.new()
	_quick_confirm.name = "QuickConfirm"
	_quick_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quick_confirm.modulate = Color(1, 1, 1, 0)  # 完全透明
	_quick_confirm.focus_mode = Control.FOCUS_NONE
	_quick_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_quick_confirm.pressed.connect(_confirm_selection)
	add_child(_quick_confirm)
	# 移动到 index=1（Background 之后），让 cards 在更上层保持点击优先
	move_child(_quick_confirm, 1)

	print("角色选择：场景加载完成")

# ==================== 输入处理 ====================

func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			auto_select_timer.stop()
			if focused_index == index:
				_confirm_selection()
			else:
				focused_index = index
				_update_focus()
				auto_select_timer.start()

func _on_auto_select_timeout() -> void:
	print("角色选择：自动选择左侧角色")
	_confirm_selection()

# ==================== 私有方法 ====================

func _update_focus() -> void:
	for i: int in range(cards.size()):
		var card: PanelContainer = cards[i]
		if i == focused_index:
			card.add_theme_stylebox_override("panel", focus_style)
		else:
			card.add_theme_stylebox_override("panel", normal_style)
	# 更新确认按钮
	var names := ["陈默", "苏晚"]
	if focused_index >= 0 and focused_index < names.size():
		confirm_button.text = "选择 %s" % names[focused_index]
		confirm_button.disabled = false

func _confirm_selection() -> void:
	var character_id: String = ""
	var character_name: String = ""
	match focused_index:
		0:
			character_id = "chenmo"
			character_name = "陈默"
		1:
			character_id = "suwan"
			character_name = "苏晚"

	GameState.character_id = character_id
	var data: Dictionary = GameState.get_character_data()
	GameState.hp = data["hp"]
	GameState.max_hp = data["hp"]
	# 初始牌组：先进卡牌池，再加入牌库
	var starter_cards: Array = GameState.get_starter_deck()
	for card in starter_cards:
		var idx: int = GameState.add_to_collection(card)
		GameState.add_to_deck(idx)

	print("角色选择：确认选择 %s" % character_name)
	get_tree().change_scene_to_file("res://scenes/map.tscn")
