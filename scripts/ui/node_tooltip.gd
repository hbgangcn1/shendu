## 蜃都节点 tooltip 系统
## Autoload: NodeTooltip
##
## 注册 Control panel → 显示节点类型中文 tooltip
## 自动 hover 触发，无需手动连接信号
##
## 2026-08-09 实现 (P0 #2 节点 tooltip + legend — epic-rollup-35e824f6)
## 覆盖 workboard cards: 64f66065, 312b2ae4, 755bad39, b35b8cf1 + ~10 normal
## 设计文档: design/09-map-system-spec.md (rule_3_three_layer_loops)

extends Node

const MapNodeScript = preload("res://scripts/core/map_node.gd")
const NodeType = MapNodeScript.NodeType

# ==================== 节点类型 → tooltip 数据 ====================
## icon 用 Unicode emoji / 符号 — 无需额外素材，立即可用
## desc 中文短描述，影响玩家决策（不超过 30 字）
const TOOLTIP_DATA := {
	NodeType.COMBAT: {
		"title": "战斗",
		"color": Color(0.9, 0.2, 0.2),
		"icon": "⚔",
		"desc": "普通战斗。掉灵石/卡牌。",
	},
	NodeType.ELITE: {
		"title": "精英",
		"color": Color(0.6, 0.1, 0.1),
		"icon": "☠",
		"desc": "精英 Boss。高风险高回报，掉稀有遗物。",
	},
	NodeType.EVENT: {
		"title": "事件",
		"color": Color(0.7, 0.3, 0.9),
		"icon": "?",
		"desc": "神秘事件（商人/诅咒/祝福）。后果难测。",
	},
	NodeType.SHOP: {
		"title": "商店",
		"color": Color(0.3, 0.5, 0.9),
		"icon": "¥",
		"desc": "灵石商店。买卡牌/遗物/回 HP。",
	},
	NodeType.REST: {
		"title": "休息",
		"color": Color(0.3, 0.8, 0.4),
		"icon": "☯",
		"desc": "灵气庇护所。回 HP 或净化魔念。",
	},
	NodeType.BOSS: {
		"title": "Boss",
		"color": Color(0.9, 0.8, 0.2),
		"icon": "👑",
		"desc": "Boss 关底。击败后进入下一境界。",
	},
	NodeType.SECRET_ROOM: {
		"title": "秘境",
		"color": Color(0.5, 0.3, 0.7),
		"icon": "★",
		"desc": "隐藏秘境。稀有奖励，可能付出代价。",
	},
}

# ==================== 内部状态 ====================
var _canvas: CanvasLayer = null
var _tooltip_panel: PanelContainer = null
var _tooltip_label: RichTextLabel = null
var _registry: Dictionary = {}  ## panel -> { type, difficulty, metadata }


func _ready() -> void:
	_create_tooltip()
	# call_deferred 让 root scene 先 ready，避免 null tree
	call_deferred("_attach_to_root")


