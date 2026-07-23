## Agent Input — 外部 Agent 操作游戏的输入模拟层
## 通过 Input.parse_input_event 模拟鼠标点击、移动、拖拽、键盘按键
## 只在 --qa-auto-run flag 存在时启用

# implements: design/01-player-experience.md
# implements_philosophy: rule_1_core_loop_first
# agent-infrastructure: loop-engineering

extends Node

# ==================== 公共 API ====================

## 模拟鼠标左键点击屏幕坐标（viewport 坐标，1920×1080 基准）
func click_at(pos: Vector2, delay_ms: int = 50) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = pos
	event.pressed = true
	Input.parse_input_event(event)

	await _wait_ms(delay_ms)

	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = pos
	event.pressed = false
	Input.parse_input_event(event)

## 模拟鼠标移动到指定坐标
func move_to(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	Input.parse_input_event(event)

## 模拟拖拽：从 from_pos 按下，移动到 to_pos，释放
func drag(from_pos: Vector2, to_pos: Vector2, duration_ms: int = 300) -> void:
	# 按下
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from_pos
	press.pressed = true
	Input.parse_input_event(press)

	# 移动
	var steps: int = maxi(1, int(float(duration_ms) / 16.0))
	for i: int in range(steps + 1):
		var t: float = float(i) / float(steps)
		var mid: Vector2 = from_pos.lerp(to_pos, t)
		var motion := InputEventMouseMotion.new()
		motion.position = mid
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await _wait_ms(16)

	# 释放
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to_pos
	release.pressed = false
	Input.parse_input_event(release)

## 模拟按键（单个）
func press_key(keycode: Key, delay_ms: int = 50) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)

	await _wait_ms(delay_ms)

	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

## 按 UI 控件中心点击（安全封装：先检查节点存在）
func click_control(control: Control, delay_ms: int = 50) -> bool:
	if control == null or not is_instance_valid(control):
		push_warning("AgentInput: 尝试点击 null 或已释放的 Control")
		return false
	if not control.visible:
		push_warning("AgentInput: 控件不可见 %s" % control.name)
		return false
	var center: Vector2 = control.get_global_rect().get_center()
	await click_at(center, delay_ms)
	return true

## 等待毫秒（异步，用于模拟人类延迟）
func _wait_ms(ms: int) -> void:
	if ms <= 0:
		return
	await Engine.get_main_loop().create_timer(float(ms) / 1000.0).timeout
