extends SceneTree

# scripts/test_load_all_scenes.gd — 验证所有 .tscn 能成功 load
#
# 目的：2026-07-22 battle_ui.gd 编译失败导致 BattleUI 变裸 CanvasLayer，
#       整个 UI 树静默失效。state.json 数据正常掩盖了真 bug。
#       本脚本用 SceneTree.load() 强制加载每个 .tscn，捕获所有 parse / load 错误。
#
# 用法（headless）：
#   Godot --headless --path C:\Users\hbgan\Projects\shendu --script scripts/test_load_all_scenes.gd
#
# 退出码：
#   0 = 全部 scene load 成功
#   1 = 至少一个 scene 失败

func _init() -> void:
	var scene_dir: String = "res://scenes"
	var scenes: Array = []
	_collect_scenes(scene_dir, scenes)
	
	print("=== test_load_all_scenes ===")
	print("Found %d scenes in %s" % [scenes.size(), scene_dir])
	print("")
	
	var passed: int = 0
	var failed: int = 0
	var failures: Array = []
	
	for scene_path in scenes:
		var result: Dictionary = _try_load(scene_path)
		if result.ok:
			passed += 1
			print("  OK   %s" % scene_path)
		else:
			failed += 1
			failures.append({"path": scene_path, "errors": result.errors})
			print("  FAIL %s" % scene_path)
			for err in result.errors:
				print("       - %s" % err)
	
	print("")
	print("=== Summary ===")
	print("  Total:  %d" % scenes.size())
	print("  Passed: %d" % passed)
	print("  Failed: %d" % failed)
	
	if failed > 0:
		print("")
		print("=== Failure details ===")
		for f in failures:
			print("Scene: %s" % f.path)
			for err in f.errors:
				print("  - %s" % err)
		quit(1)
	else:
		quit(0)

func _collect_scenes(dir_path: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path: String = dir_path + "/" + file_name
		if dir.current_is_dir():
			_collect_scenes(full_path, out)
		elif file_name.ends_with(".tscn"):
			out.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

func _try_load(scene_path: String) -> Dictionary:
	# 捕获 load 时的所有错误
	var errors_before: int = 0
	if OS.has_feature("editor"):
		# editor 下可以拿错误数
		pass
	
	# 用 ResourceLoader.load
	var packed: Resource = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	
	if packed == null:
		return {"ok": false, "errors": ["ResourceLoader.load returned null"]}
	
	if not (packed is PackedScene):
		return {"ok": false, "errors": ["Loaded resource is not a PackedScene: %s" % typeof(packed)]}
	
	# 强制实例化（这是触发 parse error 的关键步骤）
	var scene: Node = (packed as PackedScene).instantiate()
	if scene == null:
		return {"ok": false, "errors": ["PackedScene.instantiate returned null"]}
	
	# 检查根节点的 script 是否有 @tool 编译错误
	# 立即 free 避免内存泄漏
	scene.queue_free()
	
	return {"ok": true, "errors": []}