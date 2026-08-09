## 蜃都 onboarding overlay
## 新玩家首次进游戏的全屏引导
## 半透明黑底 + 中央中式云纹对话框 + 5s 自动消失
##
## 2026-08-09 实现 (P0 #4 onboarding — epic-rollup-35e824f6)
## 覆盖 workboard cards: 8f6028f7, ad50d7d2, 03e4a8c9
## 设计文档: design/01-player-experience.md (onboarding flow)

extends Control

const TITLE_TEXT := "欢迎来到蜃都"
const BODY_TEXT := "这是你的修炼之旅。\n点击亮起的节点开始你的旅程。"
const HINT_TEXT := "提示：按 L 键可随时查看节点图例。"
const FOOTER_TEXT := "(5 秒后自动消失 / 点击任意位置关闭)"

var _fade_tween: Tween = null


func _ready() -> void:
	_build()


func _build() -> void:
	# 全屏 dark overlay（拦截点击让玩家专注）
	var dark := ColorRect.new()
	dark.name = "DarkOverlay"
	dark.color = Color(0, 0, 0, 0.65)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dark)

	# 中央对话框
	var dialog := PanelContainer.new()
	dialog.name = "OnboardingDialog"
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.offset_left = -320.0
	dialog.offset_right = 320.0
	dialog.offset_top = -180.0
	dialog.offset_bottom = 180.0
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = UITheme.CYAN_NEON
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	dialog.add_theme_stylebox_override("panel", style)
	add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = TITLE_TEXT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title_label(title, 30)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# 正文
	var body := Label.new()
	body.text = BODY_TEXT
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_body_label(body, 20)
	vbox.add_child(body)

	# 提示
	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_secondary_label(hint, 16)
	vbox.add_child(hint)

	# 底部说明
	var footer := Label.new()
	footer.text = FOOTER_TEXT
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_secondary_label(footer, 13)
	footer.modulate.a = 0.7
	vbox.add_child(footer)

	# 点击 dark 关闭
	dark.gui_input.connect(_on_dark_clicked)

	# 5s 自动消失
	_fade_tween = create_tween()
	_fade_tween.tween_interval(5.0)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.6)
	_fade_tween.tween_callback(queue_free)


func _on_dark_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_dismiss()


func _dismiss() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_fade_tween.tween_callback(queue_free)