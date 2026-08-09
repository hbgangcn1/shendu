# implements: design/09-map-system-spec.md
# implements_philosophy: rule_3_three_layer_loops
# avoids_red_line: red_7_difficulty_wall

class_name GameMapScene
extends Control

const _MapNodeScript = preload("res://scripts/core/map_node.gd")
const NodeType = _MapNodeScript.NodeType

# ==================== 常量 ====================

const NODE_TYPE_TEXTURES: Dictionary = {
	NodeType.COMBAT: "res://assets/images/ui/map_nodes/map_node_combat_001.png",
	NodeType.ELITE: "res://assets/images/ui/map_nodes/map_node_elite_001.png",
	NodeType.EVENT: "res://assets/images/ui/map_nodes/map_node_event_001.png",
	NodeType.SHOP: "res://assets/images/ui/map_nodes/map_node_shop_001.png",
	NodeType.REST: "res://assets/images/ui/map_nodes/map_node_rest_001.png",
	NodeType.BOSS: "res://assets/images/ui/map_nodes/map_node_boss_001.png",
	NodeType.SECRET_ROOM: "res://assets/images/ui/map_nodes/map_node_secret_001.png",
}

const NODE_TYPE_COLORS: Dictionary = {
	NodeType.COMBAT: Color(0.9, 0.2, 0.2),
	NodeType.ELITE: Color(0.6, 0.1, 0.1),
	NodeType.EVENT: Color(0.7, 0.3, 0.9),
	NodeType.SHOP: Color(0.3, 0.5, 0.9),
	NodeType.REST: Color(0.3, 0.8, 0.4),
	NodeType.BOSS: Color(0.9, 0.8, 0.2),
	NodeType.SECRET_ROOM: Color(0.5, 0.3, 0.7),
}

const MAP_CENTER_X: float = 960.0  ## 地图中心 X（屏幕中心 1920/2）
const COLUMN_SPACING: float = 213.0
const COLUMN_START_Y: float = 280.0  ## 第一列起始 Y
const MAX_NODE_SPREAD: float = 380.0  ## 节点在同一列内最大纵向展开
const NODE_SIZE: float = 88.0

## 三级路径颜色（已通过 / 可到达 / 未解锁）
const PATH_COLOR_VISITED := Color(1.0, 1.0, 1.0, 0.85)  ## 白实线
const PATH_COLOR_REACHABLE := Color(0.0, 1.0, 0.8, 0.7)  ## 青虚线
const PATH_COLOR_LOCKED := Color(0.3, 0.3, 0.4, 0.5)    ## 暗灰

# ==================== 节点引用 ====================

@onready var realm_label: Label = %RealmLabel
@onready var hp_label: Label = %HPLabel
@onready var spirit_stones_label: Label = %SpiritStonesLabel
@onready var dao_xing_label: Label = %DaoXingLabel
@onready var lines_container: Node2D = %LinesContainer
@onready var nodes_container: Control = %NodesContainer
@onready var confirmation_panel: PanelContainer = %ConfirmationPanel
@onready var confirm_type_label: Label = %ConfirmTypeLabel
@onready var confirm_go_button: Button = %ConfirmGoButton
@onready var confirm_cancel_button: Button = %ConfirmCancelButton
@onready var not_impl_popup: PanelContainer = %NotImplPopup
@onready var not_impl_label: Label = %NotImplLabel
@onready var not_impl_close_button: Button = %NotImplCloseButton
@onready var move_hint_panel: PanelContainer = %MoveHintPanel
@onready var move_hint_label: Label = %MoveHintLabel
@onready var legend_panel: PanelContainer = %LegendPanel
@onready var legend_toggle_button: Button = %LegendToggleButton

# ==================== 休息/事件 UI ====================

var _rest_popup: PanelContainer = null
var _event_popup: PanelContainer = null
var _event_logic = null
var _current_event = null
var _move_hint_tween: Tween = null

# ==================== 状态 ====================

var _realm_map = null
var _node_ui_map: Dictionary = {}  ## id -> PanelContainer
var _selected_node = null
var _deck_view_open: bool = false  ## 牌组界面是否已打开

# ==================== 生命周期 ====================

