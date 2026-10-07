## 主菜单 / Demo 入口
## 演示模式启动器

# implements: design/01-player-experience.md
# implements_philosophy: rule_7_daily_gentle_not_fomo
# avoids_red_line: red_8_tutorial_hell

extends Control

# ==================== 节点引用 ====================

@onready var start_button: Button = %StartButton
@onready var new_game_button: Button = %NewGameButton
@onready var quit_button: Button = %QuitButton
@onready var title_label: Label = %TitleLabel

# ==================== 存档系统 ====================

var _save_system: Node = null
var _has_auto_save: bool = false

# ==================== 初始化 ====================

func _ready() -> void:
	# 初始化存档系统（动态加载避免 class_name 注册顺序问题）
	var SaveSystemScript: GDScript = load("res://scripts/core/save_system.gd")
	_save_system = SaveSystemScript.new()
	add_child(_save_system)
	_has_auto_save = _save_system.has_auto_save()

	# 应用墨韵赛博 UI 主题
	_apply_theme()

	# 连接按钮信号
	start_button.pressed.connect(_on_start_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# 设置标题和副标题
	title_label.text = "蜃 都"
	# 根据存档状态更新按钮文字
	if _has_auto_save:
		start_button.text = "继续游戏"
		new_game_button.visible = true
	else:
		start_button.text = "开始游戏"
		new_game_button.visible = false  # 无存档时隐藏，避免功能重叠
	print("主菜单：菜单加载完成，自动存档: %s" % ("存在" if _has_auto_save else "无"))

	# 2026-07-29 fix: headless/AI Player mode 自动进入游戏
	# 根因：main_menu 卡在原地等用户点击 start_button，headless 模式下没用户 → 永远卡死
	# character_select 自动 confirm 已修（commit 3ae02a6）但 main_menu 不自动 transition 永远到不了 character_select
	# 修复：检测 --qa-auto-run flag 时调 _on_start_pressed()，模拟点 start_button
	if OS.get_cmdline_user_args().has("--qa-auto-run"):
		print("主菜单：headless 模式自动开始游戏 (跳过 start_button click)")
		# 延迟一帧让 _ready 完全结束再调（避免在 _ready 内修改 tree）
		await get_tree().process_frame
		_on_start_pressed()

func _apply_theme() -> void:
	# 标题样式
	UITheme.apply_title_label(title_label, UITheme.SIZE_HERO)
	# 玉牌风按钮（主菜单专用）
	UITheme.apply_jade_button(start_button)
	UITheme.apply_jade_button(new_game_button)
	UITheme.apply_jade_button(quit_button)

# ==================== 按钮事件 ====================

func _on_start_pressed() -> void:
	if _has_auto_save:
		# 加载自动存档
		var save_data: Dictionary = _save_system.load_auto_save()
		if not save_data.is_empty():
			# 恢复游戏状态
			GameState.character_id = save_data.get("character_id", "")
			GameState.hp = save_data.get("hp", 80)
			GameState.max_hp = save_data.get("max_hp", 80)
			GameState.spirit_stones = save_data.get("spirit_stones", 0)
			GameState.dao_xing = save_data.get("dao_xing", 0)
			GameState.total_dao_xing = save_data.get("total_dao_xing", 0)
			GameState.current_realm = save_data.get("current_realm", 0)
			GameState.current_node_id = save_data.get("current_node_id", "")
			GameState.visited_node_ids = save_data.get("visited_node_ids", [])
			GameState.collection = save_data.get("collection", [])
			GameState.deck = save_data.get("deck", [])
			GameState.deck_max_size = save_data.get("deck_max_size", 25)
			GameState.deck_removal_count = save_data.get("deck_removal_count", 0)
			GameState.is_boss_defeated = save_data.get("is_boss_defeated", [])
			print("主菜单：加载自动存档成功")
			get_tree().change_scene_to_file("res://scenes/map.tscn")
			return
	print("主菜单：继续游戏（无存档，进入选角）")
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_new_game_pressed() -> void:
	# 删除旧存档，开始全新游戏
	if _has_auto_save:
		_save_system.delete_save("auto_save")
		_has_auto_save = false
	GameState.reset_run()
	print("主菜单：新游戏")
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_quit_pressed() -> void:
	print("主菜单：退出游戏")
	get_tree().quit()

# ==================== 输入处理 ====================

func _unhandled_input(_event: InputEvent) -> void:
	# 按 Enter 键开始游戏
	if _event is InputEventKey:
		if _event.pressed and _event.keycode == KEY_ENTER:
			_on_start_pressed()
		# 按 ESC 键退出
		elif _event.pressed and _event.keycode == KEY_ESCAPE:
			_on_quit_pressed()
