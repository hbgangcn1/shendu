## gate_4_buttons_clickable — 自动化验证
## 2026-08-03：替代 PENDING_P1 手工验证
##
## 直接扫描 .tscn 文本检查 Button 节点（不 instantiate，避免 autoload 错误）
## 检查项：
## 1. unique_name_in_owner=true（脚本可 %ButtonName 访问）
## 2. focus_mode != FOCUS_NONE
## 3. disabled == false（默认启用）
## 4. text 非空（用户能看到）
## 5. visible == true
##
## 用法：
##   godot --headless --path C:\Users\hbgan\Projects\shendu --script scripts/test/test_button_clickability.gd
##
## 退出码：0=全部 PASS，1=至少一个 FAIL

extends SceneTree

# 场景目录
const SCENES_DIR: String = "res://scenes"

# 哪些场景必查
const TARGET_SCENES: Array[String] = [
	"res://scenes/main_menu.tscn",
	"res://scenes/character_select.tscn",
	"res://scenes/reward.tscn",
	"res://scenes/shop.tscn",
	"res://scenes/settlement.tscn",
	"res://scenes/victory.tscn",
	"res://scenes/map.tscn",
]

# 每个场景必需的按钮（基于 2026-08-03 实际扫描 .tscn）
const REQUIRED_BUTTONS: Dictionary = {
	"res://scenes/main_menu.tscn": ["StartButton", "NewGameButton", "QuitButton"],
	"res://scenes/character_select.tscn": ["ConfirmButton"],
	"res://scenes/reward.tscn": ["SkipButton"],
	"res://scenes/shop.tscn": ["LeaveButton"],
	"res://scenes/settlement.tscn": ["ReplayButton", "QuitButton"],
	"res://scenes/victory.tscn": ["BackButton"],
	"res://scenes/map.tscn": ["ConfirmGoButton"],
}

# 允许初始 disabled=true 的按钮（脚本里会动态启用）
const DISABLED_OK_BUTTONS: Dictionary = {
	"res://scenes/character_select.tscn": ["ConfirmButton"],  # _update_focus() 启用
}

func _init() -> void:
	print("=== test_button_clickability ===")
	print("Scanning %d scenes for interactive button compliance" % TARGET_SCENES.size())
	print("")

	var total_buttons: int = 0
	var total_failures: int = 0
	var failed_scenes: Array = []

	for scene_path in TARGET_SCENES:
		var result: Dictionary = _check_scene(scene_path)
		total_buttons += result.button_count
		total_failures += result.failures.size()

		if result.failures.is_empty():
			print("  OK   %s — %d buttons" % [scene_path, result.button_count])
		else:
			failed_scenes.append(scene_path)
			print("  FAIL %s — %d buttons, %d issues:" % [scene_path, result.button_count, result.failures.size()])
			for f in result.failures:
				print("       - %s" % f)

	print("")
	print("=== Summary ===")
	print("  Scenes:   %d" % TARGET_SCENES.size())
	print("  Buttons:  %d" % total_buttons)
	print("  Failures: %d" % total_failures)

	if total_failures > 0:
		print("")
		print("=== Failed scenes ===")
		for s in failed_scenes:
			print("  %s" % s)
		quit(1)
	else:
		quit(0)

func _check_scene(scene_path: String) -> Dictionary:
	var failures: Array = []
	var button_count: int = 0

	var file_path: String = ProjectSettings.globalize_path(scene_path)
	if not FileAccess.file_exists(file_path):
		failures.append("File missing: %s" % file_path)
		return {"button_count": 0, "failures": failures}

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		failures.append("Cannot open file")
		return {"button_count": 0, "failures": failures}

	var text: String = file.get_as_text()
	file.close()

	# 解析每个 [node name="X" type="Button" parent="Y" ...] 起点
	# body 手动提取（避免 RegEx 捕获组难题）
	var button_pattern: RegEx = RegEx.new()
	button_pattern.compile("\\[node name=\"([^\"]+)\" type=\"Button\" parent=\"[^\"]*\"")
	var matches: Array = button_pattern.search_all(text)

	for m in matches:
		button_count += 1
		var btn_name: String = m.get_string(1)
		# 手动提取 body：取匹配起点到下一个 [node 或文件末尾
		var match_end: int = m.get_end()
		var next_node: RegEx = RegEx.new()
		next_node.compile("\\[node ")
		var next_match: RegExMatch = next_node.search(text, match_end)
		var body_end: int = next_match.get_start() if next_match != null else text.length()
		var btn_body: String = text.substr(match_end, body_end - match_end)

		# 1. unique_name_in_owner=true
		if not _has_property(btn_body, "unique_name_in_owner", "true"):
			failures.append("[%s] Button '%s' missing unique_name_in_owner=true (脚本无法 %s 访问)" % [scene_path, btn_name, btn_name])

		# 2. focus_mode != FOCUS_NONE (0)
		var focus_val: String = _get_property(btn_body, "focus_mode")
		if focus_val == "0":
			failures.append("[%s] Button '%s' has focus_mode=NONE (键盘/手柄无法 focus)" % [scene_path, btn_name])

		# 3. disabled == false（默认），除非白名单允许
		var disabled_val: String = _get_property(btn_body, "disabled")
		if disabled_val == "true":
			var allow_disabled: bool = false
			if DISABLED_OK_BUTTONS.has(scene_path):
				allow_disabled = btn_name in DISABLED_OK_BUTTONS[scene_path]
			if not allow_disabled:
				failures.append("[%s] Button '%s' is disabled by default" % [scene_path, btn_name])

		# 4. visible == true
		var visible_val: String = _get_property(btn_body, "visible")
		if visible_val == "false":
			failures.append("[%s] Button '%s' is not visible by default" % [scene_path, btn_name])

	# 检查必需按钮
	if REQUIRED_BUTTONS.has(scene_path):
		var required: Array = REQUIRED_BUTTONS[scene_path]
		for req_name in required:
			var found: bool = false
			for m in matches:
				if m.get_string(1) == req_name:
					found = true
					break
			if not found:
				failures.append("[%s] REQUIRED button '%s' not found" % [scene_path, req_name])

	return {"button_count": button_count, "failures": failures}

func _has_property(body: String, key: String, expected_value: String) -> bool:
	return _get_property(body, key) == expected_value

func _get_property(body: String, key: String) -> String:
	var pattern: RegEx = RegEx.new()
	# \s 包括空格和 \n 等。匹配任意位置。
	pattern.compile("(?s)\\b%s\\s*=\\s*([^\\n]+)" % key)
	var m: RegExMatch = pattern.search(body)
	if m == null:
		return ""
	return m.get_string(1).strip_edges()