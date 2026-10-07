## 玩家立绘占位
## Council B-4：用 GradientTexture2D + ColorRect 程序生成角色剪影
## 最终美术到位后只需替换 Portrait.texture，无需改布局

# implements: design/08-ui-layout-spec.md
# implements_philosophy: rule_9_progressive_disclosure
# avoids_red_line: red_6_ui_overload

class_name PlayerPortraitOverlay
extends Control

const ELEM_COLORS := {
	0: Color("C0C0C0"),  # METAL
	1: Color("2ECC71"),  # WOOD
	2: Color("2980B9"),  # WATER
	3: Color("E74C3C"),  # FIRE
	4: Color("D4A017"),  # EARTH
}

# ==================== 节点引用 ====================

@onready var portrait: ColorRect = %Portrait
@onready var aura: ColorRect = %Aura
@onready var name_label: Label = %NameLabel

# ==================== 状态 ====================

var character_id: String = "chenmo"
var element: int = 3  ## FIRE

# ==================== 初始化 ====================

func _ready() -> void:
	# 必须 IGNORE，不拦截 panel 的 gui_input 事件
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if aura:
		aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if portrait:
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if name_label:
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 启动呼吸灯动画
	_start_aura_breath()

# ==================== 配置 ====================

## 设置角色（从 GameState.character_id 推断元素）
func setup(p_character_id: String, p_name: String, p_element: int) -> void:
	character_id = p_character_id
	element = p_element
	if name_label:
		name_label.text = p_name
	_apply_visual()

# ==================== 视觉生成 ====================

func _apply_visual() -> void:
	if not portrait:
		return

	var color: Color = ELEM_COLORS.get(element, Color.GRAY)
	# 立绘占位：渐变（深色 → 元素色 30%）
	var gradient := Gradient.new()
	gradient.set_color(0, color.darkened(0.6))
	gradient.set_color(1, Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 320
	tex.height = 400
	portrait.texture = tex

	# 元素光环
	if aura:
		aura.color = Color(color.r, color.g, color.b, 0.3)

# ==================== 动画 ====================

## 呼吸灯动画（alpha 0.3 ↔ 0.6，2s 周期）
func _start_aura_breath() -> void:
	if not aura:
		return
	var tween := create_tween().set_loops()
	tween.tween_property(aura, "modulate:a", 0.5, 1.0)
	tween.tween_property(aura, "modulate:a", 1.0, 1.0)
