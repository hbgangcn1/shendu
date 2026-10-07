## 占位版感官反馈效果
## 数字弹出、屏幕震动、闪烁等

# implements: design/08-ui-layout-spec.md
# implements_philosophy: rule_9_progressive_disclosure
# avoids_red_line: red_6_ui_overload

class_name FeedbackEffects
extends Node2D

# ==================== 效果节点 ====================

var _tween: Tween = null
var _camera: Camera2D = null

# ==================== 初始化 ====================

func _ready() -> void:
	# 获取或创建摄像机
	_camera = get_viewport().get_camera_2d()
	if _camera == null:
		_camera = Camera2D.new()
		add_child(_camera)

# ==================== 数字弹出效果 ====================

## 显示伤害数字
func show_damage_number(position: Vector2, damage: int, element: WuXing.Element) -> void:
	_show_number_popup(position, str(damage), WuXing.get_element_color(element), 60, 0.8)

## 显示治疗数字
func show_heal_number(position: Vector2, amount: int) -> void:
	_show_number_popup(position, "+" + str(amount), Color.GREEN, 60, 0.8)

## 显示护盾数字
func show_shield_number(position: Vector2, amount: int) -> void:
	_show_number_popup(position, "+" + str(amount), Color.CYAN, 40, 0.6)

## 通用数字弹出效果
func _show_number_popup(position: Vector2, text: String, color: Color, y_offset: float, duration: float) -> void:
	var number_label := _create_number_label(text, position)
	number_label.modulate = color
	add_child(number_label)

	# 动画：向上飘动 + 淡出
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(number_label, "position:y", position.y - y_offset, duration)
	tween.tween_property(number_label, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(number_label.queue_free)

# ==================== 屏幕震动效果 ====================

## 执行屏幕震动
const DEFAULT_SHAKE_INTERVAL := 0.05  # 每次震动间隔（秒）

func shake_screen(intensity: float = 5.0, duration: float = 0.2) -> void:
	if _camera == null:
		return

	var original_position := _camera.position
	var shake_count := int(duration / DEFAULT_SHAKE_INTERVAL)

	for i in range(shake_count):
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		_camera.position = original_position + offset
		await get_tree().create_timer(DEFAULT_SHAKE_INTERVAL).timeout

	_camera.position = original_position

# ==================== 闪烁效果 ====================

## 闪烁节点
func flash_node(node: Node2D, color: Color = Color.WHITE, duration: float = 0.3) -> void:
	if node == null:
		return

	var original_modulate := node.modulate
	node.modulate = color

	var tween: Tween = create_tween()
	tween.tween_property(node, "modulate", original_modulate, duration)

# ==================== 五行相生链特效 ====================

## 显示相生链触发特效
func show_generation_chain_effect(chain: Array, center_position: Vector2) -> void:
	# 记录创建的符号以便清理
	var created_symbols: Array[Label] = []
	
	# 创建五行符号特效
	for i in range(chain.size()):
		var element: WuXing.Element = chain[i]
		var angle := (i * TAU) / chain.size()
		var radius := 100.0
		var offset := Vector2(cos(angle), sin(angle)) * radius
		var pos := center_position + offset

		# 创建元素符号
		var symbol := _create_element_symbol(element, pos)
		add_child(symbol)
		created_symbols.append(symbol)

		# 动画：旋转 + 放大
		var tween: Tween = create_tween()
		tween.set_loops(2)
		tween.tween_property(symbol, "rotation", TAU, 0.5)
		tween.parallel().tween_property(symbol, "scale", Vector2(1.5, 1.5), 0.25)
		tween.tween_property(symbol, "scale", Vector2(1.0, 1.0), 0.25)

	# 清理
	await get_tree().create_timer(1.0).timeout
	for symbol in created_symbols:
		if symbol and is_instance_valid(symbol):
			symbol.queue_free()

# ==================== 内部方法 ====================

func _create_number_label(text: String, position: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 设置字体大小（需要加载字体）
	# label.add_theme_font_size_override("font_size", 24)

	return label

func _create_element_symbol(element: WuXing.Element, position: Vector2) -> Label:
	var label := Label.new()
	label.text = WuXing.get_element_name(element)
	label.position = position
	label.modulate = WuXing.get_element_color(element)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 设置字体大小
	# label.add_theme_font_size_override("font_size", 32)

	return label