func _create_tooltip() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 100  # 在所有 UI 之上（包括 popup）

	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 1000
	_canvas.add_child(_tooltip_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = UITheme.CYAN_NEON
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 8
	style.shadow_offset = Vector2(2, 2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_tooltip_panel.add_theme_stylebox_override("panel", style)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.custom_minimum_size = Vector2(280, 0)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.add_theme_font_size_override("normal_font_size", 16)
	_tooltip_label.add_theme_color_override("default_color", UITheme.TEXT_PRIMARY)
	_tooltip_panel.add_child(_tooltip_label)


func _attach_to_root() -> void:
	if _canvas.get_parent() == null and get_tree() != null:
		get_tree().root.add_child(_canvas)


# ==================== 公开 API ====================

## 注册节点 panel → 自动 hover 显示 tooltip
## panel: Control（如 PanelContainer / TextureRect / Button）
## node_type: NodeType 枚举值
## difficulty: 0=普通, 1=精英, 2=Boss（影响 desc 中的"敌人等级"）
## metadata: 附加信息（如 enemy_level, heal_percent 等）
func register(panel: Control, node_type: int, difficulty: int = 0, metadata: Dictionary = {}) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	_registry[panel] = {
		"type": node_type,
		"difficulty": difficulty,
		"metadata": metadata,
	}
	# connect signals（一次即可）
	if not panel.mouse_entered.is_connected(_on_panel_mouse_entered):
		panel.mouse_entered.connect(_on_panel_mouse_entered.bind(panel))
	if not panel.mouse_exited.is_connected(_on_panel_mouse_exited):
		panel.mouse_exited.connect(_on_panel_mouse_exited.bind(panel))


## 取消注册 panel（节点销毁时调用，避免泄漏）
func unregister(panel: Control) -> void:
	if panel == null:
		return
	_registry.erase(panel)
	if is_instance_valid(panel):
		if panel.mouse_entered.is_connected(_on_panel_mouse_entered):
			panel.mouse_entered.disconnect(_on_panel_mouse_entered)
		if panel.mouse_exited.is_connected(_on_panel_mouse_exited):
			panel.mouse_exited.disconnect(_on_panel_mouse_exited)


## 强制隐藏 tooltip（场景切换等）
func hide() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


# ==================== 信号回调 ====================

func _on_panel_mouse_entered(panel: Control) -> void:
	if not _registry.has(panel):
		return
	_show_for(panel)


func _on_panel_mouse_exited(_panel: Control) -> void:
	hide()


# ==================== 内部实现 ====================

func _show_for(panel: Control) -> void:
	var data: Dictionary = _registry.get(panel, {})
	var node_type: int = data.get("type", -1)
	if node_type < 0 or not TOOLTIP_DATA.has(node_type):
		return

	var info: Dictionary = TOOLTIP_DATA[node_type]
	var title: String = info["title"]
	var color: Color = info["color"]
	var icon: String = info["icon"]
	var desc: String = info["desc"]

	# 根据 metadata 调整 desc（让 tooltip 数据驱动，更智能）
	var metadata: Dictionary = data.get("metadata", {})
	if node_type == NodeType.COMBAT and metadata.has("enemy_level"):
		desc = "预计敌人等级 %d。掉灵石/卡牌。" % int(metadata["enemy_level"])
	elif node_type == NodeType.ELITE and metadata.has("elite_level"):
		desc = "精英 Boss（等级 %d）。高风险，掉稀有遗物。" % int(metadata["elite_level"])
	elif node_type == NodeType.REST and metadata.has("heal_percent"):
		var pct: int = int(float(metadata["heal_percent"]) * 100)
		desc = "灵气庇护所。回 %d%% HP 或净化魔念。" % pct

	# BBCode 格式化（彩色标题 + 白色描述）
	var color_hex: String = color.to_html(true)
	var bbcode: String = "[color=#%s][b]%s %s[/b][/color]\n\n[color=#%s]%s[/color]" % [
		color_hex, icon, title,
		UITheme.TEXT_PRIMARY.to_html(true), desc,
	]
	_tooltip_label.text = bbcode

	# 定位到 panel 右侧
	var panel_global_pos: Vector2 = panel.global_position
	var panel_size: Vector2 = panel.size
	var tooltip_pos: Vector2 = panel_global_pos + Vector2(panel_size.x + 12, 0)

	# 防止溢出屏幕（左右 + 上下）
	var viewport_size: Vector2 = Vector2(1920, 1080)  # 默认 viewport 大小
	if get_viewport() != null:
		viewport_size = get_viewport().get_visible_rect().size

	var tooltip_size: Vector2 = Vector2(300, 100)  # 估算大小
	# 右侧溢出 → 显示在 panel 左侧
	if tooltip_pos.x + tooltip_size.x > viewport_size.x:
		tooltip_pos.x = panel_global_pos.x - tooltip_size.x - 12
	# 左边溢出 → 贴左边
	if tooltip_pos.x < 0:
		tooltip_pos.x = 16
	# 下边溢出 → 上移
	if tooltip_pos.y + tooltip_size.y > viewport_size.y:
		tooltip_pos.y = viewport_size.y - tooltip_size.y - 16
	# 上边溢出 → 贴上
	if tooltip_pos.y < 0:
		tooltip_pos.y = 16

	_tooltip_panel.position = tooltip_pos
	_tooltip_panel.visible = true