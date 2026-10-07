## 蜃都 墨韵赛博 UI 主题
## 基于 2026-06-25 Council UI 设计规范
## Autoload: UITheme
# implements: design/08-ui-layout-spec.md
# implements_philosophy: rule_9_progressive_disclosure
# avoids_red_line: red_6_ui_overload

extends Node

# ==================== 色彩系统 ====================

# 主色
const INK_BLACK := Color("0A0A0A")        # 墨黑 - 遮罩/背景
const RICE_PAPER := Color("1A1A1E")       # 宣纸灰 - 面板底色
const CINNABAR := Color("C23B22")         # 朱砂红 - 警告/印章
const CYAN_NEON := Color("00FFCC")        # 青磷 - 主霓虹
const GOLD := Color("FFD700")             # 金黄 - 次强调

# 文字色
const TEXT_PRIMARY := Color("E8E0D0")     # 宣纸白 - 主文字
const TEXT_SECONDARY := Color("8A8070")   # 灰褐 - 次文字
const TEXT_DISABLED := Color("4A4540")    # 暗灰 - 禁用

# 元素色
const ELEM_METAL := Color("C0C0C0")
const ELEM_WOOD := Color("2ECC71")
const ELEM_WATER := Color("2980B9")
const ELEM_FIRE := Color("E74C3C")
const ELEM_EARTH := Color("D4A017")

# 元素霓虹色（高亮用）
const ELEM_METAL_GLOW := Color("FFD700")
const ELEM_WOOD_GLOW := Color("00FF88")
const ELEM_WATER_GLOW := Color("00CCFF")
const ELEM_FIRE_GLOW := Color("FF6600")
const ELEM_EARTH_GLOW := Color("FFAA00")

# 霓虹色使用上限：主色 60%、辅助 30%、强调 10%

# ==================== 字号阶梯（统一全游戏） ====================

const SIZE_HERO: int = 85     ## 页面主标题（如主菜单“蜃都”）
const SIZE_H1: int = 48       ## H1 页面标题（如“选择角色”）
const SIZE_H2: int = 28       ## H2 区块标题（如“牌组管理”）
const SIZE_H3: int = 22       ## H3 模块名/主要按钮
const SIZE_BODY: int = 18     ## 正文（默认 label）
const SIZE_HELPER: int = 15   ## 辅助/说明文字
const SIZE_NUMERIC: int = 20  ## 数值（HP/灵石/道行）

# ==================== 字体 ====================

# 正文字体（思源宋体 / 系统宋体）
var font_body: Font
# 数值等宽字体
var font_mono: Font

# ==================== StyleBox 缓存 ====================

var panel_style: StyleBoxFlat
var panel_overlay_style: StyleBoxFlat
var button_normal: StyleBoxFlat
var button_hover: StyleBoxFlat
var button_pressed: StyleBoxFlat
var button_disabled: StyleBoxFlat

## 玉牌按钮（主菜单/选择界面专用）
var button_jade_normal: StyleBoxFlat
var button_jade_hover: StyleBoxFlat
var button_jade_pressed: StyleBoxFlat

# ==================== 初始化 ====================

func _ready() -> void:
	_init_fonts()
	_init_styles()
	print("UITheme: 墨韵赛博主题已加载")

func _init_fonts() -> void:
	# 使用系统默认字体，后续可替换为自定义字体
	font_body = ThemeDB.fallback_font
	font_mono = ThemeDB.fallback_font

func _init_styles() -> void:
	# --- 面板样式：水墨底板 ---
	panel_style = StyleBoxFlat.new()
	panel_style.bg_color = RICE_PAPER
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(CYAN_NEON, 0.3)
	panel_style.corner_radius_top_left = 2
	panel_style.corner_radius_top_right = 2
	panel_style.corner_radius_bottom_right = 2
	panel_style.corner_radius_bottom_left = 2
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 4
	panel_style.shadow_offset = Vector2(0, 2)

	# --- 遮罩面板：60-75% 不透明度 ---
	panel_overlay_style = StyleBoxFlat.new()
	panel_overlay_style.bg_color = Color(INK_BLACK, 0.7)
	panel_overlay_style.border_width_left = 0
	panel_overlay_style.border_width_top = 0
	panel_overlay_style.border_width_right = 0
	panel_overlay_style.border_width_bottom = 0

	# --- 按钮：普通态 ---
	button_normal = StyleBoxFlat.new()
	button_normal.bg_color = Color("1E1E22")
	button_normal.border_width_left = 1
	button_normal.border_width_top = 1
	button_normal.border_width_right = 1
	button_normal.border_width_bottom = 1
	button_normal.border_color = Color(CYAN_NEON, 0.4)
	button_normal.corner_radius_top_left = 2
	button_normal.corner_radius_top_right = 2
	button_normal.corner_radius_bottom_right = 2
	button_normal.corner_radius_bottom_left = 2

	# --- 按钮：Hover 态（霓虹辉光） ---
	button_hover = button_normal.duplicate()
	button_hover.bg_color = Color("252530")
	button_hover.border_color = CYAN_NEON
	button_hover.shadow_color = Color(CYAN_NEON, 0.3)
	button_hover.shadow_size = 6
	button_hover.shadow_offset = Vector2(0, 0)

	# --- 按钮：按下态 ---
	button_pressed = button_normal.duplicate()
	button_pressed.bg_color = Color("0E0E12")
	button_pressed.border_color = Color(CYAN_NEON, 0.6)

	# --- 按钮：禁用态 ---
	button_disabled = StyleBoxFlat.new()
	button_disabled.bg_color = Color("151518")
	button_disabled.border_width_left = 1
	button_disabled.border_width_top = 1
	button_disabled.border_width_right = 1
	button_disabled.border_width_bottom = 1
	button_disabled.border_color = Color(TEXT_DISABLED, 0.3)
	button_disabled.corner_radius_top_left = 2
	button_disabled.corner_radius_top_right = 2
	button_disabled.corner_radius_bottom_right = 2
	button_disabled.corner_radius_bottom_left = 2

	# --- 玉牌按钮：Normal（墨绿调+顶部高光）---
	button_jade_normal = StyleBoxFlat.new()
	button_jade_normal.bg_color = Color(0.05, 0.1, 0.08, 0.88)
	button_jade_normal.border_width_left = 1
	button_jade_normal.border_width_top = 1
	button_jade_normal.border_width_right = 1
	button_jade_normal.border_width_bottom = 1
	button_jade_normal.border_color = Color(CYAN_NEON, 0.5)
	button_jade_normal.corner_radius_top_left = 4
	button_jade_normal.corner_radius_top_right = 4
	button_jade_normal.corner_radius_bottom_left = 4
	button_jade_normal.corner_radius_bottom_right = 4
	button_jade_normal.content_margin_left = 16
	button_jade_normal.content_margin_right = 16
	button_jade_normal.content_margin_top = 10
	button_jade_normal.content_margin_bottom = 10

	# --- 玉牌按钮：Hover（霓虹辉光）---
	button_jade_hover = button_jade_normal.duplicate()
	button_jade_hover.bg_color = Color(0.08, 0.15, 0.12, 0.92)
	button_jade_hover.border_color = CYAN_NEON
	button_jade_hover.shadow_color = Color(CYAN_NEON, 0.35)
	button_jade_hover.shadow_size = 10
	button_jade_hover.shadow_offset = Vector2(0, 0)

	# --- 玉牌按钮：Pressed（按下变深）---
	button_jade_pressed = button_jade_normal.duplicate()
	button_jade_pressed.bg_color = Color(0.03, 0.06, 0.05, 0.95)
	button_jade_pressed.border_color = Color(CYAN_NEON, 0.7)

