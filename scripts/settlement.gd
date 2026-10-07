## 结算场景
## 本局结束，显示道行统计

# implements: design/04-progression-experience.md
# implements_philosophy: rule_2_failure_must_have_meaning
# avoids_red_line: red_7_difficulty_wall

extends Control

# ==================== 节点引用 ====================

@onready var result_label: Label = %ResultLabel
@onready var realm_label: Label = %RealmLabel
@onready var daoxing_label: Label = %DaoxingLabel
@onready var total_label: Label = %TotalLabel
@onready var replay_button: Button = %ReplayButton
@onready var quit_button: Button = %QuitButton

# ==================== 初始化 ====================

func _ready() -> void:
	# 累加本局道行到跨局累计
	GameState.total_dao_xing += GameState.dao_xing

	# 应用墨韵赛博主题
	var backdrop: PanelContainer = get_node_or_null("Backdrop")
	if backdrop:
		UITheme.apply_panel(backdrop, true)
	UITheme.apply_title_label(result_label, 48)
	UITheme.apply_body_label(realm_label, 18)
	UITheme.apply_body_label(daoxing_label, 18)
	UITheme.apply_body_label(total_label, 18)
	UITheme.apply_button(replay_button)
	UITheme.apply_button(quit_button)

	# 判断胜负并显示原因
	if GameState.hp <= 0:
		result_label.text = "走火入魔"
		result_label.add_theme_color_override("font_color", UITheme.CINNABAR)
		var reason: String = "体力耗尽，HP降至0"
		_show_reason("原因: %s" % reason)
		print("结算：失败 - %s" % reason)
	else:
		result_label.text = "通关！"
		result_label.add_theme_color_override("font_color", UITheme.CYAN_NEON)
		_show_reason("成功突破境界！")
		print("结算：胜利")

	realm_label.text = "境界: %s" % GameState.get_realm_name()
	daoxing_label.text = "本局道行: +%d" % GameState.dao_xing
	total_label.text = "累计道行: %d" % GameState.total_dao_xing

	replay_button.pressed.connect(_on_replay_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	print("结算：境界=%s, 本局道行=%d, 累计=%d" % [
		GameState.get_realm_name(), GameState.dao_xing, GameState.total_dao_xing
	])

func _show_reason(text: String) -> void:
	var reason_label: Label = result_label.get_node_or_null("../ReasonLabel")
	if reason_label:
		reason_label.text = text
		reason_label.add_theme_constant_override("outline_size", 2)
		reason_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))

# ==================== 按钮 ====================

func _on_replay_pressed() -> void:
	GameState.reset_run()
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