func _ready() -> void:
	_generate_map()
	_update_top_bar()
	_draw_map()
	_update_reachable()
	# 2026-08-06 方案 D 完成：update_reachable 后 export map layout（让 minimax 看到节点结构）
	# game_state.gd.export_map_layout_for_ai_player() 读 game_map.realms[current_realm]
	# 写 {columns, stats, decision_hints} 到 user:// + workspace 镜像。
	# ai_player_client.py DirectRouter 读这个文件、压成 minimax 友好 markdown、
	# 注入 _fill_prompt 的 {map_layout} 替换。AI Player 不再只看像素视觉，
	# 能直接选"5 个可达节点里 3 个是 COMBAT 1 个 REST 1 个 SHOP"而不是猜图标。
	# trigger：每次进 map scene 都重写（_ready 频繁被叫 → write overwrite，小 file 几 ms）。
	var map_layout: Dictionary = GameState.export_map_layout_for_ai_player()
	GameState.save_map_layout_to_disk(map_layout)
	_connect_signals()
	_add_deck_button()
	_add_menu_button()
	confirmation_panel.z_index = 50
	not_impl_popup.z_index = 50
	_show_move_hint()

	# 应用主题到确认弹窗
	UITheme.apply_panel(confirmation_panel)
	UITheme.apply_body_label(confirm_type_label, 16)
	var go_btn: Button = confirmation_panel.get_node_or_null("VBoxContainer/ConfirmGoButton")
	var cancel_btn: Button = confirmation_panel.get_node_or_null("VBoxContainer/ConfirmCancelButton")
	if go_btn:
		UITheme.apply_button(go_btn)
	if cancel_btn:
		UITheme.apply_button(cancel_btn)

	print("地图场景：加载完成，当前境界 %s" % GameState.get_realm_name())

# ==================== 事件处理 ====================

func _on_node_gui_input(event: InputEvent, node) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if node.is_reachable and not GameState.visited_node_ids.has(node.id):
				_show_confirmation(node)

func _on_confirm_go() -> void:
	if _selected_node == null:
		return

	GameState.current_node_id = _selected_node.id
	if not GameState.visited_node_ids.has(_selected_node.id):
		GameState.visited_node_ids.append(_selected_node.id)
	_selected_node.is_visited = true

	print("地图场景：前往 %s" % _selected_node.get_type_name())

	match _selected_node.type:
		NodeType.COMBAT, NodeType.ELITE, NodeType.BOSS:
			# 2026-07-31 fix: 真实战斗应该去 battle.tscn (6661 字节 + 战斗逻辑)
			# battle_demo.tscn (348 字节) 是 dev/test scene，不能让 AI Player 陷进去
			# 7/30 之前用了 battle_demo 可能因为 battle.tscn 还没准备好
			# commit 7/30 a555a1b 跳过 BattleDemo 是 workaround，但根本没用 — 还是 trigger
			# 这里直接跳到 battle.tscn
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
		NodeType.SHOP:
			get_tree().change_scene_to_file("res://scenes/shop.tscn")
		NodeType.REST:
			_hide_confirmation()
			_show_rest_ui()
			return
		NodeType.EVENT:
			_hide_confirmation()
			_show_event_ui()
			return
		_:
			_show_not_implemented(_selected_node.get_type_name())

	_hide_confirmation()

# ==================== 私有方法 ====================

func _generate_map() -> void:
	var realm_ids: Array[String] = ["liqi", "zhuji", "jindan"]
	var realm_index: int = mini(GameState.current_realm, realm_ids.size() - 1)
	var realm_id: String = realm_ids[realm_index]
	var MapGeneratorScript = load("res://scripts/core/map_generator.gd")
	var generator = MapGeneratorScript.new(42)
	_realm_map = generator.generate(realm_id, realm_index)

	# 保存到 GameState 供战斗场景使用（boss检测、节点类型查询）
	if GameState.game_map == null:
		var GameMapScript = load("res://scripts/core/game_map.gd")
		GameState.game_map = GameMapScript.new()
		GameState.game_map.initialize_all_realms(42)
	# 同步当前层的 RealmMap（保留 boss_node 等生成结果）
	GameState.game_map.realms[realm_index] = _realm_map
	GameState.game_map.current_realm_index = realm_index

	print("地图场景：生成地图 %s" % realm_id)

