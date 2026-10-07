## 存档/读档系统
## 管理游戏存档的保存、加载、删除

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name SaveSystem
extends Node

const SAVE_DIR := "user://saves/"
const AUTO_SAVE_NAME := "auto_save"
const MAX_SAVE_SLOTS := 3

signal save_completed(slot_name: String)
signal save_failed(reason: String)
signal load_completed(slot_name: String)
signal load_failed(reason: String)

## 保存游戏状态
func save_game(slot_name: String, game_state: Dictionary) -> bool:
	# 确保存档目录存在
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var save_data := {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"play_time": game_state.get("play_time", 0),
		"state": game_state,
	}

	var json_str := JSON.stringify(save_data, "\t")
	var file_path := SAVE_DIR + slot_name + ".json"

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		save_failed.emit("无法写入文件: %s" % file_path)
		return false

	file.store_string(json_str)
	file.close()

	save_completed.emit(slot_name)
	print("Save: 游戏已保存到 %s" % file_path)
	return true

## 加载游戏状态
func load_game(slot_name: String) -> Dictionary:
	var file_path := SAVE_DIR + slot_name + ".json"

	if not FileAccess.file_exists(file_path):
		load_failed.emit("存档不存在: %s" % slot_name)
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		load_failed.emit("无法读取文件: %s" % file_path)
		return {}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		load_failed.emit("存档格式错误: %s" % slot_name)
		return {}

	var save_data: Dictionary = json.data
	var version: int = save_data.get("version", 0)
	if version < 1:
		load_failed.emit("存档版本过旧: v%d" % version)
		return {}

	load_completed.emit(slot_name)
	print("Save: 存档 %s 已加载（%s）" % [slot_name, save_data.get("timestamp", "?")])
	return save_data.get("state", {})

## 删除存档
func delete_save(slot_name: String) -> bool:
	var file_path := SAVE_DIR + slot_name + ".json"
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
		print("Save: 存档 %s 已删除" % slot_name)
		return true
	return false

## 获取所有存档列表
func get_save_list() -> Array:
	var saves: Array = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return saves

	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var slot_name := file_name.trim_suffix(".json")
			var meta := get_save_meta(slot_name)
			if not meta.is_empty():
				saves.append(meta)
		file_name = dir.get_next()
	dir.list_dir_end()

	# 按时间排序（最新在前）
	saves.sort_custom(func(a, b): return a.get("timestamp", "") > b.get("timestamp", ""))
	return saves

## 获取存档元数据（不加载完整数据）
func get_save_meta(slot_name: String) -> Dictionary:
	var file_path := SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(file_path):
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		return {}

	var data: Dictionary = json.data
	return {
		"slot_name": slot_name,
		"timestamp": data.get("timestamp", ""),
		"play_time": data.get("play_time", 0),
		"realm": data.get("state", {}).get("realm", 0),
		"dao_xing": data.get("state", {}).get("dao_xing", 0),
	}

## 自动存档
func auto_save(game_state: Dictionary) -> bool:
	return save_game(AUTO_SAVE_NAME, game_state)

## 加载自动存档
func load_auto_save() -> Dictionary:
	return load_game(AUTO_SAVE_NAME)

## 检查自动存档是否存在
func has_auto_save() -> bool:
	return FileAccess.file_exists(SAVE_DIR + AUTO_SAVE_NAME + ".json")