# ==================== 工具方法 ====================

## 给节点应用面板样式
func apply_panel(node: PanelContainer, use_overlay: bool = false) -> void:
	if use_overlay:
		node.add_theme_stylebox_override("panel", panel_overlay_style)
	else:
		node.add_theme_stylebox_override("panel", panel_style)

## 给节点应用按钮全套样式
func apply_button(node: Button) -> void:
	node.add_theme_stylebox_override("normal", button_normal)
	node.add_theme_stylebox_override("hover", button_hover)
	node.add_theme_stylebox_override("pressed", button_pressed)
	node.add_theme_stylebox_override("disabled", button_disabled)
	node.add_theme_color_override("font_color", TEXT_PRIMARY)
	node.add_theme_color_override("font_hover_color", CYAN_NEON)
	node.add_theme_color_override("font_pressed_color", Color(CYAN_NEON, 0.8))
	node.add_theme_color_override("font_disabled_color", TEXT_DISABLED)

## 玉牌按钮（主菜单/选择界面专用，含霓虹辉光）
func apply_jade_button(node: Button) -> void:
	node.add_theme_stylebox_override("normal", button_jade_normal)
	node.add_theme_stylebox_override("hover", button_jade_hover)
	node.add_theme_stylebox_override("pressed", button_jade_pressed)
	node.add_theme_stylebox_override("disabled", button_disabled)
	node.add_theme_color_override("font_color", TEXT_PRIMARY)
	node.add_theme_color_override("font_hover_color", CYAN_NEON)
	node.add_theme_color_override("font_pressed_color", Color(CYAN_NEON, 0.9))
	node.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	if node.get_theme_font_size("font_size") <= 0:
		node.add_theme_font_size_override("font_size", SIZE_H3)

## 应用标题样式
func apply_title_label(node: Label, size: int = SIZE_H1) -> void:
	node.add_theme_color_override("font_color", TEXT_PRIMARY)
	node.add_theme_font_size_override("font_size", size)

## 应用正文样式
func apply_body_label(node: Label, size: int = SIZE_BODY) -> void:
	node.add_theme_color_override("font_color", TEXT_PRIMARY)
	node.add_theme_font_size_override("font_size", size)

## 应用次要文字样式
func apply_secondary_label(node: Label, size: int = SIZE_HELPER) -> void:
	node.add_theme_color_override("font_color", TEXT_SECONDARY)
	node.add_theme_font_size_override("font_size", size)

## 应用数值样式（如 HP/费用/伤害）
func apply_numeric_label(node: Label, size: int = SIZE_NUMERIC) -> void:
	node.add_theme_color_override("font_color", TEXT_PRIMARY)
	node.add_theme_font_size_override("font_size", size)

## 获取元素颜色
func get_element_color(element: int) -> Color:
	match element:
		0: return ELEM_METAL
		1: return ELEM_WOOD
		2: return ELEM_WATER
		3: return ELEM_FIRE
		4: return ELEM_EARTH
		_: return TEXT_PRIMARY

## 获取元素霓虹色
func get_element_glow(element: int) -> Color:
	match element:
		0: return ELEM_METAL_GLOW
		1: return ELEM_WOOD_GLOW
		2: return ELEM_WATER_GLOW
		3: return ELEM_FIRE_GLOW
		4: return ELEM_EARTH_GLOW
		_: return CYAN_NEON

## 创建半透明遮罩（用于文字安全区）
func create_overlay_rect() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(INK_BLACK, 0.7)
	return rect