# ==================== HP 闪烁动画 ====================

var _hp_pulse_tween: Tween = null

func _update_top_bar() -> void:
	for label: Label in [realm_label, hp_label, spirit_stones_label, %DaoXingLabel]:
		UITheme.apply_body_label(label, 16)

	realm_label.text = "境界: %s" % GameState.get_realm_name()
	hp_label.text = "HP: %d/%d" % [GameState.hp, GameState.max_hp]
	spirit_stones_label.text = "灵石: %d" % GameState.spirit_stones
	dao_xing_label.text = "道行: %d" % GameState.dao_xing
	dao_xing_label.tooltip_text = "道行：击败敌人获得，后续版本可用于领悟技能、解锁天赋等。当前版本暂无消耗用途。"
	_update_hp_color()

## 2026-08-05 art_review fix (5069241b): HP<30% 时数字变红 + 1.5s 循环闪烁
## 闪烁频率不超过 1.5s/周期，避免癫痫风险（AI Player 建议）
func _update_hp_color() -> void:
	if GameState.max_hp <= 0:
		return
	var ratio: float = float(GameState.hp) / float(GameState.max_hp)
	if ratio < 0.3:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.15))
		if _hp_pulse_tween == null or not _hp_pulse_tween.is_valid():
			_hp_pulse_tween = create_tween().set_loops()
			_hp_pulse_tween.tween_property(hp_label, "modulate:a", 0.35, 0.75)
			_hp_pulse_tween.tween_property(hp_label, "modulate:a", 1.0, 0.75)
	else:
		hp_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		if _hp_pulse_tween != null and _hp_pulse_tween.is_valid():
			_hp_pulse_tween.kill()
		_hp_pulse_tween = null
		hp_label.modulate.a = 1.0

