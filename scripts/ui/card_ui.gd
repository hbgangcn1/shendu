## 卡牌 UI 组件
## 显示单张卡牌的信息和交互

# implements: design/08-ui-layout-spec.md
# implements_philosophy: rule_9_progressive_disclosure
# avoids_red_line: red_6_ui_overload

class_name CardUI
extends PanelContainer

const CardDataResource := preload("res://scripts/core/card_data.gd")

# 卡牌美术资产（Robert 2026-06-29 反馈集成）
const CARD_FRAME_BASE := preload("res://assets/images/ui/card_frame_base_001.png")
const RARITY_FRAMES := preload("res://assets/images/ui/rarity_frames.png")

## 稀有度颜色（除按 frame 外，也加一点底色增强可读性）
const RARITY_TINT := {
	0: Color(0.95, 0.95, 1.0, 0.05),  # common - 几乎透明
	1: Color(0.5, 0.7, 1.0, 0.08),    # rare - 浅蓝光
	2: Color(0.7, 0.4, 1.0, 0.1),     # epic - 紫光
	3: Color(1.0, 0.78, 0.2, 0.12),   # legend - 金光
}

# ==================== 信号 ====================

signal card_clicked

# ==================== UI 节点 ====================

@onready var card_name_label: Label = %CardNameLabel
@onready var cost_label: Label = %CostLabel
@onready var description_label: Label = %DescriptionLabel
@onready var portrait: TextureRect = %Portrait
@onready var card_frame: TextureRect = %CardFrame
@onready var rarity_overlay: ColorRect = %RarityOverlay

# ==================== 卡牌数据 ====================

var card_data: CardDataResource = null

# ==================== 初始化 ====================

func setup(card: CardDataResource) -> void:
	card_data = card
	_update_display()

# ==================== 显示更新 ====================

func _update_display() -> void:
	if card_data == null:
		return

	# 确保 UI 节点已初始化
	if card_name_label == null or cost_label == null or description_label == null:
		return

	# 稀有度装饰（Robert 2026-06-29 反馈集成）
	if card_frame:
		card_frame.texture = CARD_FRAME_BASE
	if rarity_overlay:
		var rarity_tint: Color = RARITY_TINT.get(card_data.rarity, RARITY_TINT[0])
		rarity_overlay.color = rarity_tint

	card_name_label.text = card_data.name
	cost_label.text = str(card_data.cost)

	# 构建描述：基础描述 + 效果数值
	var desc: String = card_data.description
	var stats: Array = []
	if card_data.damage > 0:
		stats.append("伤害 %d" % card_data.damage)
	if card_data.block > 0:
		stats.append("格挡 %d" % card_data.block)
	if card_data.heal > 0:
		stats.append("治疗 %d" % card_data.heal)
	if card_data.draw_cards > 0:
		stats.append("抽牌 %d" % card_data.draw_cards)
	if not stats.is_empty():
		if not desc.is_empty():
			desc += "\n"
		desc += " | ".join(stats)
	# 2026-08-09 P1 #5 (epic-rollup-35e824f6): 8 字简写优先显示
	var short: String = card_data.short_desc
	if short.is_empty() and not card_data.description.is_empty():
		short = _truncate_to_eight(card_data.description)
	description_label.text = short if not short.is_empty() else desc
	# 提亮文字颜色 + outline 描边，提升小尺寸卡牌（165x220）下的可读性
	description_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	description_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	description_label.add_theme_constant_override("outline_size", 2)
	card_name_label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	card_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	card_name_label.add_theme_constant_override("outline_size", 3)
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))  # 金色费用


## 2026-08-09 P1 #5: 截取 description 到 8 字以内（中文字符计数）
func _truncate_to_eight(text: String) -> String:
	if text.is_empty():
		return ""
	var clean: String = text.replace("\n", "").strip_edges()
	var count: int = 0
	var result: String = ""
	for c in clean:
		var ch: String = c
		if ch == " " or (ch.length() == 1 and ch.is_valid_int()):
			continue
		result += ch
		count += 1
		if count >= 8:
			break
	return result

	# 添加卡牌完整提示文本
	var tooltip_parts: Array = []
	tooltip_parts.append(card_data.name)
	tooltip_parts.append("费用: %d" % card_data.cost)
	tooltip_parts.append("元素: %s" % WuXing.ELEMENT_NAMES.get(int(card_data.element), "无"))
	if card_data.description != "":
		tooltip_parts.append(card_data.description)
	if card_data.damage > 0:
		tooltip_parts.append("伤害: %d" % card_data.damage)
	if card_data.block > 0:
		tooltip_parts.append("格挡: %d" % card_data.block)
	if card_data.heal > 0:
		tooltip_parts.append("治疗: %d" % card_data.heal)
	if card_data.draw_cards > 0:
		tooltip_parts.append("抽牌: %d" % card_data.draw_cards)
	# 修复 2026-07-22: card_data.gd 没有 exhaust/erode 字段，统一通过 tags 数组判断
	if card_data.tags.has("exhaust"):
		tooltip_parts.append("【消耗】使用后移出战斗")
	if card_data.tags.has("erode"):
		tooltip_parts.append("【侵蚀】使用后侵蚀 +1")
	if card_data.tags.size() > 0:
		tooltip_parts.append("标签: %s" % ", ".join(card_data.tags))
	description_label.tooltip_text = "\n".join(tooltip_parts)
	cost_label.tooltip_text = "费用: %d 灵力" % card_data.cost
	card_name_label.tooltip_text = description_label.tooltip_text

	# 设置元素颜色与图标（图标节点可选，未配置时静默）
	_set_element_color(card_data.element)
	_load_element_icon()
	
	# 加载卡牌立绘
	_load_portrait()

func _load_portrait() -> void:
	if portrait == null or card_data == null:
		return
	if card_data.art_path != "" and ResourceLoader.exists(card_data.art_path):
		portrait.texture = load(card_data.art_path)
	else:
		# Fallback: use element background
		var elem_names := ["metal", "wood", "water", "fire", "earth"]
		var elem_idx: int = clampi(int(card_data.element), 0, 4)
		var fallback_path := "res://assets/images/card_bgs/element_%s.png" % elem_names[elem_idx]
		if ResourceLoader.exists(fallback_path):
			portrait.texture = load(fallback_path)

func _load_element_icon() -> void:
	var element_icon := get_node_or_null("%ElementIcon") as TextureRect
	if element_icon == null or card_data == null:
		return
	var icon_path: String = WuXing.ELEMENT_ICONS.get(int(card_data.element), "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		element_icon.texture = load(icon_path)

func _set_element_color(element: WuXing.Element) -> void:
	var color := UITheme.get_element_color(int(element))
	var glow := UITheme.get_element_glow(int(element))
	var style: StyleBoxFlat = UITheme.panel_style.duplicate()
	style.bg_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.6)
	style.border_color = Color(glow, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

# ==================== 交互 ====================

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("CardUI: 卡牌被点击, card=%s" % card_data.name if card_data else "null")
			card_clicked.emit()
