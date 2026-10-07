## 通关画面
## 金丹期 Boss 击败后显示

# implements: design/04-progression-experience.md
# implements_philosophy: rule_2_failure_must_have_meaning

extends Control

@onready var title_label: Label = %TitleLabel
@onready var stats_label: Label = %StatsLabel
@onready var back_button: Button = %BackButton

func _ready() -> void:
	title_label.text = "通关！"
	UITheme.apply_title_label(title_label, 48)
	UITheme.apply_body_label(stats_label, 16)
	UITheme.apply_button(back_button)

	# 应用半透明遮罩底板
	var backdrop: PanelContainer = get_node_or_null("Backdrop")
	if backdrop:
		UITheme.apply_panel(backdrop, true)

	stats_label.text = "恭喜你击败了通天塔守卫，完成了金丹期的试炼。\n\n境界: %s\nHP: %d/%d\n灵石: %d\n道行: %d\n牌库: %d/%d\n\n更多境界将在后续版本开放。" % [
		GameState.get_realm_name(),
		GameState.hp, GameState.max_hp,
		GameState.spirit_stones,
		GameState.dao_xing,
		GameState.deck.size(), GameState.deck_max_size,
	]
	back_button.pressed.connect(func():
		GameState.reset_run()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
