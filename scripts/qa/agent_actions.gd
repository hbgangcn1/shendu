## Agent Actions — 提供直接调用场景方法的能力
## 避免 Input.parse_input_event 模拟点击不可靠的问题

# implements: agent-infrastructure
# implements_philosophy: rule_1_core_loop_first
# agent-infrastructure: loop-engineering

extends Node

## 调用当前场景的方法（如果方法存在）
## 用法：AgentActions.call("start_button.pressed.emit()")
##  或者 AgentActions.call_method("_on_new_game_pressed")
func call_method(method_name: String) -> bool:
	var scene := _get_current_scene()
	if scene == null:
		return false
	if not scene.has_method(method_name):
		push_warning("AgentActions: 场景 %s 没有方法 %s" % [scene.name, method_name])
		return false
	scene.call(method_name)
	return true

## 触发按钮的 pressed 信号
func click_button(button: Button) -> bool:
	if button == null or not is_instance_valid(button):
		return false
	if not button.visible:
		return false
	if button.disabled:
		return false
	button.pressed.emit()
	return true

## 通过 unique_name 找按钮并点击
func click_button_by_name(unique_name: String) -> bool:
	var scene := _get_current_scene()
	if scene == null:
		return false
	var node := scene.get_node_or_null("%" + unique_name)
	if node is Button:
		return click_button(node as Button)
	return false

func _get_current_scene() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene