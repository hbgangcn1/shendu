## 蜃都 Legend 面板
##
## 显示所有节点类型的图标 + 中文 + 配色
## 默认折叠，右下角"?" 按钮 / L 键切换
##
## 2026-08-09 实现 (P0 #2 节点 tooltip + legend — epic-rollup-35e824f6)
## 覆盖 workboard cards: 64f66065, b35b8cf1, 755bad39
## 设计文档: design/09-map-system-spec.md

extends PanelContainer

const MapNodeScript: GDScript = preload("res://scripts/core/map_node.gd")
const NodeType: Dictionary = MapNodeScript.NodeType

const TYPE_LIST := [
	NodeType.COMBAT,
	NodeType.ELITE,
	NodeType.EVENT,
	NodeType.SHOP,
	NodeType.REST,
	NodeType.BOSS,
	NodeType.SECRET_ROOM,
]

const COLLAPSED_SIZE := Vector2(56, 56)
const EXPANDED_SIZE := Vector2(260, 380)


func _ready() -> void:
	_build()
	visible = false  # 默认折叠


func _build() -> void:
	# 整体 panel 样式
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = UITheme.CYAN_NEON
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 8
	style.shadow_offset = Vector2(2, 2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "节点图例"
	UITheme.apply_title_label(title, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "(L 键切换)"
	UITheme.apply_secondary_label(hint, 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	# 7 种类型行
	for type_id in TYPE_LIST:
		var info: Dictionary = NodeTooltip.TOOLTIP_DATA.get(type_id, {})
		if info.is_empty():
			continue
		vbox.add_child(_build_type_row(info))


func _build_type_row(info: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	# 颜色方块（24x24）
	var color_rect := ColorRect.new()
	color_rect.custom_minimum_size = Vector2(24, 24)
	color_rect.size = Vector2(24, 24)
	color_rect.color = info["color"]
	hbox.add_child(color_rect)

	# 图标 + 中文
	var label := Label.new()
	label.text = "%s  %s" % [info["icon"], info["title"]]
	UITheme.apply_body_label(label, 16)
	hbox.add_child(label)

	return hbox


# ==================== 折叠/展开 ====================

func toggle() -> void:
	visible = not visible


func expand() -> void:
	visible = true


func collapse() -> void:
	visible = false
