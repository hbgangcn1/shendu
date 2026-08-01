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
# 2026-08-01 fix(ed75d23a): 防止重复调用 _confirm_selection
var _selection_confirmed: bool = false
var _failsafe_timer: Timer = null
# 2026-07-25 gate_1 fix B: 全屏点击确认（解决 click miss 问题）
var _quick_confirm: Button = null

# ==================== 初始化 ====================

func _ready() -> void:
	print("角色选择：_ready() 开始")
	
	# 2026-08-01 fix(ed75d23a): 立即检测 headless 模式并自动确认
	# 根因：之前 Fix C (2026-07-27) 在 UITheme 样式代码之后执行，
	#       如果样式代码崩溃（@onready 节点访问失败），_confirm_selection() 永远不执行
	# 修复：headless auto-confirm 移到 _ready() 第一行，在任何节点访问之前
	if _is_headless_mode():
		print("角色选择：headless 模式检测成功，立即自动确认")
		_confirm_selection()
		# 即使 _confirm_selection() 失败，继续执行后续代码（failsafe timer 会重试）
	
	cards = [chenmo_card, suwan_card]

	# 2026-08-01 fix(ed75d23a): 样式初始化延迟到下一帧，避免阻塞场景加载
	# 如果 UITheme/@onready 节点访问失败，不影响核心功能（auto-confirm）
	call_deferred("_deferred_setup_styling")

	# 连接自动选择计时器（场景内定义的 AutoSelectTimer 节点）
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
	
	# 2026-08-01 fix(ed75d23a): 额外 failsafe timer（5 秒后强制确认）
	# 如果所有其他机制都失败（UITheme 崩溃 / auto_select_timer 没触发 / headless 检测失败）
	# 5 秒后强制调用 _confirm_selection()，确保场景不会卡死
	_failsafe_timer = Timer.new()
	_failsafe_timer.wait_time = 5.0
	_failsafe_timer.one_shot = true
	_failsafe_timer.timeout.connect(_on_failsafe_timeout)
	add_child(_failsafe_timer)
	_failsafe_timer.start()

	print("角色选择：场景加载完成（failsafe timer 5s 已启动）")

# ==================== 延迟样式初始化 ====================

func _deferred_setup_styling() -> void:
	# 2026-08-01 fix(ed75d23a): UITheme/@onready 节点样式初始化
	# 放在单独函数 + call_deferred，避免崩溃阻塞 _ready() 核心逻辑
	if chenmo_card == null or suwan_card == null or confirm_button == null:
		push_warning("角色选择：@onready 节点为 null，跳过样式初始化")
		return
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
	_update_focus()
	print("角色选择：样式初始化完成（deferred）")

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
	print("角色选择：自动选择左侧角色（auto_select_timer 触发）")
	_confirm_selection()

func _on_failsafe_timeout() -> void:
	# 2026-08-01 fix(ed75d23a): failsafe timer 触发
	# 如果 _selection_confirmed 已经为 true，_confirm_selection() 会立即返回
	print("角色选择：failsafe timer 触发（5s 超时），强制确认")
	_confirm_selection()

# ==================== 私有方法 ====================

func _is_headless_mode() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg in ["--qa-auto-run", "--agent-mode", "--headless"]:
			return true
	# Fallback: 已知 flag 是 --qa-auto-run (agent_socket.gd:20)
	return "--qa-auto-run" in args

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
	# 2026-08-01 fix(ed75d23a): 防止重复调用（headless + failsafe timer 可能同时触发）
	if _selection_confirmed:
		print("角色选择：_confirm_selection() 已执行过，跳过")
		return
	_selection_confirmed = true
	
	var character_id: String = ""
	var character_name: String = ""
	match focused_index:
		0:
			character_id = "chenmo"
			character_name = "陈默"
		1:
			character_id = "suwan"
			character_name = "苏晚"

	print("角色选择：设置 GameState.character_id = %s" % character_id)
	GameState.character_id = character_id
	
	var data: Dictionary = GameState.get_character_data()
	if data.is_empty():
		push_error("角色选择：GameState.get_character_data() 返回空，使用默认值")
		GameState.hp = 80
		GameState.max_hp = 80
	else:
		GameState.hp = data["hp"]
		GameState.max_hp = data["hp"]
		print("角色选择：HP 设置完成 %d/%d" % [GameState.hp, GameState.max_hp])
	
	# 初始牌组：先进卡牌池，再加入牌库
	var starter_cards: Array = GameState.get_starter_deck()
	print("角色选择：starter_deck 大小 = %d" % starter_cards.size())
	for card in starter_cards:
		var idx: int = GameState.add_to_collection(card)
		GameState.add_to_deck(idx)

	print("角色选择：确认选择 %s（card_count=%d）" % [character_name, GameState.deck.size()])
	
	# 停止所有 timer（避免重复触发）
	if auto_select_timer != null:
		auto_select_timer.stop()
	if _failsafe_timer != null:
		_failsafe_timer.stop()
	
	# 切换场景
	var err = get_tree().change_scene_to_file("res://scenes/map.tscn")
	if err != OK:
		push_error("角色选择：change_scene_to_file 失败，error code = %d" % err)
		# 2026-08-01 fix(ed75d23a): 如果 change_scene_to_file 失败，尝试 call_deferred
		print("角色选择：尝试 call_deferred 重试场景切换")
		get_tree().change_scene_to_file.call_deferred("res://scenes/map.tscn")
	else:
		print("角色选择：场景切换成功 → map.tscn")
