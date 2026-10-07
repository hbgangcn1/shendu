## 自定义确认弹窗
## 替代 Godot 默认 ConfirmationDialog，支持玉牌主题 + 危险样式
## 用于：地图节点确认、移除卡牌、退出游戏等

# implements: design/08-ui-layout-spec.md
# implements_philosophy: rule_9_progressive_disclosure
# avoids_red_line: red_6_ui_overload

class_name ConfirmDialog
extends PanelContainer

signal confirmed
signal cancelled

# ==================== 节点引用 ====================

@onready var _title_label: Label = %TitleLabel
@onready var _message_label: Label = %MessageLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton

# ==================== 状态 ====================

var _is_danger: bool = false

# ==================== 初始化 ====================

func _ready() -> void:
	# 弹窗主体拦截事件
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 按钮信号
	if _confirm_button:
		_confirm_button.pressed.connect(func(): confirmed.emit())
	if _cancel_button:
		_cancel_button.pressed.connect(func(): cancelled.emit())

# ==================== 配置 ====================

## 配置弹窗内容
## is_danger: true 时确认按钮变红色（用于"删除""销毁"等不可逆操作）
func setup(title_text: String, message_text: String, confirm_text: String = "确认", cancel_text: String = "取消", is_danger: bool = false) -> void:
	if _title_label:
		_title_label.text = title_text
	if _message_label:
		_message_label.text = message_text
	if _confirm_button:
		_confirm_button.text = confirm_text
	if _cancel_button:
		_cancel_button.text = cancel_text
	_is_danger = is_danger
	_apply_styles()

## 应用样式（区分普通 vs 危险）
func _apply_styles() -> void:
	UITheme.apply_title_label(_title_label, UITheme.SIZE_H2)
	UITheme.apply_body_label(_message_label, UITheme.SIZE_BODY)
	UITheme.apply_button(_confirm_button)
	UITheme.apply_button(_cancel_button)

	if _is_danger and _confirm_button:
		# 危险按钮：边框用 CINNAR 红
		var danger_hover: StyleBoxFlat = UITheme.button_hover.duplicate()
		danger_hover.border_color = UITheme.CINNAR
		danger_hover.shadow_color = Color(UITheme.CINNAR, 0.4)
		var danger_normal: StyleBoxFlat = UITheme.button_normal.duplicate()
		danger_normal.border_color = Color(UITheme.CINNAR, 0.6)
		_confirm_button.add_theme_stylebox_override("normal", danger_normal)
		_confirm_button.add_theme_stylebox_override("hover", danger_hover)

# ==================== 静态构造 ====================

## 弹出弹窗（静态便捷方法）
## parent: 父节点
## 返回弹窗实例，调用方监听 confirmed/cancelled 信号
static func popup(parent: Node, title_text: String, message_text: String, confirm_text: String = "确认", cancel_text: String = "取消", is_danger: bool = false) -> ConfirmDialog:
	var dialog := preload("res://scenes/confirm_dialog.tscn").instantiate() as ConfirmDialog
	parent.add_child(dialog)
	dialog.setup(title_text, message_text, confirm_text, cancel_text, is_danger)
	# 居中
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dialog.offset_left = -260
	dialog.offset_right = 260
	dialog.offset_top = -150
	dialog.offset_bottom = 150
	dialog.z_index = 200
	return dialog