func _draw_map() -> void:
	for child: Node in nodes_container.get_children():
		child.queue_free()
	for child: Node in lines_container.get_children():
		child.queue_free()
	_node_ui_map.clear()

	for node in _realm_map.nodes:
		var from_pos: Vector2 = _get_node_position(node)
		for conn in node.connections:
			var to_pos: Vector2 = _get_node_position(conn)
			var line := Line2D.new()
			line.add_point(from_pos)
			line.add_point(to_pos)
			line.width = 3.0
			# 三级路径颜色：已通过=白实线 / 可到达=青虚线 / 未解锁=暗灰
			var both_visited: bool = GameState.visited_node_ids.has(node.id) and GameState.visited_node_ids.has(conn.id)
			if both_visited:
				line.default_color = PATH_COLOR_VISITED
				line.width = 3.0
			elif node.is_reachable or conn.is_reachable:
				line.default_color = PATH_COLOR_REACHABLE
				line.width = 2.0
			else:
				line.default_color = PATH_COLOR_LOCKED
				line.width = 1.0
			line.z_index = 0
			lines_container.add_child(line)

	for node in _realm_map.nodes:
		var pos: Vector2 = _get_node_position(node)
		var panel := PanelContainer.new()
		panel.position = pos - Vector2(NODE_SIZE / 2.0, NODE_SIZE / 2.0)
		panel.z_index = 5
		panel.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
		panel.size = Vector2(NODE_SIZE, NODE_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var texture_path: String = NODE_TYPE_TEXTURES.get(node.type, "")
		var icon_rect := TextureRect.new()
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(NODE_SIZE - 8, NODE_SIZE - 8)
		icon_rect.size = Vector2(NODE_SIZE - 8, NODE_SIZE - 8)
		icon_rect.position = Vector2(4, 4)
		if texture_path != "" and ResourceLoader.exists(texture_path):
			icon_rect.texture = load(texture_path)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS

		panel.add_child(icon_rect)
		panel.gui_input.connect(_on_node_gui_input.bind(node))
		nodes_container.add_child(panel)
		_node_ui_map[node.id] = panel
		# 2026-08-09 P0 #2 (epic-rollup-35e824f6): register hover tooltip
		NodeTooltip.register(panel, node.type, 0, node.metadata)

func _get_node_position(node) -> Vector2:
	# 水平居中：所有列宽之和以 MAP_CENTER_X 为中心展开
	var max_col: int = 0
	for n in _realm_map.nodes:
		if n.column > max_col:
			max_col = n.column
	var map_width: float = max_col * COLUMN_SPACING
	var offset_x: float = MAP_CENTER_X - map_width / 2.0

	var x: float = offset_x + node.column * COLUMN_SPACING
	var col_nodes: Array = _realm_map.columns[node.column]
	var node_count: int = col_nodes.size()
	var y: float
	if node_count <= 1:
		y = COLUMN_START_Y + MAX_NODE_SPREAD / 2.0
	else:
		var total_height: float = min(node_count * 120.0, MAX_NODE_SPREAD)
		var spacing: float = total_height / (node_count - 1)
		var idx: int = col_nodes.find(node)
		y = COLUMN_START_Y + (MAX_NODE_SPREAD - total_height) / 2.0 + idx * spacing
	return Vector2(x, y)

func _update_reachable() -> void:
	for node in _realm_map.nodes:
		node.is_reachable = false

	if GameState.visited_node_ids.is_empty():
		for node in _realm_map.get_start_nodes():
			node.is_reachable = true
	else:
		for node in _realm_map.nodes:
			if GameState.visited_node_ids.has(node.id):
				for conn in node.connections:
					conn.is_reachable = true

	_update_node_visuals()

func _update_node_visuals() -> void:
	for node in _realm_map.nodes:
		var panel = _node_ui_map.get(node.id)
		if panel == null:
			continue

		var is_visited: bool = GameState.visited_node_ids.has(node.id)
		var is_reachable: bool = node.is_reachable

		# 修复 AI Player 反馈 (2026-07-14) "在第一层地图节点 0 上卡了 8 秒没反应，UI 显示可点击但没效果"
		# 原因：visited 节点和 unreachable 节点仍接收 gui_input 但被 silently ignore
		# 修复：visited/unreachable 节点 mouse_filter = IGNORE，点击直接穿透，让玩家感知到"不可点击"
		if is_visited or not is_reachable:
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var base_color: Color = NODE_TYPE_COLORS.get(node.type, Color.GRAY)

		var style := UITheme.panel_style.duplicate()
		style.set_corner_radius_all(12)

		var icon_rect = panel.get_child(0)
		var modulate_color := Color(1, 1, 1, 1)
		if is_visited:
			style.bg_color = Color(base_color.r * 0.3, base_color.g * 0.3, base_color.b * 0.3)
			style.border_color = Color(base_color, 0.3)
			modulate_color = Color(0.5, 0.5, 0.5, 0.5)
		elif is_reachable:
			style.bg_color = Color(base_color.r * 0.6, base_color.g * 0.6, base_color.b * 0.6, 0.8)
			style.border_color = Color(base_color, 0.8)
			style.shadow_color = Color(base_color, 0.4)
			style.shadow_size = 6
			modulate_color = Color(1, 1, 1, 1)
		else:
			style.bg_color = Color(0.15, 0.15, 0.18)
			style.border_color = Color(0.3, 0.3, 0.35)
			modulate_color = Color(0.3, 0.3, 0.3, 0.6)
		if icon_rect is TextureRect:
			icon_rect.modulate = modulate_color

		panel.add_theme_stylebox_override("panel", style)

func _show_confirmation(node) -> void:
	_selected_node = node
	confirm_type_label.text = "%s\n前往此处？" % node.get_type_name()
	# 确认弹窗边框颜色匹配节点类型
	var node_color: Color = NODE_TYPE_COLORS.get(node.type, UITheme.CYAN_NEON)
	var conf_style := UITheme.panel_style.duplicate()
	conf_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	conf_style.border_color = node_color
	conf_style.set_content_margin_all(16)
	confirmation_panel.add_theme_stylebox_override("panel", conf_style)
	confirmation_panel.visible = true

func _hide_confirmation() -> void:
	confirmation_panel.visible = false
	_selected_node = null

func _show_not_implemented(type_name: String) -> void:
	not_impl_label.text = "%s 未实现" % type_name
	not_impl_popup.visible = true

func _hide_not_implemented() -> void:
	not_impl_popup.visible = false

# ==================== 移动教程提示 ====================

## 2026-08-09 design_concern fix (ff762f56):
## AI Player 在第一个 tick 完全不知所措（25+ 节点 + 不知道点击是否移动）。
## 修复：visited_node_ids 为空时显示 3 秒浮动提示"点击相邻节点移动"，
## 并对首个可达节点做 scale 脉冲引导玩家点击。一旦玩家移动后不再显示。
func _show_move_hint() -> void:
	if move_hint_panel == null or move_hint_label == null:
		return

	# 玩家已经移动过 → 不再显示新手引导
	if not GameState.visited_node_ids.is_empty():
		move_hint_panel.visible = false
		return

	move_hint_panel.visible = true
	move_hint_label.modulate.a = 1.0

	# 浮动 + 淡出（约 3 秒总时长：保持 2.5s 后 0.6s 淡出）
	if _move_hint_tween != null and _move_hint_tween.is_valid():
		_move_hint_tween.kill()
	_move_hint_tween = create_tween()
	_move_hint_tween.tween_interval(2.5)
	_move_hint_tween.tween_property(move_hint_label, "modulate:a", 0.0, 0.6)
	_move_hint_tween.tween_callback(func():
		if is_instance_valid(move_hint_panel):
			move_hint_panel.visible = false
	)

	# 脉冲首个可达节点，引导玩家点击（scale 1.0→1.25→1.0，循环 2 次）
	var first_node = null
	for node in _realm_map.nodes:
		if node.is_reachable and not GameState.visited_node_ids.has(node.id):
			first_node = node
			break
	if first_node != null:
		var panel = _node_ui_map.get(first_node.id)
		if panel != null:
			_pulse_first_node(panel)

func _pulse_first_node(panel: PanelContainer) -> void:
	var pulse := create_tween().set_loops(2)
	pulse.tween_property(panel, "scale", Vector2(1.25, 1.25), 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pulse.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# ==================== 休息节点 UI ====================

func _show_rest_ui() -> void:
	if _rest_popup != null:
		_rest_popup.queue_free()

	# 获取休息节点参数
	var heal_pct: float = 0.3
	var cleanse_amt: int = 2
	if _selected_node and _selected_node.metadata.has("heal_percent"):
		heal_pct = _selected_node.metadata["heal_percent"]
	if _selected_node and _selected_node.metadata.has("cleanse_amount"):
		cleanse_amt = _selected_node.metadata["cleanse_amount"]

	var heal_amount: int = floori(GameState.max_hp * heal_pct)

	# 创建弹窗
	_rest_popup = PanelContainer.new()
	_rest_popup.z_index = 200
	_rest_popup.set_anchors_preset(Control.PRESET_CENTER)
	_rest_popup.offset_left = -266
	_rest_popup.offset_right = 266
	_rest_popup.offset_top = -200
	_rest_popup.offset_bottom = 200

	var style := UITheme.panel_style.duplicate()
	style.bg_color = Color(0.08, 0.12, 0.08, 0.95)
	style.border_color = UITheme.ELEM_WOOD_GLOW
	style.set_content_margin_all(20)
	_rest_popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "休息节点"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title_label(title, 22)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "灵气环绕的庇护所。选择一项恢复："
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_secondary_label(desc, 14)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	var heal_btn := Button.new()
	heal_btn.text = "吐纳 — 回复 %d HP（%d%%）" % [heal_amount, int(heal_pct * 100)]
	heal_btn.custom_minimum_size = Vector2(400, 53)
	UITheme.apply_button(heal_btn)
	heal_btn.pressed.connect(_on_rest_heal.bind(heal_amount))
	vbox.add_child(heal_btn)

	var cleanse_btn := Button.new()
	cleanse_btn.text = "净化 — 清除 %d 层魔念" % cleanse_amt
	cleanse_btn.custom_minimum_size = Vector2(400, 53)
	UITheme.apply_button(cleanse_btn)
	cleanse_btn.pressed.connect(_on_rest_cleanse.bind(cleanse_amt))
	vbox.add_child(cleanse_btn)

	var skip_btn := Button.new()
	skip_btn.text = "跳过"
	UITheme.apply_button(skip_btn)
	skip_btn.pressed.connect(_on_rest_skip)
	vbox.add_child(skip_btn)

	_rest_popup.add_child(vbox)
	add_child(_rest_popup)

func _on_rest_heal(amount: int) -> void:
	var old_hp: int = GameState.hp
	GameState.hp = mini(GameState.max_hp, GameState.hp + amount)
	print("休息：吐纳回复 %d HP (%d → %d)" % [amount, old_hp, GameState.hp])
	_close_rest_ui()

func _on_rest_cleanse(amount: int) -> void:
	var old_mo: int = GameState.mo_nian
	GameState.mo_nian = maxi(0, GameState.mo_nian - amount)
	print("休息：净化魔念 %d (%d → %d)" % [amount, old_mo, GameState.mo_nian])
	_close_rest_ui()

func _on_rest_skip() -> void:
	print("休息：跳过")
	_close_rest_ui()

func _close_rest_ui() -> void:
	if _rest_popup:
		_rest_popup.queue_free()
		_rest_popup = null
	_update_top_bar()
	_update_reachable()

# ==================== 事件节点 UI ====================

func _show_event_ui() -> void:
	if _event_popup != null:
		_event_popup.queue_free()

	# 初始化事件逻辑
	if _event_logic == null:
		var EventLogicScript = preload("res://scripts/core/event_logic.gd")
		_event_logic = EventLogicScript.new(42)
		# 加载事件数据
		var events_file := FileAccess.open("res://data/events/events.json", FileAccess.READ)
		if events_file:
			var json := JSON.new()
			var parse_result := json.parse(events_file.get_as_text())
			if parse_result == OK:
				_event_logic.load_events(json.data)
				print("事件系统：加载了 %d 个事件" % json.data.size())
			else:
				print("事件系统：JSON 解析失败")
		else:
			print("事件系统：无法打开 events.json")

	# 生成事件
	var realm_ids: Array[String] = ["liqi", "zhuji", "jindan"]
	var realm_id: String = realm_ids[mini(GameState.current_realm, 2)]
	var player_state := {
		"hp": GameState.hp,
		"max_hp": GameState.max_hp,
		"spirit_stones": GameState.spirit_stones,
		"dao_xing": GameState.dao_xing,
		"mo_nian": GameState.mo_nian,
	}
	_current_event = _event_logic.generate_event(realm_id, player_state)

	if _current_event == null:
		_show_not_implemented("事件")
		return

	# 创建弹窗
	_event_popup = PanelContainer.new()
	_event_popup.z_index = 200
	_event_popup.set_anchors_preset(Control.PRESET_CENTER)
	_event_popup.offset_left = -373
	_event_popup.offset_right = 373
	_event_popup.offset_top = -266
	_event_popup.offset_bottom = 266

	var style := UITheme.panel_style.duplicate()
	style.bg_color = Color(0.08, 0.06, 0.14, 0.95)
	style.border_color = UITheme.CYAN_NEON
	style.set_content_margin_all(20)
	_event_popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "%s" % _current_event.name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title_label(title, 20)
	vbox.add_child(title)

	var desc := RichTextLabel.new()
	desc.text = _current_event.description
	desc.fit_content = true
	desc.custom_minimum_size = Vector2(666, 80)
	desc.add_theme_font_size_override("normal_font_size", 19)
	desc.add_theme_color_override("default_color", UITheme.TEXT_PRIMARY)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	for i in range(_current_event.choices.size()):
		var choice = _current_event.choices[i]
		var btn := Button.new()
		btn.text = choice.text
		btn.custom_minimum_size = Vector2(533, 48)
		UITheme.apply_button(btn)
		btn.pressed.connect(_on_event_choice.bind(i))
		vbox.add_child(btn)

	var leave_btn := Button.new()
	leave_btn.text = "离开"
	UITheme.apply_button(leave_btn)
	leave_btn.pressed.connect(_close_event_ui)
	vbox.add_child(leave_btn)

	_event_popup.add_child(vbox)
	add_child(_event_popup)

func _on_event_choice(choice_index: int) -> void:
	if _current_event == null:
		return

	var player_state := {
		"hp": GameState.hp,
		"max_hp": GameState.max_hp,
		"spirit_stones": GameState.spirit_stones,
		"dao_xing": GameState.dao_xing,
		"mo_nian": GameState.mo_nian,
	}

	var result: Dictionary = _event_logic.execute_choice(_current_event, choice_index, player_state)

	# 同步回 GameState
	GameState.hp = player_state.get("hp", GameState.hp)
	GameState.max_hp = player_state.get("max_hp", GameState.max_hp)
	GameState.spirit_stones = player_state.get("spirit_stones", GameState.spirit_stones)
	GameState.dao_xing = player_state.get("dao_xing", GameState.dao_xing)
	GameState.mo_nian = player_state.get("mo_nian", GameState.mo_nian)

	var msg: String = result.get("summary", "事件完成")
	print("事件：%s — %s" % [_current_event.name, msg])

	_current_event = null
	_close_event_ui()

func _close_event_ui() -> void:
	if _event_popup:
		_event_popup.queue_free()
		_event_popup = null
	_update_top_bar()
	_update_reachable()

func _connect_signals() -> void:
	confirm_go_button.pressed.connect(_on_confirm_go)
	confirm_cancel_button.pressed.connect(_hide_confirmation)
	not_impl_close_button.pressed.connect(_hide_not_implemented)
	# 2026-08-09 P0 #2: legend toggle button
	legend_toggle_button.pressed.connect(_on_legend_toggle_pressed)


func _unhandled_input(event: InputEvent) -> void:
	# 2026-08-09 P0 #2: L 键切换 legend panel
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_L:
			_toggle_legend()
			get_viewport().set_input_as_handled()


func _on_legend_toggle_pressed() -> void:
	_toggle_legend()


func _toggle_legend() -> void:
	if legend_panel == null:
		return
	legend_panel.visible = not legend_panel.visible

# ==================== 牌组查看 ====================

const DeckViewScene := preload("res://scripts/ui/deck_view.gd")
const ConfirmDialogScene := preload("res://scenes/confirm_dialog.tscn")

func _add_deck_button() -> void:
	var deck_btn := Button.new()
	deck_btn.name = "DeckButton"
	deck_btn.text = "牌组 %d/%d" % [GameState.deck.size(), GameState.deck_max_size]
	deck_btn.add_theme_font_size_override("font_size", 19)
	deck_btn.custom_minimum_size = Vector2(160, 48)
	deck_btn.position = Vector2(1080 - 140, 10)
	deck_btn.z_index = 100
	deck_btn.pressed.connect(_on_deck_button_pressed)
	add_child(deck_btn)

## 右上角菜单按钮（Robert 反馈 地图无退出入口）
func _add_menu_button() -> void:
	var menu_btn := Button.new()
	menu_btn.name = "MenuButton"
	menu_btn.text = "≡"
	menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.custom_minimum_size = Vector2(56, 48)
	menu_btn.position = Vector2(1820, 10)
	menu_btn.z_index = 100
	menu_btn.pressed.connect(_on_menu_button_pressed)
	add_child(menu_btn)

func _on_menu_button_pressed() -> void:
	# 使用通用确认弹窗（继续/退出主菜单）
	var dlg: Control = ConfirmDialogScene.instantiate()
	dlg.z_index = 200
	dlg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dlg.offset_left = -260
	dlg.offset_right = 260
	dlg.offset_top = -150
	dlg.offset_bottom = 150
	add_child(dlg)
	dlg.setup("暂停菜单", "选择操作", "继续", "退出主菜单")
	dlg.confirmed.connect(_on_menu_continue)
	dlg.cancelled.connect(_on_menu_exit)

func _on_menu_continue() -> void:
	pass  # 继续游戏（关闭弹窗即继续）

func _on_menu_exit() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_deck_button_pressed() -> void:
	if _deck_view_open:
		return
	_deck_view_open = true
	var deck_view: Control = DeckViewScene.new()
	deck_view.name = "DeckView"
	deck_view.z_index = 100
	deck_view.anchor_left = 0.0
	deck_view.anchor_top = 0.0
	deck_view.anchor_right = 1.0
	deck_view.anchor_bottom = 1.0
	deck_view.offset_left = 0.0
	deck_view.offset_top = 0.0
	deck_view.offset_right = 0.0
	deck_view.offset_bottom = 0.0
	add_child(deck_view)
	deck_view.tree_exited.connect(func(): _deck_view_open = false)
	deck_view.tree_exited.connect(func(): _deck_view_open = false)
